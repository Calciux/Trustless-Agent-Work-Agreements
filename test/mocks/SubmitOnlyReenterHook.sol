// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";
import {IERC165} from "../../contracts/interfaces/IERC165.sol";

// SubmitOnlyReenterHook — only reenters on submit selector (UT-092).
// Needed because the generic MaliciousReenterHook would also reenter
// on fund(), preventing the job from reaching Funded state.
contract SubmitOnlyReenterHook is IACPHook {
    bytes4 private constant SEL_SUBMIT = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 private constant SEL_SUBMIT_EXT = bytes4(keccak256("submit(uint256,bytes32,bytes)"));

    address public immutable escrow;
    address public immutable reenterProvider;

    constructor(address escrow_, address reenterProvider_) {
        escrow = escrow_;
        reenterProvider = reenterProvider_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACPHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function beforeAction(uint256, bytes4, bytes calldata) external override {}

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        if (selector == SEL_SUBMIT || selector == SEL_SUBMIT_EXT) {
            IEscrowReenter(escrow).submit(jobId, bytes32(0));
        }
    }
}

interface IEscrowReenter {
    function submit(uint256 jobId, bytes32 deliverable) external;
}
