// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IACPHook — Agentic Commerce Protocol Hook
 * @dev Optional hook interface for ERC-8183 jobs.
 *      Each job MAY bind a hook contract that intercepts core actions
 *      before and/or after execution.
 *
 * Hookable functions: setProvider, setBudget, fund, submit, complete, reject
 * NOT hookable:       claimRefund (deliberately excluded to guarantee refund path)
 *
 * https://eips.ethereum.org/EIPS/eip-8183
 */
interface IACPHook {
    /**
     * @notice Called before a core action executes.
     * @param jobId    The job being acted upon
     * @param selector The function selector of the core action
     * @param data     The calldata (excluding selector) of the core action
     */
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;

    /**
     * @notice Called after a core action executes.
     * @param jobId    The job being acted upon
     * @param selector The function selector of the core action
     * @param data     The calldata (excluding selector) of the core action
     */
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
