// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";

// @title CrossReenterHook — 跨函数重入 Hook
// @dev 在 afterAction 中根据触发 selector 查表，调用不同的目标函数
//   构造函数：
//     _escrow:          ERC8183Escrow 合约地址
//     _triggerSelector: 触发重入的源 selector
//     _targetFunction:  要调用的目标函数签名（作为 key）
//     目标函数调用固定参数 (jobId, bytes32(uint256(1)))
//   使用示例（IT-015: submit→complete）:
//     new CrossReenterHook(escrow, SEL_SUBMIT, SEL_COMPLETE)
//   使用示例（IT-016: complete→reject）:
//     new CrossReenterHook(escrow, SEL_COMPLETE, SEL_REJECT)
contract CrossReenterHook is IACPHook {
    address public immutable escrow;
    bytes4 public immutable triggerSelector;
    bytes4 public immutable targetFunction;

    // 函数选择器常量（与 ERC8183Escrow 中定义一致）
    bytes4 private constant SEL_SETPROVIDER   = bytes4(keccak256("setProvider(uint256,address)"));
    bytes4 private constant SEL_SETBUDGET     = bytes4(keccak256("setBudget(uint256,uint256)"));
    bytes4 private constant SEL_FUND          = bytes4(keccak256("fund(uint256,uint256)"));
    bytes4 private constant SEL_SUBMIT        = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 private constant SEL_COMPLETE      = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 private constant SEL_REJECT        = bytes4(keccak256("reject(uint256,bytes32)"));

    // 带 optParams 版本（需要对应匹配）
    bytes4 private constant SEL_SUBMIT_EXT    = bytes4(keccak256("submit(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_COMPLETE_EXT  = bytes4(keccak256("complete(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_REJECT_EXT    = bytes4(keccak256("reject(uint256,bytes32,bytes)"));

    constructor(address _escrow, bytes4 _triggerSelector, bytes4 _targetFunction) {
        escrow = _escrow;
        triggerSelector = _triggerSelector;
        targetFunction = _targetFunction;
    }

    function beforeAction(uint256, bytes4, bytes calldata) external override {
        // 不执行任何操作
    }

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        // 匹配 selector（包括无 optParams 和带 optParams 版本）
        bool isTrigger = (selector == triggerSelector ||
                          (triggerSelector == SEL_SUBMIT && selector == SEL_SUBMIT_EXT) ||
                          (triggerSelector == SEL_COMPLETE && selector == SEL_COMPLETE_EXT) ||
                          (triggerSelector == SEL_REJECT && selector == SEL_REJECT_EXT));

        if (!isTrigger) return;

        if (targetFunction == SEL_SETPROVIDER) {
            IEscrow(escrow).setProvider(jobId, address(0xdead));
        } else if (targetFunction == SEL_SETBUDGET) {
            IEscrow(escrow).setBudget(jobId, 1);
        } else if (targetFunction == SEL_FUND) {
            IEscrow(escrow).fund(jobId, 1);
        } else if (targetFunction == SEL_SUBMIT) {
            IEscrow(escrow).submit(jobId, bytes32(uint256(1)));
        } else if (targetFunction == SEL_COMPLETE) {
            IEscrow(escrow).complete(jobId, bytes32(uint256(1)));
        } else if (targetFunction == SEL_REJECT) {
            IEscrow(escrow).reject(jobId, bytes32(uint256(1)));
        }
    }
}

// @dev 最小接口，仅包含 CrossReenterHook 需要重入的函数
//     （与 MaliciousReenterHook 中定义一致）
interface IEscrow {
    function setProvider(uint256 jobId, address provider) external;
    function setBudget(uint256 jobId, uint256 amount) external;
    function fund(uint256 jobId, uint256 expectedBudget) external;
    function submit(uint256 jobId, bytes32 deliverable) external;
    function complete(uint256 jobId, bytes32 reason) external;
    function reject(uint256 jobId, bytes32 reason) external;
    function claimRefund(uint256 jobId) external;
}
