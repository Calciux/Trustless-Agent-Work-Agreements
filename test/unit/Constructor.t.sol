// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title ConstructorTest — UT-001 ~ UT-003
contract ConstructorTest is Test {
    MockERC20 public token;

    function setUp() public {
        token = new MockERC20();
    }

    // ── UT-001: paymentToken=address(0) → revert ─────────────────────
    function test_UT001_RevertWhen_PaymentTokenIsZeroAddress() public {
        vm.expectRevert("ERC8183: payment token zero address");
        new ERC8183Escrow(address(0), address(0), 0);
    }

    // ── UT-002: feeBps > MAX_FEE_BPS(10000) → revert ────────────────
    function test_UT002_RevertWhen_FeeBpsTooHigh() public {
        vm.expectRevert("ERC8183: fee too high");
        new ERC8183Escrow(address(token), address(0), 10001);
    }

    // ── UT-003: 正常部署后 storage 变量正确初始化 ─────────────────────
    function test_UT003_Deploy_StorageInitializedCorrectly() public {
        address treasury = makeAddr("treasury");
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), treasury, 250);

        assertEq(escrow.owner(), address(this), "owner should be deployer");
        assertEq(escrow.paymentToken(), address(token), "paymentToken mismatch");
        assertEq(escrow.treasury(), treasury, "treasury mismatch");
        assertEq(escrow.feeBps(), 250, "feeBps mismatch");
        assertEq(escrow.jobCount(), 0, "jobCount should be 0");
    }
}
