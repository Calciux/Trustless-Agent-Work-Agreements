// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../interfaces/IACPHook.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";

// @title FundTransferHook — EIP-8183 Example 1: 代币 Swap 两阶段托管
// @notice 资本→Provider→swap→产出→Hook→Buyer
//   通过 optParams 在 setBudget 时记录 swap 参数，
//   通过 msg.sender（Escrow）回调查询 getJob 获取角色地址。
//
//   角色流转：
//     fund afterAction:    Client --[USDT 资本]--> Provider
//     submit beforeAction: Provider --[ETH 产出]--> Hook（托管）
//     complete afterAction: Hook --[ETH 产出]--> Buyer
//     reject afterAction:  Hook --[ETH 产出]--> Provider（退还）
//     recoverTokens:       Provider 在过期后取回产出
contract FundTransferHook is IACPHook {
    // ── 函数选择器常量 ──
    bytes4 private constant SEL_SETBUDGET   = bytes4(keccak256("setBudget(uint256,uint256)"));
    bytes4 private constant SEL_SETBUDGET_EXT = bytes4(keccak256("setBudget(uint256,uint256,bytes)"));
    bytes4 private constant SEL_FUND        = bytes4(keccak256("fund(uint256,uint256)"));
    bytes4 private constant SEL_FUND_EXT    = bytes4(keccak256("fund(uint256,uint256,bytes)"));
    bytes4 private constant SEL_SUBMIT      = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 private constant SEL_SUBMIT_EXT  = bytes4(keccak256("submit(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_COMPLETE    = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 private constant SEL_COMPLETE_EXT = bytes4(keccak256("complete(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_REJECT      = bytes4(keccak256("reject(uint256,bytes32)"));
    bytes4 private constant SEL_REJECT_EXT  = bytes4(keccak256("reject(uint256,bytes32,bytes)"));

    // ── struct ──
    struct Commitment {
        address buyer;          // 产出代币接收方
        address capitalToken;   // 资本代币（如 USDT）
        uint256 capitalAmount;  // 资本代币数量
        address outputToken;    // 产出代币（如 ETH，mock）
        uint256 outputAmount;   // 期望产出数量
    }

    // ── storage ──
    mapping(uint256 => Commitment) public commitments;
    mapping(uint256 => uint256) public deposited; // jobId → 已存入的产出
    mapping(uint256 => bool)    public recovered; // jobId → 是否已取回

    // ── events ──
    event CapitalForwarded(uint256 indexed jobId, address provider, address token, uint256 amount);
    event OutputDeposited(uint256 indexed jobId, address provider, address token, uint256 amount);
    event OutputReleased(uint256 indexed jobId, address buyer, address token, uint256 amount);
    event OutputReturned(uint256 indexed jobId, address provider, address token, uint256 amount);

    // ── 最小 Escrow 接口（用于查询 job 角色） ──
    function _getEscrowJob(uint256 jobId) private view returns (address client, address provider) {
        // msg.sender 就是 Escrow 合约，直接回调查询
        (bool ok, bytes memory ret) = msg.sender.staticcall(
            abi.encodeWithSignature("getJob(uint256)", jobId)
        );
        require(ok, "Hook: getJob failed");
        // getJob returns Job struct: (client, provider, evaluator, description, budget, expiredAt, status, hook)
        // 取前两个字段
        assembly {
            client   := mload(add(ret, 32))
            provider := mload(add(ret, 64))
        }
    }

    // ═══════════════════════════════════════════════════════
    //  beforeAction
    // ═══════════════════════════════════════════════════════

    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        if (selector == SEL_SETBUDGET || selector == SEL_SETBUDGET_EXT) {
            _beforeSetBudget(jobId, data);
        } else if (selector == SEL_FUND || selector == SEL_FUND_EXT) {
            _beforeFund(jobId);
        } else if (selector == SEL_SUBMIT || selector == SEL_SUBMIT_EXT) {
            _beforeSubmit(jobId);
        }
    }

    // @dev 从 setBudget 的 optParams 解码 swap 参数
    //      optParams = abi.encode(buyer, capitalToken, capitalAmount, outputToken, outputAmount)
    function _beforeSetBudget(uint256 jobId, bytes calldata data) private {
        if (data.length < 160) return; // 5 × 32 bytes minimum
        (
            address buyer,
            address capitalToken,
            uint256 capitalAmount,
            address outputToken,
            uint256 outputAmount
        ) = abi.decode(data, (address, address, uint256, address, uint256));
        require(buyer != address(0), "Hook: buyer zero");
        require(capitalToken != address(0), "Hook: capitalToken zero");
        require(outputToken != address(0), "Hook: outputToken zero");
        require(capitalAmount > 0, "Hook: capitalAmount zero");
        require(outputAmount > 0, "Hook: outputAmount zero");

        commitments[jobId] = Commitment(buyer, capitalToken, capitalAmount, outputToken, outputAmount);
    }

    // @dev fund 前验证 Client 已 approve Hook 足额资本代币
    function _beforeFund(uint256 jobId) private view {
        Commitment memory c = commitments[jobId];
        if (c.capitalAmount == 0) return;
        (address client, ) = _getEscrowJob(jobId);
        uint256 allowance = IERC20Minimal(c.capitalToken).allowance(client, address(this));
        require(allowance >= c.capitalAmount, "Hook: insufficient capital allowance");
    }

    // @dev submit 前从 Provider 拉产出代币存入 Hook
    function _beforeSubmit(uint256 jobId) private {
        Commitment memory c = commitments[jobId];
        if (c.outputAmount == 0) return;
        require(deposited[jobId] == 0, "Hook: already deposited");

        (, address provider) = _getEscrowJob(jobId);
        IERC20Minimal(c.outputToken).transferFrom(provider, address(this), c.outputAmount);
        deposited[jobId] = c.outputAmount;
        emit OutputDeposited(jobId, provider, c.outputToken, c.outputAmount);
    }

    // ═══════════════════════════════════════════════════════
    //  afterAction
    // ═══════════════════════════════════════════════════════

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata /*data*/) external override {
        if (selector == SEL_FUND || selector == SEL_FUND_EXT) {
            _afterFund(jobId);
        } else if (selector == SEL_COMPLETE || selector == SEL_COMPLETE_EXT) {
            _afterComplete(jobId);
        } else if (selector == SEL_REJECT || selector == SEL_REJECT_EXT) {
            _afterReject(jobId);
        }
    }

    // @dev 从 Client 拉资本代币转给 Provider
    function _afterFund(uint256 jobId) private {
        Commitment memory c = commitments[jobId];
        if (c.capitalAmount == 0) return;

        (address client, address provider) = _getEscrowJob(jobId);
        IERC20Minimal(c.capitalToken).transferFrom(client, provider, c.capitalAmount);
        emit CapitalForwarded(jobId, provider, c.capitalToken, c.capitalAmount);
    }

    // @dev 释放产出代币给 buyer
    function _afterComplete(uint256 jobId) private {
        Commitment memory c = commitments[jobId];
        uint256 amount = deposited[jobId];
        if (c.buyer == address(0) || amount == 0) return;

        deposited[jobId] = 0;
        IERC20Minimal(c.outputToken).transfer(c.buyer, amount);
        emit OutputReleased(jobId, c.buyer, c.outputToken, amount);
    }

    // @dev 退还产出代币给 Provider
    function _afterReject(uint256 jobId) private {
        uint256 amount = deposited[jobId];
        if (amount == 0) return;

        (, address provider) = _getEscrowJob(jobId);
        deposited[jobId] = 0;
        address token = commitments[jobId].outputToken;
        IERC20Minimal(token).transfer(provider, amount);
        emit OutputReturned(jobId, provider, token, amount);
    }

    // ═══════════════════════════════════════════════════════
    //  recoverTokens — 过期后 Provider 手动取回产出
    // ═══════════════════════════════════════════════════════

    function recoverTokens(uint256 jobId) external {
        require(!recovered[jobId], "Hook: already recovered");
        uint256 amount = deposited[jobId];
        require(amount > 0, "Hook: nothing to recover");

        (, address provider) = _getEscrowJob(jobId);
        recovered[jobId] = true;
        deposited[jobId] = 0;

        address token = commitments[jobId].outputToken;
        IERC20Minimal(token).transfer(provider, amount);
        emit OutputReturned(jobId, provider, token, amount);
    }
}
