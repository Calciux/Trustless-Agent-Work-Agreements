// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {CrossReenterHook} from "../../mocks/CrossReenterHook.sol";

// @title CrossReentryTest — IT-015 ~ IT-016: 跨函数重入集成测试
contract CrossReentryTest is Test {
    MockERC20 token;
    address client = makeAddr("client");
    address provider = makeAddr("provider");
    address evaluator = makeAddr("evaluator");
    uint256 expiredAt;

    // 函数选择器常量（与 ERC8183Escrow 中定义一致）
    bytes4 constant SEL_SUBMIT   = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 constant SEL_COMPLETE = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 constant SEL_REJECT   = bytes4(keccak256("reject(uint256,bytes32)"));

    function setUp() public {
        token = new MockERC20();
        expiredAt = block.timestamp + 7 days;
    }

    // ================================================================
    // IT-015: submit 的 Hook afterAction 中重入 complete → nonReentrant 阻止
    // ================================================================
    function test_IT015_SubmitHookReentersCompleteBlocked() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // Deploy hook that reenters complete from submit's afterAction
        CrossReenterHook hook = new CrossReenterHook(address(escrow), SEL_SUBMIT, SEL_COMPLETE);

        // ── createJob + setProvider + setBudget + fund ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(hook));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(token.balanceOf(address(escrow)), 500);

        // ── submit → expect reentrant call revert ──
        vm.expectRevert(bytes("ERC8183: reentrant call"));
        vm.prank(provider);
        escrow.submit(1, bytes32("work"));

        // submit 的状态变更被回滚
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        // 资金未动
        assertEq(token.balanceOf(address(escrow)), 500);
    }

    // ================================================================
    // IT-016: complete 的 Hook afterAction 中重入 reject → nonReentrant 阻止
    // ================================================================
    function test_IT016_CompleteHookReentersRejectBlocked() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // Deploy hook that reenters reject from complete's afterAction
        CrossReenterHook hook = new CrossReenterHook(address(escrow), SEL_COMPLETE, SEL_REJECT);

        // ── createJob + setProvider + setBudget + fund + submit → Submitted ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(hook));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        vm.prank(provider);
        escrow.submit(jobId, bytes32("work"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));
        assertEq(token.balanceOf(address(escrow)), 500);

        // ── complete → expect reentrant call revert ──
        vm.expectRevert(bytes("ERC8183: reentrant call"));
        vm.prank(evaluator);
        escrow.complete(1, bytes32("ok"));

        // 状态仍为 Submitted（不是 Completed，也不是 Rejected）
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));
        // 资金未动
        assertEq(token.balanceOf(address(escrow)), 500);
        // 未付款
        assertEq(token.balanceOf(provider), 0);
        // 未退款
        assertEq(token.balanceOf(client), 500);
    }
}
