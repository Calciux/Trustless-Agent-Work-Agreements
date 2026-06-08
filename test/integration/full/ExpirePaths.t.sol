// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockHook} from "../../mocks/MockHook.sol";

// @title ExpirePathsTest — IT-008 ~ IT-012: 过期路径集成测试
contract ExpirePathsTest is Test {
    MockERC20 token;
    address client = makeAddr("client");
    address provider = makeAddr("provider");
    address evaluator = makeAddr("evaluator");
    address stranger = makeAddr("stranger");
    uint256 expiredAt;

    function setUp() public {
        token = new MockERC20();
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: create Open job (仅 createJob)
    function _createOpenJob(ERC8183Escrow escrow) internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "test job", address(0));
    }

    // @dev Helper: create + setProvider + setBudget + fund → Funded
    function _setupFunded(ERC8183Escrow escrow, uint256 budgetAmt, address hook) internal returns (uint256) {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "test job", hook);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        token.mint(client, budgetAmt);
        token.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();
        return jid;
    }

    // @dev Helper: create + setProvider + setBudget + fund + submit → Submitted
    function _setupSubmitted(ERC8183Escrow escrow, uint256 budgetAmt, address hook) internal returns (uint256) {
        uint256 jid = _setupFunded(escrow, budgetAmt, hook);
        vm.prank(provider);
        escrow.submit(jid, bytes32(uint256(1)));
        return jid;
    }

    // ================================================================
    // IT-008: Funded 状态过期 → 任意人 claimRefund 成功
    // ================================================================
    function test_IT008_FundedExpiredClaimRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // Use MockHook to verify no hook calls during claimRefund
        MockHook hook = new MockHook();
        uint256 shortExpiry = block.timestamp + 3600;

        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, shortExpiry, "desc", address(hook));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(token.balanceOf(address(escrow)), 500);

        // ── warp past expiry ──
        vm.warp(shortExpiry + 1);
        assertGe(block.timestamp, shortExpiry + 1);

        // ── claimRefund (stranger) ──
        // Snapshot hook counters before claimRefund (setProvider + setBudget + fund
        // each fire beforeAction + afterAction → 3 each)
        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        vm.expectEmit(true, false, false, false);
        emit IERC8183.JobExpired(1);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(1, client, 500);
        vm.prank(stranger);
        escrow.claimRefund(1);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(client), 1000);

        // claimRefund 不调 Hook — counter 未增加
        assertEq(hook.beforeCount(), bcBefore);
        assertEq(hook.afterCount(), acBefore);
    }

    // ================================================================
    // IT-009: Submitted 状态过期 → 任意人 claimRefund 成功
    // ================================================================
    function test_IT009_SubmittedExpiredClaimRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        uint256 shortExpiry = block.timestamp + 3600;

        // ── setup to Submitted ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, shortExpiry, "desc", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(1, provider, bytes32("work"));
        vm.prank(provider);
        escrow.submit(jobId, bytes32("work"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));

        // ── warp past expiry ──
        vm.warp(shortExpiry + 1);
        assertGt(block.timestamp, shortExpiry);

        // ── claimRefund (stranger) ──
        vm.expectEmit(true, false, false, false);
        emit IERC8183.JobExpired(1);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(1, client, 500);
        vm.prank(stranger);
        escrow.claimRefund(1);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(client), 1000);
        assertEq(token.balanceOf(provider), 0);  // Provider 分文未得
    }

    // ================================================================
    // IT-010: 过期后 submit 仍可执行（无过期拦截），但可被 claimRefund 覆盖
    // ================================================================
    function test_IT010_SubmitAfterExpiryThenClaimRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        uint256 shortExpiry = block.timestamp + 3600;

        // ── setup to Funded ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, shortExpiry, "desc", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        // ── warp past expiry ──
        vm.warp(shortExpiry + 1);
        assertGt(block.timestamp, shortExpiry);
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));

        // ── submit after expiry — expect SUCCESS (contract has no expiry check) ──
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(1, provider, bytes32("late work"));
        vm.prank(provider);
        escrow.submit(1, bytes32("late work"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));

        // ── claimRefund can still override ──
        vm.prank(stranger);
        escrow.claimRefund(1);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(client), 1000);
    }

    // ================================================================
    // IT-011: Expired 后重复 claimRefund → revert
    // ================================================================
    function test_IT011_DuplicateClaimRefundReverts() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        uint256 shortExpiry = block.timestamp + 3600;

        // ── setup to Funded + expire + first claimRefund ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, shortExpiry, "desc", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        vm.warp(shortExpiry + 1);
        vm.prank(stranger);
        escrow.claimRefund(1);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(address(escrow)), 0);

        // ── second claimRefund → revert ──
        vm.expectRevert(bytes("ERC8183: job not in refundable state"));
        vm.prank(stranger);
        escrow.claimRefund(1);

        // 状态和余额不变
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // ================================================================
    // IT-012: block.timestamp 恰好等于 expiredAt → claimRefund 成功
    // ================================================================
    function test_IT012_ExpiredAtExactBoundaryClaimRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        uint256 exactExpiry = block.timestamp + 3600;

        // ── setup to Funded ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, exactExpiry, "desc", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        // ── warp to EXACTLY expiredAt ──
        vm.warp(exactExpiry);
        assertEq(block.timestamp, exactExpiry);

        // ── claimRefund → success (>=) ──
        vm.expectEmit(true, false, false, false);
        emit IERC8183.JobExpired(1);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(1, client, 500);
        vm.prank(stranger);
        escrow.claimRefund(1);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
    }
}
