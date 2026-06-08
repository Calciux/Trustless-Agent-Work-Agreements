// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title FundOnlyReenterHook — only reenters on fund selector (UT-091)
/// @dev Needed because the generic MaliciousReenterHook would also reenter
/// on setProvider()/setBudget() during setup, preventing the job from
/// reaching Funded state.
contract FundOnlyReenterHook {
    bytes4 private constant SEL_FUND = bytes4(keccak256("fund(uint256,uint256)"));
    bytes4 private constant SEL_FUND_EXT = bytes4(keccak256("fund(uint256,uint256,bytes)"));

    address public immutable escrow;

    constructor(address escrow_) {
        escrow = escrow_;
    }

    function beforeAction(uint256, bytes4, bytes calldata) external {}

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external {
        if (selector == SEL_FUND || selector == SEL_FUND_EXT) {
            IEscrowReenter(escrow).fund(jobId, 1);
        }
    }
}

interface IEscrowReenter {
    function fund(uint256 jobId, uint256 expectedBudget) external;
}
