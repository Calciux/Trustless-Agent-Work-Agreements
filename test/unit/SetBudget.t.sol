// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockHook} from "../mocks/MockHook.sol";

// @title SetBudgetTest — UT-016 ~ UT-021
contract SetBudgetTest is Test {
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

    // @dev Helper: create a job (Open, provider=0)
    function _createJob() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
    }

    // @dev Helper: create job + set provider (still Open)
    function _createJobWithProvider() internal returns (uint256) {
        uint256 jid = _createJob();
        vm.prank(client);
        escrow.setProvider(jid, provider);
        return jid;
    }

    // ── UT-016: Client 在 Open 状态设置 budget → 成功 ────────────────
    function test_UT016_SetBudget_ClientSucceeds() public {
        uint256 jid = _createJob();

        vm.expectEmit(true, false, false, true);
        emit IERC8183.BudgetSet(jid, 100);

        vm.prank(client);
        escrow.setBudget(jid, 100);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.budget, 100, "budget should be 100");
    }

    // ── UT-017: Provider 在 Open 状态设置 budget → 成功 ──────────────
    function test_UT017_SetBudget_ProviderSucceeds() public {
        uint256 jid = _createJobWithProvider();

        vm.expectEmit(true, false, false, true);
        emit IERC8183.BudgetSet(jid, 200);

        vm.prank(provider);
        escrow.setBudget(jid, 200);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.budget, 200, "budget should be 200");
    }

    // ── UT-018: 既非 Client 也非 Provider 调用 → revert ─────────────
    function test_UT018_SetBudget_RevertWhen_NotClientOrProvider() public {
        uint256 jid = _createJob();

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller not client or provider");
        vm.prank(stranger);
        escrow.setBudget(jid, 100);
    }

    // ── UT-019: 非 Open 状态（Funded）→ revert ───────────────────────
    function test_UT019_SetBudget_RevertWhen_NotOpen() public {
        uint256 jid = _createJobWithProvider();

        // Fund the job
        vm.startPrank(client);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(client);
        escrow.setBudget(jid, 200);
    }

    // ── UT-020: budget 设为 0 → 允许 ─────────────────────────────────
    function test_UT020_SetBudget_ZeroAllowed() public {
        uint256 jid = _createJob();

        vm.expectEmit(true, false, false, true);
        emit IERC8183.BudgetSet(jid, 0);

        vm.prank(client);
        escrow.setBudget(jid, 0);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.budget, 0, "budget should be 0");
    }

    // ── UT-021: 无 optParams + 带 optParams 版本均正确路由 ───────────
    function test_UT021_SetBudget_BothOverloadsRouteCorrectly() public {
        // Create job with hook
        vm.prank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator, expiredAt, "desc1", address(hook));

        // 2-param version
        bytes4 sel2 = bytes4(keccak256("setBudget(uint256,uint256)"));
        uint256 beforeBefore = hook.beforeCount();

        vm.prank(client);
        escrow.setBudget(jid1, 50);

        assertEq(escrow.getJob(jid1).budget, 50);
        assertEq(hook.lastSelector(), sel2);
        assertEq(hook.beforeCount(), beforeBefore + 1);

        // 3-param version (new job)
        vm.prank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator, expiredAt, "desc2", address(hook));
        bytes4 sel3 = bytes4(keccak256("setBudget(uint256,uint256,bytes)"));
        bytes memory optParams = hex"aabb";
        uint256 beforeBefore2 = hook.beforeCount();

        vm.prank(client);
        escrow.setBudget(jid2, 75, optParams);

        assertEq(escrow.getJob(jid2).budget, 75);
        assertEq(hook.lastSelector(), sel3);
        assertEq(hook.lastData(), optParams);
        assertEq(hook.beforeCount(), beforeBefore2 + 1);
    }
}
