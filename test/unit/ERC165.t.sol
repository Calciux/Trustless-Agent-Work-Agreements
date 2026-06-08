// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {IERC165} from "../../contracts/interfaces/IERC165.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title ERC165Test — UT-068 ~ UT-070
contract ERC165Test is Test {
    ERC8183Escrow public escrow;

    function setUp() public {
        MockERC20 token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);
    }

    // ── UT-068: supportsInterface(IERC8183.interfaceId) → true ───────
    function test_UT068_SupportsInterface_IERC8183() public {
        bool result = escrow.supportsInterface(type(IERC8183).interfaceId);
        assertTrue(result, "should support IERC8183");
    }

    // ── UT-069: supportsInterface(IERC165.interfaceId) → true ────────
    function test_UT069_SupportsInterface_IERC165() public {
        bool result = escrow.supportsInterface(type(IERC165).interfaceId);
        assertTrue(result, "should support IERC165");
    }

    // ── UT-070: supportsInterface(0xffffffff) → false ────────────────
    function test_UT070_SupportsInterface_RandomBytes4() public {
        bool result = escrow.supportsInterface(0xffffffff);
        assertFalse(result, "should not support random interface");
    }
}
