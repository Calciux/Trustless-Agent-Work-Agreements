// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {RevertingMockHook} from "../../mocks/RevertingMockHook.sol";

// @title HookInteractionsTest — IT-013 ~ IT-014: Hook revert 集成测试
contract HookInteractionsTest is Test {
    MockERC20 token;
    address client = makeAddr("client");
    address provider = makeAddr("provider");
    address evaluator = makeAddr("evaluator");
    uint256 expiredAt;

    // 函数选择器常量（与 ERC8183Escrow 中定义一致）
    bytes4 constant SEL_FUND     = bytes4(keccak256("fund(uint256,uint256)"));
    bytes4 constant SEL_COMPLETE = bytes4(keccak256("complete(uint256,bytes32)"));

    function setUp() public {
        token = new MockERC20();
        expiredAt = block.timestamp + 7 days;
    }

    // ================================================================
    // IT-013: beforeAction revert → 整个 tx 回滚（以 fund 为例）
    // ================================================================
    function test_IT013_BeforeActionRevertRollsBackFundTx() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // Deploy hook that reverts in beforeAction for SEL_FUND
        RevertingMockHook hook = new RevertingMockHook(true, false, SEL_FUND);

        // ── createJob + setProvider + setBudget ──
        vm.startPrank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(hook));
        escrow.setProvider(jobId, provider);
        escrow.setBudget(jobId, 500);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));
        assertEq(token.balanceOf(address(escrow)), 0);

        // ── fund → expect revert from hook's beforeAction ──
        vm.expectRevert(bytes("Hook: beforeAction reverted"));
        vm.prank(client);
        escrow.fund(1, 500);

        // 状态未变
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));
        // 资金未转入
        assertEq(token.balanceOf(address(escrow)), 0);
        // 资金未扣除
        assertEq(token.balanceOf(client), 1000);
    }

    // ================================================================
    // IT-014: afterAction revert → 整个 tx 回滚（以 complete 为例）
    // ================================================================
    function test_IT014_AfterActionRevertRollsBackCompleteTx() public {
        ERC8183Escrow escrow = new ERC8183Escrow(address(token), address(0), 0);
        token.mint(client, 1000);
        vm.prank(client);
        token.approve(address(escrow), 1000);

        // Deploy hook that reverts in afterAction for SEL_COMPLETE
        RevertingMockHook hook = new RevertingMockHook(false, true, SEL_COMPLETE);

        // ── setup to Submitted ──
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

        // ── complete → expect revert from hook's afterAction ──
        vm.expectRevert(bytes("Hook: afterAction reverted"));
        vm.prank(evaluator);
        escrow.complete(1, bytes32("ok"));

        // 状态仍为 Submitted（不是 Completed — tx 原子回滚）
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Submitted));
        // 资金未动
        assertEq(token.balanceOf(address(escrow)), 500);
        // Provider 未收款
        assertEq(token.balanceOf(provider), 0);
    }
}
