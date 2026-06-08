// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

// @title EdgeIntegrationTest — IT-020 ~ IT-022: 边界集成测试
contract EdgeIntegrationTest is Test {
    MockERC20 token;
    address client = makeAddr("client");
    address provider = makeAddr("provider");
    address evaluator = makeAddr("evaluator");
    address treasuryAddr = makeAddr("treasury");
    address stranger = makeAddr("stranger");
    uint256 expiredAt;

    function setUp() public {
        token = new MockERC20();
        expiredAt = block.timestamp + 7 days;
    }

    // ================================================================
    // IT-020: expiredAt 极短（1 秒），Provider 抢在 claimRefund 前 submit → 成功
    // ================================================================
    function test_IT020_UltraShortExpirySubmitBeforeClaimRefund() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        uint256 shortExpiry = block.timestamp + 1;

        // ── setup to Funded ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, shortExpiry, "urgent", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        escrow.fund(jobId, 500);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertLt(block.timestamp, shortExpiry);

        // ── warp past expiry ──
        vm.warp(block.timestamp + 2);
        assertGt(block.timestamp, shortExpiry);
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));

        // ── submit after expiry — 成功（合约无过期拦截）──
        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(1, provider, bytes32("late"));
        vm.prank(provider);
        escrow.submit(1, bytes32("late"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));

        // ── claimRefund 可覆盖 ──
        vm.prank(stranger);
        escrow.claimRefund(1);

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Expired));
        assertEq(token.balanceOf(client), 1000);
    }

    // ================================================================
    // IT-021: Owner 中途修改 feeBps → 影响后续 complete 的手续费计算
    // ================================================================
    function test_IT021_MidJobFeeBpsChange() public {
        // Deploy with feeBps=250 (2.5%)
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), treasuryAddr, 250);
        token.mint(client, 10000);
        vm.prank(client);
        token.approve(address(escrow), 10000);

        uint256 budget = 10000;
        uint256 jobExpiry = block.timestamp + 7 days;

        // ── 阶段 1: 旧费率下创建 + fund ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, jobExpiry, "desc", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, budget);
        escrow.fund(jobId, budget);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(escrow.feeBps(), 250);  // 旧费率

        // ── 阶段 2: Owner 改费率 ──
        // address(this) is the deployer → owner
        escrow.setFeeBps(500);  // 改为 5%
        assertEq(escrow.feeBps(), 500);  // 新费率

        // ── 阶段 3: 新费率下 submit + complete ──
        vm.prank(provider);
        escrow.submit(jobId, bytes32("work"));

        uint256 providerBalBefore = token.balanceOf(provider);
        uint256 treasuryBalBefore = token.balanceOf(treasuryAddr);

        vm.prank(evaluator);
        escrow.complete(jobId, bytes32("ok"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
        // Provider 收 10000 - 500 = 9500（按新费率 5%）
        assertEq(token.balanceOf(provider), providerBalBefore + 9500);
        // treasury 收 500
        assertEq(token.balanceOf(treasuryAddr), treasuryBalBefore + 500);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    // ================================================================
    // IT-022: Owner 中途修改 treasury → 影响后续 complete 的收费开关
    // ================================================================
    function test_IT022_MidJobTreasuryChange() public {
        // Deploy with treasury=address(0), feeBps=500 (5%)
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 500);
        token.mint(client, 10000);
        vm.prank(client);
        token.approve(address(escrow), 10000);

        uint256 budget = 10000;
        uint256 jobExpiry = block.timestamp + 7 days;

        // ── 阶段 1: 零 treasury 下创建 + fund ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, jobExpiry, "desc", address(0));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, budget);
        escrow.fund(jobId, budget);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded));
        assertEq(escrow.treasury(), address(0));  // 零 treasury

        // ── 阶段 2: Owner 设置 treasury ──
        escrow.setTreasury(treasuryAddr);  // 从 address(0) 改为非零
        assertEq(escrow.treasury(), treasuryAddr);  // 新 treasury

        // ── 阶段 3: 新 treasury 下 submit + complete ──
        vm.prank(provider);
        escrow.submit(jobId, bytes32("work"));

        uint256 providerBalBefore = token.balanceOf(provider);
        uint256 treasuryBalBefore = token.balanceOf(treasuryAddr);

        vm.prank(evaluator);
        escrow.complete(jobId, bytes32("ok"));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Completed));
        // Provider 收 9500（手续费 5% 被触发）
        assertEq(token.balanceOf(provider), providerBalBefore + 9500);
        // treasuryAddr 收 500
        assertEq(token.balanceOf(treasuryAddr), treasuryBalBefore + 500);
        assertEq(token.balanceOf(address(escrow)), 0);
    }
}
