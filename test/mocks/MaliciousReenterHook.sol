// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";

// @title MaliciousReenterHook — 用于防重入测试的恶意 Hook
// @notice 在 afterAction 中根据 selector 重入调用对应的核心函数
contract MaliciousReenterHook is IACPHook {
    // ── 函数选择器常量（与 ERC8183Escrow 中定义一致） ──

    // 无 optParams 版本
    bytes4 private constant SEL_SETPROVIDER = bytes4(keccak256("setProvider(uint256,address)"));
    bytes4 private constant SEL_SETBUDGET = bytes4(keccak256("setBudget(uint256,uint256)"));
    bytes4 private constant SEL_FUND = bytes4(keccak256("fund(uint256,uint256)"));
    bytes4 private constant SEL_SUBMIT = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 private constant SEL_COMPLETE = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 private constant SEL_REJECT = bytes4(keccak256("reject(uint256,bytes32)"));

    // 带 optParams 版本
    bytes4 private constant SEL_SETPROVIDER_EXT = bytes4(keccak256("setProvider(uint256,address,bytes)"));
    bytes4 private constant SEL_SETBUDGET_EXT = bytes4(keccak256("setBudget(uint256,uint256,bytes)"));
    bytes4 private constant SEL_FUND_EXT = bytes4(keccak256("fund(uint256,uint256,bytes)"));
    bytes4 private constant SEL_SUBMIT_EXT = bytes4(keccak256("submit(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_COMPLETE_EXT = bytes4(keccak256("complete(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_REJECT_EXT = bytes4(keccak256("reject(uint256,bytes32,bytes)"));

    // @notice 托管合约地址
    address public immutable escrow;

    // @notice 用于重入 setProvider 的备用地址
    address public immutable reenterProvider;

    constructor(address escrow_, address reenterProvider_) {
        escrow = escrow_;
        reenterProvider = reenterProvider_;
    }

    // @notice beforeAction — 不执行重入（仅在 afterAction 中重入）
    function beforeAction(uint256, bytes4, bytes calldata) external override {
        // 不执行任何操作
    }

    // @notice afterAction — 根据 selector 重入对应的核心函数
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        if (selector == SEL_SETPROVIDER || selector == SEL_SETPROVIDER_EXT) {
            IEscrow(escrow).setProvider(jobId, reenterProvider);
        } else if (selector == SEL_SETBUDGET || selector == SEL_SETBUDGET_EXT) {
            IEscrow(escrow).setBudget(jobId, 1);
        } else if (selector == SEL_FUND || selector == SEL_FUND_EXT) {
            IEscrow(escrow).fund(jobId, 1);
        } else if (selector == SEL_SUBMIT || selector == SEL_SUBMIT_EXT) {
            IEscrow(escrow).submit(jobId, bytes32(0));
        } else if (selector == SEL_COMPLETE || selector == SEL_COMPLETE_EXT) {
            IEscrow(escrow).complete(jobId, bytes32(0));
        } else if (selector == SEL_REJECT || selector == SEL_REJECT_EXT) {
            IEscrow(escrow).reject(jobId, bytes32(0));
        }
        // 其他 selector 不处理
    }
}

// @dev 最小接口，仅包含 MaliciousReenterHook 需要重入的函数
interface IEscrow {
    function setProvider(uint256 jobId, address provider) external;
    function setBudget(uint256 jobId, uint256 amount) external;
    function fund(uint256 jobId, uint256 expectedBudget) external;
    function submit(uint256 jobId, bytes32 deliverable) external;
    function complete(uint256 jobId, bytes32 reason) external;
    function reject(uint256 jobId, bytes32 reason) external;
    function claimRefund(uint256 jobId) external;
}
