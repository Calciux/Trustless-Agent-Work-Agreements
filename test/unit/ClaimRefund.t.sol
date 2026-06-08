// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockHook} from "../mocks/MockHook.sol";

// @title ClaimRefundTest — UT-052 ~ UT-059
contract ClaimRefundTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;
    MockHook public hook;

    address public client;
    address public provider;
    address public evaluator;
    uint256 public expiredAt;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);
        hook = new MockHook();

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        expiredAt = block.timestamp + 7 days;
    }

    // Helper: create + fund → Funded
    function _setupFundedJob(uint256 budgetAmt) internal returns (uint256) {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        token.mint(client, budgetAmt);
        token.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();
        return jid;
    }

    // Helper: create + fund + submit → Submitted
    function _setupSubmittedJob(uint256 budgetAmt) internal returns (uint256) {
        uint256 jid = _setupFundedJob(budgetAmt);
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
        return jid;
    }

    // ── UT-052: Funded + 已过期 → Expired + 全额退款 ──────────────────
    function test_UT052_ClaimRefund_FundedExpired_RefundsClient() public {
        uint256 jid = _setupFundedJob(500);

        vm.warp(expiredAt + 1);

        vm.expectEmit(true, false, false, false);
        emit IERC8183.JobExpired(jid);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(jid, client, 500);

        escrow.claimRefund(jid);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(client), 500, "client should be refunded 500");
        assertEq(token.balanceOf(address(escrow)), 0, "escrow should be 0");
    }

    // ── UT-053: Submitted + 已过期 → Expired + 全额退款 ───────────────
    function test_UT053_ClaimRefund_SubmittedExpired_RefundsClient() public {
        uint256 jid = _setupSubmittedJob(500);

        vm.warp(expiredAt + 1);

        vm.expectEmit(true, false, false, false);
        emit IERC8183.JobExpired(jid);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(jid, client, 500);

        escrow.claimRefund(jid);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(client), 500);
    }

    // ── UT-054: 未过期 → revert ───────────────────────────────────────
    function test_UT054_ClaimRefund_RevertWhen_NotExpired() public {
        uint256 jid = _setupFundedJob(500);
        // Not warped — still before expiredAt

        vm.expectRevert("ERC8183: job not expired");
        escrow.claimRefund(jid);
    }

    // ── UT-055: Open 状态 → revert ────────────────────────────────────
    function test_UT055_ClaimRefund_RevertWhen_Open() public {
        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));

        vm.warp(expiredAt + 1);

        vm.expectRevert("ERC8183: job not in refundable state");
        escrow.claimRefund(jid);
    }

    // ── UT-056: Completed/Rejected/Expired 状态 → revert ──────────────
    function test_UT056_ClaimRefund_RevertWhen_TerminalState() public {
        // --- Completed ---
        uint256 jid1 = _setupSubmittedJob(100);
        vm.prank(evaluator);
        escrow.complete(jid1, bytes32(0));

        vm.expectRevert("ERC8183: job not in refundable state");
        escrow.claimRefund(jid1);

        // --- Rejected ---
        // 新 job 需要用当前时间重新计算 future expiry（此前可能已 warp）
        uint256 freshExpiry = block.timestamp + 7 days;
        vm.prank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator, freshExpiry, "desc2", address(0));
        vm.startPrank(client);
        escrow.setProvider(jid2, provider);
        escrow.setBudget(jid2, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid2, 100);
        vm.stopPrank();
        vm.prank(evaluator);
        escrow.reject(jid2, bytes32(0));

        vm.expectRevert("ERC8183: job not in refundable state");
        escrow.claimRefund(jid2);

        // --- Expired (already claimed) ---
        uint256 freshExpiry2 = block.timestamp + 7 days;
        vm.prank(client);
        uint256 jid3 = escrow.createJob(address(0), evaluator, freshExpiry2, "desc3", address(0));
        vm.startPrank(client);
        escrow.setProvider(jid3, provider);
        escrow.setBudget(jid3, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid3, 100);
        vm.stopPrank();
        vm.warp(freshExpiry2 + 1);
        escrow.claimRefund(jid3); // Now Expired

        vm.expectRevert("ERC8183: job not in refundable state");
        escrow.claimRefund(jid3);
    }

    // ── UT-057: 任何人可调用（随机地址） ───────────────────────────────
    function test_UT057_ClaimRefund_AnyoneCanCall() public {
        uint256 jid = _setupFundedJob(500);
        vm.warp(expiredAt + 1);

        address randomCaller = makeAddr("randomStranger");
        vm.prank(randomCaller);
        escrow.claimRefund(jid);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(client), 500, "client should be refunded");
    }

    // ── UT-058: 未到期（far future）→ revert ──────────────────────────
    function test_UT058_ClaimRefund_RevertWhen_FarFutureExpiry() public {
        // Create job with very far expiry
        uint256 farFuture = block.timestamp + 365 days;
        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, farFuture, "desc", address(0));
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 500);
        token.mint(client, 500);
        token.approve(address(escrow), 500);
        escrow.fund(jid, 500);
        vm.stopPrank();

        vm.expectRevert("ERC8183: job not expired");
        escrow.claimRefund(jid);
    }

    // ── UT-059: Hook≠0 时不调用 beforeAction/afterAction ──────────────
    function test_UT059_ClaimRefund_DoesNotCallHook() public {
        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(hook));
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 500);
        token.mint(client, 500);
        token.approve(address(escrow), 500);
        escrow.fund(jid, 500);
        vm.stopPrank();

        // Record hook call counts before claimRefund
        uint256 beforeCnt = hook.beforeCount();
        uint256 afterCnt = hook.afterCount();

        vm.warp(expiredAt + 1);
        escrow.claimRefund(jid);

        // Hook should NOT have been called
        assertEq(hook.beforeCount(), beforeCnt, "beforeAction should not be called");
        assertEq(hook.afterCount(), afterCnt, "afterAction should not be called");
        assertEq(token.balanceOf(client), 500, "client should be refunded");
    }
}
