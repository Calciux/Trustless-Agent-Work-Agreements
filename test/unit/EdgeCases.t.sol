// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title EdgeCasesTest — UT-096 ~ UT-104
contract EdgeCasesTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    address public client;
    address public provider;
    address public evaluator;
    uint256 public expiredAt;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        expiredAt = block.timestamp + 7 days;
    }

    // ── UT-096: expiredAt = block.timestamp + 1 → 成功 ───────────────
    function test_UT096_CreateJob_ExpiredAtPlusOneSecond() public {
        uint256 nearExpiry = block.timestamp + 1;

        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, nearExpiry, "desc", address(0));

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.expiredAt, nearExpiry, "expiredAt should be block.timestamp + 1");
    }

    // ── UT-097: 不存在的 jobId 调用核心函数 → revert ────────────────
    function test_UT097_NonExistentJobId_Reverts() public {
        // getJob(0)
        vm.expectRevert("ERC8183: job not found");
        escrow.getJob(0);

        // getJob(999)
        vm.expectRevert("ERC8183: job not found");
        escrow.getJob(999);

        // setProvider on non-existent job: onlyClient reads _jobs[0].client=address(0)
        vm.expectRevert("ERC8183: caller is not client");
        vm.prank(makeAddr("rando"));
        escrow.setProvider(0, provider);

        // fund on non-existent job: onlyClient fails
        vm.expectRevert("ERC8183: caller is not client");
        vm.prank(makeAddr("rando"));
        escrow.fund(0, 100);

        // submit on non-existent job: onlyProvider fails
        vm.expectRevert("ERC8183: caller is not provider");
        vm.prank(makeAddr("rando"));
        escrow.submit(0, bytes32(0));

        // complete on non-existent job: onlyEvaluator fails
        vm.expectRevert("ERC8183: caller is not evaluator");
        vm.prank(makeAddr("rando"));
        escrow.complete(0, bytes32(0));

        // reject on non-existent job: status check fails (Open→caller not client)
        vm.expectRevert("ERC8183: caller not client");
        vm.prank(makeAddr("rando"));
        escrow.reject(0, bytes32(0));

        // claimRefund on non-existent job: status check fails
        vm.expectRevert("ERC8183: job not in refundable state");
        escrow.claimRefund(0);
    }

    // ── UT-098: complete 后再次 complete → revert ─────────────────────
    function test_UT098_Complete_AfterCompleted_Reverts() public {
        // Setup to Submitted → Complete
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        // Second complete attempt
        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));
    }

    // ── UT-099: reject 后再次 reject → revert ─────────────────────────
    function test_UT099_Reject_AfterRejected_Reverts() public {
        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));

        vm.prank(client);
        escrow.reject(jid, bytes32(0));

        // Second reject attempt
        vm.expectRevert("ERC8183: invalid job status for reject");
        vm.prank(client);
        escrow.reject(jid, bytes32(0));
    }

    // ── UT-100: budget = type(uint256).max ────────────────────────────
    function test_UT100_BudgetTypeUint256Max() public {
        uint256 maxBudget = type(uint256).max;

        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, maxBudget);
        token.mint(client, maxBudget);
        token.approve(address(escrow), maxBudget);
        escrow.fund(jid, maxBudget);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Funded));
        assertEq(token.balanceOf(address(escrow)), maxBudget);

        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(token.balanceOf(provider), maxBudget, "provider should receive max budget");
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // ── UT-101: jobId 自增不回溯 ──────────────────────────────────────
    function test_UT101_JobId_NoBacktrackAfterTerminal() public {
        address evaluator2 = makeAddr("evaluator2");

        // Create job1 and move to Completed (terminal)
        vm.startPrank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator, expiredAt, "job1", address(0));
        escrow.setProvider(jid1, provider);
        escrow.setBudget(jid1, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid1, 100);
        vm.stopPrank();
        vm.prank(provider);
        escrow.submit(jid1, bytes32(0));
        vm.prank(evaluator);
        escrow.complete(jid1, bytes32(0));

        assertEq(jid1, 1);
        assertEq(escrow.jobCount(), 1);

        // Create job2 — should be 2, not 1
        vm.prank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator2, expiredAt, "job2", address(0));

        assertEq(jid2, 2, "jobId should be 2, not backtrack to 1");
        assertEq(escrow.jobCount(), 2);
    }

    // ── UT-102: expectedBudget=0 且 budget=0 → 检查顺序验证 ──────────
    function test_UT102_Fund_ZeroBudgetCheckOrder() public {
        // Create job without setting budget (budget stays 0)
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        // NOT calling setBudget — budget remains 0
        vm.stopPrank();

        // fund(jobId, 0) — should revert with "budget not set" (checked before "budget mismatch")
        vm.expectRevert("ERC8183: budget not set");
        vm.prank(client);
        escrow.fund(jid, 0);
    }

    // ── UT-103: constructor feeBps 恰好 = MAX_FEE_BPS(10000) ──────────
    function test_UT103_Constructor_FeeBpsExactlyMax() public {
        ERC8183Escrow e = new ERC8183Escrow(address(token), address(0), 10000);
        assertEq(e.feeBps(), 10000, "feeBps should be 10000");
    }

    // ── UT-104: block.timestamp == expiredAt → 可退款 ────────────────
    function test_UT104_ClaimRefund_ExactlyAtExpiry() public {
        uint256 exactExpiry = block.timestamp + 100;

        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, exactExpiry, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 500);
        token.mint(client, 500);
        token.approve(address(escrow), 500);
        escrow.fund(jid, 500);
        vm.stopPrank();

        // Warp to exactly expiredAt
        vm.warp(exactExpiry);

        // Should succeed: block.timestamp >= expiredAt (equal is allowed)
        escrow.claimRefund(jid);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(client), 500);
    }
}
