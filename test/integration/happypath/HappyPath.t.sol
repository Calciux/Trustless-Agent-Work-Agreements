// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract HappyPathTest is Test {
    address client = makeAddr("client");
    address provider = makeAddr("provider");
    address evaluator = makeAddr("evaluator");
    address treasury = makeAddr("treasury");

    MockERC20 token;

    function setUp() public {
        token = new MockERC20();
    }

    // ================================================================
    // IT-001: 无手续费 Happy Path
    // ================================================================
    function test_IT001_HappyPath_NoFee() public {
        // ── Deploy (treasury=address(0), feeBps=0) ──
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);

        uint256 budget = 100;
        token.mint(client, budget);
        uint256 expiredAt = block.timestamp + 7 days;

        // ── Step 1: createJob ──
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit IERC8183.JobCreated(1, client, address(0), evaluator, expiredAt);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));

        assertEq(jobId, 1);
        assertEq(escrow.jobCount(), 1);
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));

        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client);
        assertEq(job.evaluator, evaluator);
        assertEq(job.provider, address(0));
        assertEq(job.budget, 0);

        // ── Step 2: setProvider ──
        vm.prank(client);
        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(1, provider);
        escrow.setProvider(1, provider);

        job = escrow.getJob(1);
        assertEq(job.provider, provider);

        // ── Step 3: setBudget ──
        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit IERC8183.BudgetSet(1, budget);
        escrow.setBudget(1, budget);

        job = escrow.getJob(1);
        assertEq(job.budget, budget);

        // ── Step 4: approve ──
        vm.prank(client);
        token.approve(address(escrow), budget);

        assertGe(token.allowance(client, address(escrow)), budget);

        // ── Step 5: fund ──
        uint256 clientBalBefore = token.balanceOf(client);
        uint256 escrowBalBefore = token.balanceOf(address(escrow));

        vm.prank(client);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobFunded(1, client, budget);
        escrow.fund(1, budget);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(token.balanceOf(client), clientBalBefore - budget);
        assertEq(token.balanceOf(address(escrow)), escrowBalBefore + budget);

        // ── Step 6: submit ──
        bytes32 deliverable = bytes32("proof");

        vm.prank(provider);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(1, provider, deliverable);
        escrow.submit(1, deliverable);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));

        // ── Step 7: complete ──
        uint256 providerBalBefore = token.balanceOf(provider);
        uint256 treasuryBalBefore = token.balanceOf(address(0)); // treasury = address(0)

        bytes32 reason = bytes32("ok");

        vm.prank(evaluator);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobCompleted(1, evaluator, reason);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.PaymentReleased(1, provider, budget);
        escrow.complete(1, reason);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(provider), providerBalBefore + budget);
        assertEq(token.balanceOf(address(0)), treasuryBalBefore); // treasury unchanged
    }

    // ================================================================
    // IT-002: 有手续费 Happy Path (2.5%)
    // ================================================================
    function test_IT002_HappyPath_WithFee() public {
        // ── Deploy (treasury≠address(0), feeBps=250) ──
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), treasury, 250);

        uint256 budget = 10000;
        uint256 fee = 250; // 10000 * 250 / 10000
        uint256 payAmount = 9750;
        token.mint(client, budget);
        uint256 expiredAt = block.timestamp + 7 days;

        // ── Step 1: createJob ──
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit IERC8183.JobCreated(1, client, address(0), evaluator, expiredAt);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));

        assertEq(jobId, 1);
        assertEq(escrow.jobCount(), 1);
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));

        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client);
        assertEq(job.evaluator, evaluator);
        assertEq(job.provider, address(0));
        assertEq(job.budget, 0);

        // ── Step 2: setProvider ──
        vm.prank(client);
        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(1, provider);
        escrow.setProvider(1, provider);

        job = escrow.getJob(1);
        assertEq(job.provider, provider);

        // ── Step 3: setBudget ──
        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit IERC8183.BudgetSet(1, budget);
        escrow.setBudget(1, budget);

        job = escrow.getJob(1);
        assertEq(job.budget, budget);

        // ── Step 4: approve ──
        vm.prank(client);
        token.approve(address(escrow), budget);

        assertGe(token.allowance(client, address(escrow)), budget);

        // ── Step 5: fund ──
        uint256 clientBalBefore = token.balanceOf(client);
        uint256 escrowBalBefore = token.balanceOf(address(escrow));

        vm.prank(client);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobFunded(1, client, budget);
        escrow.fund(1, budget);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(token.balanceOf(client), clientBalBefore - budget);
        assertEq(token.balanceOf(address(escrow)), escrowBalBefore + budget);

        // ── Step 6: submit ──
        bytes32 deliverable = bytes32("proof");

        vm.prank(provider);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(1, provider, deliverable);
        escrow.submit(1, deliverable);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));

        // ── Step 7: complete ──
        uint256 providerBalBefore = token.balanceOf(provider);
        uint256 treasuryBalBefore = token.balanceOf(treasury);

        bytes32 reason = bytes32("ok");

        vm.prank(evaluator);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobCompleted(1, evaluator, reason);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.PaymentReleased(1, provider, payAmount);
        escrow.complete(1, reason);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(provider), providerBalBefore + payAmount);
        assertEq(token.balanceOf(treasury), treasuryBalBefore + fee);
    }
}
