// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";
import {IERC165} from "../../contracts/interfaces/IERC165.sol";

// CompleteOnlyReenterHook — only reenters on complete selector (UT-093).
contract CompleteOnlyReenterHook is IACPHook {
    bytes4 private constant SEL_COMPLETE = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 private constant SEL_COMPLETE_EXT = bytes4(keccak256("complete(uint256,bytes32,bytes)"));

    address public immutable escrow;

    constructor(address escrow_) {
        escrow = escrow_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACPHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function beforeAction(uint256, bytes4, bytes calldata) external override {}

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        if (selector == SEL_COMPLETE || selector == SEL_COMPLETE_EXT) {
            IEscrowReenter(escrow).complete(jobId, bytes32(0));
        }
    }
}

interface IEscrowReenter {
    function complete(uint256 jobId, bytes32 reason) external;
}
