// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

// @title MultiJobTest — IT-017 ~ IT-019: 多 Job 并存集成测试
contract MultiJobTest is Test {
    MockERC20 token;
    address client = makeAddr("client");
    address provider1 = makeAddr("provider1");
    address provider2 = makeAddr("provider2");
    address evaluator1 = makeAddr("evaluator1");
    address evaluator2 = makeAddr("evaluator2");
    uint256 expiredAt;

    function setUp() public {
        token = new MockERC20();
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: full Happy Path for one job
    function _runHappyPath(
        ERC8183Escrow escrow,
        uint256 jid,
        address prov,
        address eval,
        uint256 budgetAmt,
        bytes32 deliverable
    ) internal {
        // Approve needed amount
        uint256 need = budgetAmt;
        vm.prank(client);
        token.approve(address(escrow), need);

        vm.startPrank(client);
        escrow.setProvider(jid, prov);
        escrow.setBudget(jid, budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();

        vm.prank(prov);
        escrow.submit(jid, deliverable);

        vm.prank(eval);
        escrow.complete(jid, bytes32("ok"));
    }

    // ================================================================
    // IT-017: 两个 Job 独立 Happy Path（无手续费）
    // ================================================================
    function test_IT017_TwoIndependentHappyPaths() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 2000);

        uint256 expiry1 = block.timestamp + 7 days;
        uint256 expiry2 = block.timestamp + 7 days;

        // ── Job 1: createJob ──
        vm.prank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator1, expiry1, "job1", address(0));
        assertEq(jid1, 1);
        assertEq(escrow.jobCount(), 1);

        // ── Job 1: Happy Path ──
        _runHappyPath(escrow, jid1, provider1, evaluator1, 500, bytes32("work1"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
        assertEq(token.balanceOf(provider1), 500);
        assertEq(token.balanceOf(address(escrow)), 0);

        // ── Job 2: createJob ──
        vm.prank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator2, expiry2, "job2", address(0));
        assertEq(jid2, 2);
        assertEq(escrow.jobCount(), 2);

        IERC8183.Job memory job2 = escrow.getJob(2);
        assertEq(job2.client, client);
        assertEq(job2.evaluator, evaluator2);

        // ── Job 2: Happy Path ──
        // @dev Job2 fund 后的中间态 Escrow 余额由 UT-fund 覆盖，此处验证终极态
        _runHappyPath(escrow, jid2, provider2, evaluator2, 700, bytes32("work2"));

        assertEq(uint256(escrow.getStatus(2)), uint256(IERC8183.Status.Completed));
        assertEq(token.balanceOf(provider2), 700);
        assertEq(token.balanceOf(address(escrow)), 0);

        // Job1 状态未被干扰
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
    }

    // ================================================================
    // IT-018: Job1 Funded + Job2 Open 并存，互不干扰
    // ================================================================
    function test_IT018_MixedStatesCoexist() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 2000);
        vm.prank(client);
        token.approve(address(escrow), 2000);

        uint256 expiry1 = block.timestamp + 7 days;
        uint256 expiry2 = block.timestamp + 7 days;

        // ── Job 1: fund 后停留 ──
        vm.startPrank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator1, expiry1, "job1", address(0));
        escrow.setProvider(jid1, provider1);
        escrow.setBudget(jid1, 500);
        escrow.fund(jid1, 500);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(escrow.getJob(1).budget, 500);

        // ── Job 2: 仅创建（Open）──
        vm.startPrank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator2, expiry2, "job2", address(0));
        escrow.setProvider(jid2, provider2);
        escrow.setBudget(jid2, 300);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(2)), uint256(IERC8183.Status.Open));
        assertEq(escrow.getJob(2).budget, 300);

        // Job1 状态未受 Job2 操作影响
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(escrow.getJob(1).budget, 500);

        // 仅 Job1 资金在 escrow
        assertEq(token.balanceOf(address(escrow)), 500);
    }

    // ================================================================
    // IT-019: 同一 Client 完成 Job1 后创建并 fund Job2 — 余额闭环
    // ================================================================
    function test_IT019_SameClientBalanceTracking() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        uint256 expiry1 = block.timestamp + 7 days;
        uint256 expiry2 = block.timestamp + 7 days;

        // ── Job 1: Happy Path ──
        vm.startPrank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator1, expiry1, "job1", address(0));
        escrow.setProvider(jid1, provider1);
        escrow.setBudget(jid1, 400);
        escrow.fund(jid1, 400);
        vm.stopPrank();

        vm.prank(provider1);
        escrow.submit(jid1, bytes32("work1"));

        vm.prank(evaluator1);
        escrow.complete(jid1, bytes32("ok"));

        assertEq(token.balanceOf(client), 600);  // 1000 - 400
        assertEq(token.balanceOf(provider1), 400);

        // ── Job 2: same Client ──
        vm.startPrank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator2, expiry2, "job2", address(0));
        escrow.setProvider(jid2, provider2);
        escrow.setBudget(jid2, 300);
        escrow.fund(jid2, 300);
        vm.stopPrank();

        assertEq(token.balanceOf(client), 300);  // 600 - 300

        vm.prank(provider2);
        escrow.submit(jid2, bytes32("work2"));

        vm.prank(evaluator2);
        escrow.complete(jid2, bytes32("ok"));

        assertEq(token.balanceOf(client), 300);
        assertEq(token.balanceOf(provider2), 300);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
        assertEq(uint256(escrow.getStatus(2)), uint256(IERC8183.Status.Completed));
        assertEq(escrow.jobCount(), 2);
    }
}
