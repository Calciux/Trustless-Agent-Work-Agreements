// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../interfaces/IACPHook.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";

// @title FundTransferHookV3 — 最小可行版，去掉 beforeAction 的 allowance 检查
contract FundTransferHookV3 is IACPHook {
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

    struct Commitment {
        address buyer;
        address capitalToken;
        uint256 capitalAmount;
        address outputToken;
        uint256 outputAmount;
    }

    mapping(uint256 => Commitment) public commitments;
    mapping(uint256 => uint256) public deposited;

    // ── helpers to get roles from Escrow via staticcall ──
    function _escrowClient(uint256 jobId) private view returns (address) {
        (bool ok, bytes memory ret) = msg.sender.staticcall(
            abi.encodeWithSignature("getJob(uint256)", jobId)
        );
        require(ok, "Hook: staticcall failed");
        address client;
        assembly { client := mload(add(ret, 32)) }
        return client;
    }

    function _escrowProvider(uint256 jobId) private view returns (address) {
        (bool ok, bytes memory ret) = msg.sender.staticcall(
            abi.encodeWithSignature("getJob(uint256)", jobId)
        );
        require(ok, "Hook: staticcall failed");
        address provider;
        assembly { provider := mload(add(ret, 64)) }
        return provider;
    }

    // ═══════════════ beforeAction ═══════════════

    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        if (selector == SEL_SETBUDGET || selector == SEL_SETBUDGET_EXT) {
            if (data.length >= 160) {
                (address buyer, address capitalToken, uint256 capitalAmount, address outputToken, uint256 outputAmount)
                    = abi.decode(data, (address, address, uint256, address, uint256));
                commitments[jobId] = Commitment(buyer, capitalToken, capitalAmount, outputToken, outputAmount);
            }
        } else if (selector == SEL_SUBMIT || selector == SEL_SUBMIT_EXT) {
            Commitment memory c = commitments[jobId];
            if (c.outputAmount > 0 && deposited[jobId] == 0) {
                address provider = _escrowProvider(jobId);
                IERC20Minimal(c.outputToken).transferFrom(provider, address(this), c.outputAmount);
                deposited[jobId] = c.outputAmount;
            }
        }
    }

    // ═══════════════ afterAction ═══════════════

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        if (selector == SEL_FUND || selector == SEL_FUND_EXT) {
            Commitment memory c = commitments[jobId];
            if (c.capitalAmount > 0) {
                address client = _escrowClient(jobId);
                address provider = _escrowProvider(jobId);
                IERC20Minimal(c.capitalToken).transferFrom(client, provider, c.capitalAmount);
            }
        } else if (selector == SEL_COMPLETE || selector == SEL_COMPLETE_EXT) {
            Commitment memory c = commitments[jobId];
            uint256 amount = deposited[jobId];
            if (c.buyer != address(0) && amount > 0) {
                deposited[jobId] = 0;
                IERC20Minimal(c.outputToken).transfer(c.buyer, amount);
            }
        } else if (selector == SEL_REJECT || selector == SEL_REJECT_EXT) {
            uint256 amount = deposited[jobId];
            if (amount > 0) {
                deposited[jobId] = 0;
                address provider = _escrowProvider(jobId);
                IERC20Minimal(commitments[jobId].outputToken).transfer(provider, amount);
            }
        }
    }
}
