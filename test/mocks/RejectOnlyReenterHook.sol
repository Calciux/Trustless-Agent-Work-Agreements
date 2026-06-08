// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";
import {IERC165} from "../../contracts/interfaces/IERC165.sol";

// RejectOnlyReenterHook — only reenters on reject selector (UT-094).
contract RejectOnlyReenterHook is IACPHook {
    bytes4 private constant SEL_REJECT = bytes4(keccak256("reject(uint256,bytes32)"));
    bytes4 private constant SEL_REJECT_EXT = bytes4(keccak256("reject(uint256,bytes32,bytes)"));

    address public immutable escrow;

    constructor(address escrow_) {
        escrow = escrow_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACPHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function beforeAction(uint256, bytes4, bytes calldata) external override {}

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        if (selector == SEL_REJECT || selector == SEL_REJECT_EXT) {
            IEscrowReenter(escrow).reject(jobId, bytes32(0));
        }
    }
}

interface IEscrowReenter {
    function reject(uint256 jobId, bytes32 reason) external;
}
