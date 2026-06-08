// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockHook} from "../mocks/MockHook.sol";

// @title SetProviderTest — UT-009 ~ UT-015
contract SetProviderTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;
    MockHook public hook;

    address public client;
    address public provider;
    address public evaluator;
    uint256 public expiredAt;
    uint256 public jobId;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);
        hook = new MockHook();
        escrow.setHookWhitelist(address(hook), true);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: create a job with provider=0 (so setProvider can be called)
    function _createJob() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
    }

    // @dev Helper: create a job with a hook (for optParams tests)
    function _createJobWithHook() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(hook));
    }

    // ── UT-009: Client 在 Open 状态首次设置 provider → 成功 ──────────
    function test_UT009_SetProvider_FirstTimeSucceeds() public {
        uint256 jid = _createJob();

        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(jid, provider);

        vm.prank(client);
        escrow.setProvider(jid, provider);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.provider, provider, "provider should be set");
    }

    // ── UT-010: provider=address(0) → revert ────────────────────────
    function test_UT010_SetProvider_RevertWhen_ProviderIsZero() public {
        uint256 jid = _createJob();

        vm.expectRevert("ERC8183: provider is zero address");
        vm.prank(client);
        escrow.setProvider(jid, address(0));
    }

    // ── UT-011: provider 已被设置后再次设置 → revert ─────────────────
    function test_UT011_SetProvider_RevertWhen_AlreadySet() public {
        uint256 jid = _createJob();

        vm.prank(client);
        escrow.setProvider(jid, provider);

        address anotherProvider = makeAddr("anotherProvider");
        vm.expectRevert("ERC8183: provider already set");
        vm.prank(client);
        escrow.setProvider(jid, anotherProvider);
    }

    // ── UT-012: 非 Open 状态（Funded）调用 → revert ──────────────────
    function test_UT012_SetProvider_RevertWhen_NotOpen() public {
        uint256 jid = _createJob();

        // Move to Funded state
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(client);
        escrow.setProvider(jid, makeAddr("newProvider"));
    }

    // ── UT-013: 非 Client 调用 → revert ──────────────────────────────
    function test_UT013_SetProvider_RevertWhen_NotClient() public {
        uint256 jid = _createJob();

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller is not client or operator");
        vm.prank(stranger);
        escrow.setProvider(jid, provider);
    }

    // ── UT-014: 无 optParams 版本正常路由到 _setProvider ─────────────
    function test_UT014_SetProvider_WithoutOptParams() public {
        uint256 jid = _createJob();

        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(jid, provider);

        // Use 2-param version
        vm.prank(client);
        escrow.setProvider(jid, provider);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.provider, provider);
    }

    // ── UT-015: 带 optParams 版本正常路由 + optParams 透传给 Hook ────
    function test_UT015_SetProvider_WithOptParams_PassedToHook() public {
        uint256 jid = _createJobWithHook();
        bytes memory optParams = hex"deadbeefcafe";

        // Compute expected selector for 3-param version
        bytes4 expectedSelector = bytes4(keccak256("setProvider(uint256,address,bytes)"));

        // createJob calls afterAction once — record baseline
        uint256 bcBefore = hook.beforeCount();
        uint256 acBefore = hook.afterCount();

        vm.prank(client);
        escrow.setProvider(jid, provider, optParams);

        // Verify core behavior
        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.provider, provider);

        // Verify Hook received correct selector and data
        assertEq(hook.lastSelector(), expectedSelector, "hook selector should be ext version");
        assertEq(hook.lastData(), abi.encode(client, provider, optParams), "hook data should match optParams");
        assertEq(hook.beforeCount(), bcBefore + 1, "beforeAction should be called once");
        assertEq(hook.afterCount(), acBefore + 1, "afterAction should be called once");
    }
}
