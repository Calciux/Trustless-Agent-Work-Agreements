// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title PerJobTokenTest — UT-105 ~ UT-112 (per-job payment token)
contract PerJobTokenTest is Test {
    MockERC20 public tokenG; // global default token
    MockERC20 public tokenA; // per-job token for job1
    MockERC20 public tokenB; // per-job token for UT-111 multi-token test
    ERC8183Escrow public escrow;

    address public client;
    address public provider;
    address public evaluator;
    uint256 public expiredAt;

    function setUp() public {
        tokenG = new MockERC20();
        tokenA = new MockERC20();
        tokenB = new MockERC20();

        // Deploy escrow with tokenG as global default, treasury=0, feeBps=0
        escrow = new ERC8183Escrow(address(tokenG), address(0), 0);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: create job with 6-param createJob, per-job token=tokenA, provider=address(0)
    function _createJobWithTokenA() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0), address(tokenA));
    }

    // @dev Helper: create job with 6-param createJob, per-job token=tokenB, provider=address(0)
    function _createJobWithTokenB() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0), address(tokenB));
    }

    // @dev Helper: create job with 6-param createJob, per-job token=address(0)
    function _createJobWithZeroToken() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0), address(0));
    }

    // @dev Helper: setup job to Funded with the given token and budget
    //      Caller must have minted and approved token for client already
    function _setupFunded(uint256 jid, MockERC20 token, uint256 budgetAmt) internal {
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        token.mint(client, budgetAmt);
        token.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();
    }

    // @dev Helper: setup job to Submitted with the given token and budget
    function _setupSubmitted(uint256 jid, MockERC20 token, uint256 budgetAmt) internal {
        _setupFunded(jid, token, budgetAmt);
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-105: createJob (6 params) — per-job token 正常创建
    // ═══════════════════════════════════════════════════════════════
    function test_UT105_CreateJob6Param_WithPerJobToken() public {
        vm.expectEmit(true, true, true, true);
        emit IERC8183.JobCreated(1, client, address(0), evaluator, expiredAt);

        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0), address(tokenA));

        assertEq(jid, 1, "jobId should be 1");
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.paymentToken, address(tokenA), "paymentToken should be tokenA");
        assertEq(job.client, client, "client mismatch");
        assertEq(job.provider, address(0), "provider should be 0");
        assertEq(job.evaluator, evaluator, "evaluator mismatch");
        assertEq(job.budget, 0, "budget should be 0");
        assertEq(uint256(job.status), uint256(IERC8183.Status.Open), "status should be Open");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-106: createJob (6 params) — paymentToken=address(0) 等价旧版
    // ═══════════════════════════════════════════════════════════════
    function test_UT106_CreateJob6Param_WithZeroTokenFallsBack() public {
        vm.prank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0), address(0));

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.paymentToken, address(0), "paymentToken should be address(0)");

        // Verify fallback: fund should use global tokenG
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 500);
        tokenG.mint(client, 500);
        tokenG.approve(address(escrow), 500);
        escrow.fund(jid, 500);
        vm.stopPrank();

        // tokenA should be untouched
        assertEq(tokenA.balanceOf(address(escrow)), 0, "tokenA escrow should be 0");
        assertEq(tokenG.balanceOf(address(escrow)), 500, "tokenG escrow should be 500");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-107: fund — per-job token 下使用正确 token (transferFrom)
    // ═══════════════════════════════════════════════════════════════
    function test_UT107_Fund_UsesPerJobToken() public {
        uint256 jid = _createJobWithTokenA();
        uint256 budgetAmt = 1000;

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        tokenA.mint(client, budgetAmt);
        tokenA.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Funded), "status should be Funded");
        assertEq(tokenA.balanceOf(address(escrow)), budgetAmt, "tokenA escrow balance should be 1000");
        assertEq(tokenA.balanceOf(client), 0, "client tokenA balance should be 0");
        // global tokenG should be untouched
        assertEq(tokenG.balanceOf(address(escrow)), 0, "tokenG escrow should be 0");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-108: complete — per-job token 下 complete 使用正确 token + 手续费
    // ═══════════════════════════════════════════════════════════════
    function test_UT108_Complete_UsesPerJobTokenWithFees() public {
        // Re-deploy escrow with treasury and feeBps for this test
        address treasury = makeAddr("treasury");
        ERC8183Escrow escrowWithFees = new ERC8183Escrow(address(tokenA), treasury, 250); // 2.5%
        uint256 budgetAmt = 10000;

        vm.prank(client);
        uint256 jid = escrowWithFees.createJob(address(0), evaluator, expiredAt, "desc", address(0), address(tokenA));

        vm.startPrank(client);
        escrowWithFees.setProvider(jid, provider);
        escrowWithFees.setBudget(jid, budgetAmt);
        tokenA.mint(client, budgetAmt);
        tokenA.approve(address(escrowWithFees), budgetAmt);
        escrowWithFees.fund(jid, budgetAmt);
        vm.stopPrank();

        vm.prank(provider);
        escrowWithFees.submit(jid, bytes32(0));

        uint256 providerBefore = tokenA.balanceOf(provider);
        uint256 treasuryBefore = tokenA.balanceOf(treasury);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.PaymentReleased(jid, provider, 9750);

        vm.prank(evaluator);
        escrowWithFees.complete(jid, bytes32(0));

        assertEq(uint256(escrowWithFees.getStatus(jid)), uint256(IERC8183.Status.Completed));
        // Provider gets 10000 - 250 = 9750 tokenA
        assertEq(tokenA.balanceOf(provider) - providerBefore, 9750, "provider should receive 9750 tokenA");
        // Treasury gets 250 tokenA fee
        assertEq(tokenA.balanceOf(treasury) - treasuryBefore, 250, "treasury should receive 250 tokenA");
        // Escrow should be empty
        assertEq(tokenA.balanceOf(address(escrowWithFees)), 0, "escrow tokenA should be 0");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-109: reject (Funded) — per-job token 退款使用正确 token
    // ═══════════════════════════════════════════════════════════════
    function test_UT109_Reject_RefundsInPerJobToken() public {
        uint256 jid = _createJobWithTokenA();
        uint256 budgetAmt = 1000;
        _setupFunded(jid, tokenA, budgetAmt);

        uint256 clientBefore = tokenA.balanceOf(client);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(jid, client, budgetAmt);

        vm.prank(evaluator);
        escrow.reject(jid, bytes32(0));

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Rejected));
        assertEq(tokenA.balanceOf(client) - clientBefore, budgetAmt, "client should be refunded 1000 tokenA");
        assertEq(tokenA.balanceOf(address(escrow)), 0, "escrow tokenA should be 0");
        // global tokenG untouched
        assertEq(tokenG.balanceOf(address(escrow)), 0, "tokenG escrow should be 0");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-110: claimRefund — per-job token 退款使用正确 token
    // ═══════════════════════════════════════════════════════════════
    function test_UT110_ClaimRefund_RefundsInPerJobToken() public {
        uint256 jid = _createJobWithTokenA();
        uint256 budgetAmt = 500;
        _setupFunded(jid, tokenA, budgetAmt);

        // Warp past expiredAt
        vm.warp(expiredAt + 1);

        uint256 clientBefore = tokenA.balanceOf(client);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(jid, client, budgetAmt);

        escrow.claimRefund(jid);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Expired));
        assertEq(tokenA.balanceOf(client) - clientBefore, budgetAmt, "client should be refunded 500 tokenA");
        assertEq(tokenA.balanceOf(address(escrow)), 0, "escrow tokenA should be 0");
        assertEq(tokenG.balanceOf(address(escrow)), 0, "tokenG escrow should be 0");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-111: 两个 job 使用不同 paymentToken 并存不干扰
    // ═══════════════════════════════════════════════════════════════
    function test_UT111_TwoJobsDifferentTokensNoInterference() public {
        // Job1 with tokenA, budget=500
        uint256 jid1 = _createJobWithTokenA();
        _setupSubmitted(jid1, tokenA, 500);

        // Job2 with tokenB, budget=300
        uint256 jid2 = _createJobWithTokenB();
        _setupSubmitted(jid2, tokenB, 300);

        // Complete job1
        vm.prank(evaluator);
        escrow.complete(jid1, bytes32(0));

        // Complete job2
        vm.prank(evaluator);
        escrow.complete(jid2, bytes32(0));

        // Verify job1 operates only on tokenA
        assertEq(tokenA.balanceOf(provider), 500, "provider should have 500 tokenA from job1");
        assertEq(tokenA.balanceOf(address(escrow)), 0, "escrow tokenA should be 0");

        // Verify job2 operates only on tokenB
        assertEq(tokenB.balanceOf(provider), 300, "provider should have 300 tokenB from job2");
        assertEq(tokenB.balanceOf(address(escrow)), 0, "escrow tokenB should be 0");

        // tokenG untouched
        assertEq(tokenG.balanceOf(address(escrow)), 0, "tokenG escrow should be 0");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-112: paymentToken=address(0) 回退到全局默认 token
    // ═══════════════════════════════════════════════════════════════
    function test_UT112_ResolveToken_FallsBackToGlobalWhenZero() public {
        uint256 jid = _createJobWithZeroToken();
        uint256 budgetAmt = 400;

        // Fund should use global tokenG (not tokenA)
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        tokenG.mint(client, budgetAmt);
        tokenG.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Funded));
        assertEq(tokenG.balanceOf(address(escrow)), budgetAmt, "tokenG escrow should be 400");
        assertEq(tokenA.balanceOf(address(escrow)), 0, "tokenA escrow should be 0");
        assertEq(tokenB.balanceOf(address(escrow)), 0, "tokenB escrow should be 0");
    }
}
