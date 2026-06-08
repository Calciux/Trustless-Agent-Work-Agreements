// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title AdminFunctionsTest — UT-071 ~ UT-075
contract AdminFunctionsTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);
    }

    // ── UT-071: setTreasury owner 调用 → 成功 ────────────────────────
    function test_UT071_SetTreasury_OwnerSucceeds() public {
        address newTreasury = makeAddr("newTreasury");
        escrow.setTreasury(newTreasury);
        assertEq(escrow.treasury(), newTreasury);
    }

    // ── UT-072: setTreasury 非 owner → revert ────────────────────────
    function test_UT072_SetTreasury_RevertWhen_NotOwner() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller is not owner");
        vm.prank(stranger);
        escrow.setTreasury(stranger);
    }

    // ── UT-073: setFeeBps owner + feeBps ≤ MAX → 成功 ───────────────
    function test_UT073_SetFeeBps_OwnerSucceeds() public {
        escrow.setFeeBps(500);
        assertEq(escrow.feeBps(), 500);
    }

    // ── UT-074: setFeeBps > MAX_FEE_BPS → revert ────────────────────
    function test_UT074_SetFeeBps_RevertWhen_TooHigh() public {
        vm.expectRevert("ERC8183: total fee too high");
        escrow.setFeeBps(10001);
    }

    // ── UT-075: setFeeBps 非 owner → revert ──────────────────────────
    function test_UT075_SetFeeBps_RevertWhen_NotOwner() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller is not owner");
        vm.prank(stranger);
        escrow.setFeeBps(100);
    }
}
