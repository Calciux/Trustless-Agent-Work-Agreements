// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

// @title RejectPathsTest — IT-003 ~ IT-007: Reject 路径集成测试
contract RejectPathsTest is Test {
    MockERC20 token;
    address client = makeAddr("client");
    address provider = makeAddr("provider");
    address provider2 = makeAddr("provider2");
    address evaluator = makeAddr("evaluator");
    address evaluator2 = makeAddr("evaluator2");
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

    // @dev Helper: create + setProvider + setBudget → Open
    function _createOpenWithBudget(ERC8183Escrow escrow, uint256 budgetAmt) internal returns (uint256) {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "test job", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        vm.stopPrank();
        return jid;
    }

    // @dev Helper: create + setProvider + setBudget + fund → Funded
    function _setupFunded(ERC8183Escrow escrow, uint256 budgetAmt) internal returns (uint256) {
        uint256 jid = _createOpenWithBudget(escrow, budgetAmt);
        token.mint(client, budgetAmt);
        vm.prank(client);
        token.approve(address(escrow), budgetAmt);
        vm.prank(client);
        escrow.fund(jid, budgetAmt);
        return jid;
    }

    // @dev Helper: create + setProvider + setBudget + fund + submit → Submitted
    function _setupSubmitted(ERC8183Escrow escrow, uint256 budgetAmt) internal returns (uint256) {
        uint256 jid = _setupFunded(escrow, budgetAmt);
        vm.prank(provider);
        escrow.submit(jid, bytes32(uint256(1)));
        return jid;
    }

    // ================================================================
    // IT-003: Client rejects in Open（无 provider，无 budget，无资金托管）
    // ================================================================
    function test_IT003_ClientRejectsOpenNoRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);

        // ── Step 1: createJob ──
        vm.prank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "test job", address(0));

        assertEq(jobId, 1);
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client);
        assertEq(job.provider, address(0));
        assertEq(job.budget, 0);

        // ── Step 2: reject(Client) ──
        bytes32 reason = bytes32("no");
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(1, client, reason);
        vm.prank(client);
        escrow.reject(1, reason);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Rejected));
        // 不发射 Refunded（无托管资金），余额不变
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(client), 1000);
    }

    // ================================================================
    // IT-004: Client rejects in Open（provider + budget 已设，但未 fund）
    // ================================================================
    function test_IT004_ClientRejectsOpenWithBudgetNoRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);

        // ── Step 1: createJob + setProvider + setBudget ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "test job", address(0));
        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(1, provider);
        escrow.setProvider(jobId, provider);
        vm.expectEmit(true, false, false, true);
        emit IERC8183.BudgetSet(1, 500);
        escrow.setBudget(jobId, 500);
        vm.stopPrank();

        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.provider, provider);
        assertEq(job.budget, 500);

        // ── Step 2: reject(Client) ──
        bytes32 reason = bytes32("changed mind");
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(1, client, reason);
        vm.prank(client);
        escrow.reject(1, reason);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Rejected));
        // budget 仅为链上数字，资金从未转入合约
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(client), 1000);
    }

    // ================================================================
    // IT-005: Evaluator rejects in Funded（全额退款）
    // ================================================================
    function test_IT005_EvaluatorRejectsFundedFullRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // ── Step 1: setup to Funded ──
        uint256 jobId = _setupFunded(escrow, 500);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(token.balanceOf(address(escrow)), 500);
        assertEq(token.balanceOf(client), 500);

        // ── Step 2: reject(Evaluator) ──
        bytes32 reason = bytes32("not qualified");
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(1, evaluator, reason);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(1, client, 500);
        vm.prank(evaluator);
        escrow.reject(1, reason);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Rejected));
        assertEq(token.balanceOf(address(escrow)), 0);  // 全额退还
        assertEq(token.balanceOf(client), 1000);        // 恢复 fund 前余额
        assertEq(token.balanceOf(evaluator), 0);        // Evaluator 永不触碰资金
    }

    // ================================================================
    // IT-006: Evaluator rejects in Submitted（全额退款）
    // ================================================================
    function test_IT006_EvaluatorRejectsSubmittedFullRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // ── Step 1: setup to Funded + submit to Submitted ──
        uint256 jobId = _setupFunded(escrow, 500);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(1, provider, bytes32(uint256(1)));
        vm.prank(provider);
        escrow.submit(jobId, bytes32(uint256(1)));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));

        // ── Step 2: reject(Evaluator) ──
        bytes32 reason = bytes32("quality fail");
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(1, evaluator, reason);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(1, client, 500);
        vm.prank(evaluator);
        escrow.reject(1, reason);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Rejected));
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(client), 1000);
        assertEq(token.balanceOf(provider), 0);  // Provider 未收款
    }

    // ================================================================
    // IT-007: Reject 退款后资金闭环 — Client 用退款创建新 Job 并 Happy Path
    // ================================================================
    function test_IT007_RefundClosedLoopNewJobHappyPath() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // ── Job 1: 被拒退款 ──
        uint256 expiredAt1 = block.timestamp + 7 days;
        vm.startPrank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator, expiredAt1, "job1", address(0));
        escrow.setProvider(jid1, provider);
        escrow.setBudget(jid1, 400);
        escrow.fund(jid1, 400);
        vm.stopPrank();

        vm.prank(evaluator);
        escrow.reject(jid1, bytes32("rejected"));

        assertEq(token.balanceOf(client), 1000);  // 退款全额到账

        // ── Job 2: Happy Path（退款资金）──
        uint256 expiredAt2 = block.timestamp + 7 days;
        vm.startPrank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator2, expiredAt2, "job2", address(0));
        escrow.setProvider(jid2, provider2);
        escrow.setBudget(jid2, 400);
        escrow.fund(jid2, 400);
        vm.stopPrank();

        assertEq(jid2, 2);
        assertEq(escrow.jobCount(), 2);  // jobId 不回退
        assertEq(token.balanceOf(client), 600);
        assertEq(token.balanceOf(address(escrow)), 400);

        vm.prank(provider2);
        escrow.submit(jid2, bytes32("work2"));

        vm.prank(evaluator2);
        escrow.complete(jid2, bytes32("ok"));

        assertEq(uint256(escrow.getStatus(2)), uint256(IERC8183.Status.Completed));
        assertEq(token.balanceOf(provider2), 400);
        assertEq(token.balanceOf(address(escrow)), 0);
    }
}
