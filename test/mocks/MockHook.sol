// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";
import {IERC165} from "../../contracts/interfaces/IERC165.sol";

// @title MockHook — 用于 Hook 回调测试的最小实现
// @notice 实现 IACPHook 接口，用 storage 变量记录每次调用的参数，供测试断言
contract MockHook is IACPHook {
    // ── 最后一次调用的参数 ──
    uint256 public lastJobId;
    bytes4 public lastSelector;
    bytes public lastData;

    // ── 调用次数计数器 ──
    uint256 public beforeCount;
    uint256 public afterCount;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACPHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // @notice Called before a core action executes.
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        beforeCount++;
        lastJobId = jobId;
        lastSelector = selector;
        lastData = data;
    }

    // @notice Called after a core action executes.
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        afterCount++;
        lastJobId = jobId;
        lastSelector = selector;
        lastData = data;
    }
}
