// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockHook} from "../mocks/MockHook.sol";

// @title HookCallbacksTest — UT-076 ~ UT-088
contract HookCallbacksTest is Test {
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

    // @dev Helper: create job with hook, provider=0
    function _createJobWithHook() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(hook));
    }

    // @dev Helper: create job without hook
    function _createJobNoHook() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
    }

    // ─────────────────────────────────────────────────────────────────
    // setProvider Hook tests
    // ─────────────────────────────────────────────────────────────────

    // ── UT-076: setProvider + hook≠0 → beforeAction + afterAction ────
    function test_UT076_SetProvider_HookCalled() public {
        uint256 jid = _createJobWithHook();
        bytes4 expectedSel = bytes4(keccak256("setProvider(uint256,address)"));

        vm.prank(client);
        escrow.setProvider(jid, provider);

        assertEq(hook.beforeCount(), 1, "beforeAction should be called once");
        assertEq(hook.afterCount(), 1, "afterAction should be called once");
        assertEq(hook.lastSelector(), expectedSel);
        assertEq(hook.lastJobId(), jid);
    }

    // ── UT-077: setProvider + hook=0 → no Hook call ──────────────────
    function test_UT077_SetProvider_NoHookCalled_WhenHookZero() public {
        uint256 jid = _createJobNoHook();
        uint256 bc = hook.beforeCount();
        uint256 ac = hook.afterCount();

        vm.prank(client);
        escrow.setProvider(jid, provider);

        assertEq(hook.beforeCount(), bc, "beforeAction should not be called");
        assertEq(hook.afterCount(), ac, "afterAction should not be called");
    }

    // ─────────────────────────────────────────────────────────────────
    // setBudget Hook tests
    // ─────────────────────────────────────────────────────────────────

    // ── UT-078: setBudget + hook≠0 → beforeAction + afterAction ──────
    function test_UT078_SetBudget_HookCalled() public {
        uint256 jid = _createJobWithHook();
        bytes4 expectedSel = bytes4(keccak256("setBudget(uint256,uint256)"));

        vm.prank(client);
        escrow.setBudget(jid, 100);

        assertEq(hook.beforeCount(), 1);
        assertEq(hook.afterCount(), 1);
        assertEq(hook.lastSelector(), expectedSel);
    }

    // ── UT-079: setBudget + hook=0 → no Hook call ────────────────────
    function test_UT079_SetBudget_NoHookCalled_WhenHookZero() public {
        uint256 jid = _createJobNoHook();
        uint256 bc = hook.beforeCount();
        uint256 ac = hook.afterCount();

        vm.prank(client);
        escrow.setBudget(jid, 100);

        assertEq(hook.beforeCount(), bc);
        assertEq(hook.afterCount(), ac);
    }

    // ─────────────────────────────────────────────────────────────────
    // fund Hook tests
    // ─────────────────────────────────────────────────────────────────

    // ── UT-080: fund + hook≠0 → beforeAction + afterAction ───────────
    function test_UT080_Fund_HookCalled() public {
        uint256 jid = _createJobWithHook();
        bytes4 expectedSel = bytes4(keccak256("fund(uint256,uint256)"));

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        vm.stopPrank();

        // Record counts after setup, before fund
        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        vm.prank(client);
        escrow.fund(jid, 100);

        // Verify fund itself triggered exactly 1 before + 1 after
        assertEq(hook.beforeCount(), bcBefore + 1, "fund should trigger beforeAction once");
        assertEq(hook.afterCount(), acBefore + 1, "fund should trigger afterAction once");
        assertEq(hook.lastSelector(), expectedSel);
    }

    // ── UT-081: fund + hook=0 → no Hook call ─────────────────────────
    function test_UT081_Fund_NoHookCalled_WhenHookZero() public {
        uint256 jid = _createJobNoHook();
        uint256 bc = hook.beforeCount();
        uint256 ac = hook.afterCount();

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        assertEq(hook.beforeCount(), bc);
        assertEq(hook.afterCount(), ac);
    }

    // ─────────────────────────────────────────────────────────────────
    // submit Hook tests
    // ─────────────────────────────────────────────────────────────────

    // ── UT-082: submit + hook≠0 → beforeAction + afterAction ─────────
    function test_UT082_Submit_HookCalled() public {
        uint256 jid = _createJobWithHook();
        bytes4 expectedSel = bytes4(keccak256("submit(uint256,bytes32)"));

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        // Record counts after setup
        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        assertEq(hook.beforeCount(), bcBefore + 1, "beforeAction called for submit");
        assertEq(hook.afterCount(), acBefore + 1, "afterAction called for submit");
        assertEq(hook.lastSelector(), expectedSel);
    }

    // ── UT-083: submit + hook=0 → no Hook call ───────────────────────
    function test_UT083_Submit_NoHookCalled_WhenHookZero() public {
        uint256 jid = _createJobNoHook();
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        uint256 bc = hook.beforeCount();
        uint256 ac = hook.afterCount();

        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        assertEq(hook.beforeCount(), bc);
        assertEq(hook.afterCount(), ac);
    }

    // ─────────────────────────────────────────────────────────────────
    // complete Hook tests
    // ─────────────────────────────────────────────────────────────────

    // ── UT-084: complete + hook≠0 → beforeAction + afterAction ───────
    function test_UT084_Complete_HookCalled() public {
        uint256 jid = _createJobWithHook();
        bytes4 expectedSel = bytes4(keccak256("complete(uint256,bytes32)"));

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(hook.beforeCount(), bcBefore + 1);
        assertEq(hook.afterCount(), acBefore + 1);
        assertEq(hook.lastSelector(), expectedSel);
    }

    // ── UT-085: complete + hook=0 → no Hook call ─────────────────────
    function test_UT085_Complete_NoHookCalled_WhenHookZero() public {
        uint256 jid = _createJobNoHook();
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        uint256 bc = hook.beforeCount();
        uint256 ac = hook.afterCount();

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(hook.beforeCount(), bc);
        assertEq(hook.afterCount(), ac);
    }

    // ─────────────────────────────────────────────────────────────────
    // reject Hook tests
    // ─────────────────────────────────────────────────────────────────

    // ── UT-086: reject + hook≠0 → beforeAction + afterAction ─────────
    function test_UT086_Reject_HookCalled() public {
        uint256 jid = _createJobWithHook();
        bytes4 expectedSel = bytes4(keccak256("reject(uint256,bytes32)"));

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        // Evaluator rejects from Funded state
        vm.prank(evaluator);
        escrow.reject(jid, bytes32(0));

        assertEq(hook.beforeCount(), bcBefore + 1);
        assertEq(hook.afterCount(), acBefore + 1);
        assertEq(hook.lastSelector(), expectedSel);
    }

    // ── UT-087: reject + hook=0 → no Hook call ───────────────────────
    function test_UT087_Reject_NoHookCalled_WhenHookZero() public {
        uint256 jid = _createJobNoHook();
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        uint256 bc = hook.beforeCount();
        uint256 ac = hook.afterCount();

        vm.prank(evaluator);
        escrow.reject(jid, bytes32(0));

        assertEq(hook.beforeCount(), bc);
        assertEq(hook.afterCount(), ac);
    }

    // ── UT-088: claimRefund hook≠0 → 不调用 beforeAction/afterAction ─
    function test_UT088_ClaimRefund_NoHookCall() public {
        uint256 jid = _createJobWithHook();

        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        // Verify that submit triggered Hook (as a positive control)
        uint256 beforeSubmitBC = hook.beforeCount();
        uint256 beforeSubmitAC = hook.afterCount();

        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        assertGt(hook.beforeCount(), beforeSubmitBC, "submit should trigger beforeAction");
        assertGt(hook.afterCount(), beforeSubmitAC, "submit should trigger afterAction");

        // Now warp and claimRefund — should NOT trigger Hook
        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        vm.warp(expiredAt + 1);
        escrow.claimRefund(jid);

        assertEq(hook.beforeCount(), bcBefore, "claimRefund must not call beforeAction");
        assertEq(hook.afterCount(), acBefore, "claimRefund must not call afterAction");
        assertEq(token.balanceOf(client), 100, "client should be refunded");
    }
}
