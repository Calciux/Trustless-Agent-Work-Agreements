// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";

// @title RevertingMockHook — 可控 revert 的 Hook
// @dev 通过构造函数参数控制 revert 时机和目标函数
//   构造函数：
//     _revertOnBefore: 是否在 beforeAction 中 revert
//     _revertOnAfter:  是否在 afterAction 中 revert
//     _targetSelector: 仅在匹配的 selector 触发时 revert
//     其他 selector 正常通过（不 revert）
contract RevertingMockHook is IACPHook {
    bool public immutable revertOnBefore;
    bool public immutable revertOnAfter;
    bytes4 public immutable targetSelector;

    // 记录最后一次调用的参数（不 revert 时用于验证）
    uint256 public lastJobId;
    bytes4 public lastSelector;
    bytes public lastData;
    uint256 public beforeCount;
    uint256 public afterCount;

    constructor(bool _revertOnBefore, bool _revertOnAfter, bytes4 _targetSelector) {
        revertOnBefore = _revertOnBefore;
        revertOnAfter = _revertOnAfter;
        targetSelector = _targetSelector;
    }

    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        beforeCount++;
        lastJobId = jobId;
        lastSelector = selector;
        lastData = data;
        if (revertOnBefore && selector == targetSelector) {
            revert("Hook: beforeAction reverted");
        }
    }

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        afterCount++;
        lastJobId = jobId;
        lastSelector = selector;
        lastData = data;
        if (revertOnAfter && selector == targetSelector) {
            revert("Hook: afterAction reverted");
        }
    }
}
