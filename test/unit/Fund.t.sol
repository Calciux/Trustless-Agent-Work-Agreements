// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockHook} from "../mocks/MockHook.sol";

// @title FundTest — UT-022 ~ UT-029
contract FundTest is Test {
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

    // @dev Helper: create job, set provider, set budget (still Open, ready to fund)
    function _setupJobReadyToFund(uint256 budgetAmt) internal returns (uint256) {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        token.mint(client, budgetAmt);
        token.approve(address(escrow), budgetAmt);
        vm.stopPrank();
        return jid;
    }

    // ── UT-022: Happy Path：Client 注资 → Open→Funded ────────────────
    function test_UT022_Fund_HappyPath_OpenToFunded() public {
        uint256 jid = _setupJobReadyToFund(100);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobFunded(jid, client, 100);

        vm.prank(client);
        escrow.fund(jid, 100);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(uint256(job.status), uint256(IERC8183.Status.Funded), "status should be Funded");
        assertEq(token.balanceOf(address(escrow)), 100, "escrow balance");
        assertEq(token.balanceOf(client), 0, "client balance should be 0");
    }

    // ── UT-023: expectedBudget ≠ job.budget → revert ─────────────────
    function test_UT023_Fund_RevertWhen_BudgetMismatch() public {
        uint256 jid = _setupJobReadyToFund(100);

        vm.expectRevert("ERC8183: budget mismatch");
        vm.prank(client);
        escrow.fund(jid, 99);

        // Status should remain Open
        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Open));
    }

    // ── UT-024: budget 未设置（=0）→ revert ──────────────────────────
    function test_UT024_Fund_RevertWhen_BudgetNotSet() public {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        // budget not set (remains 0)
        vm.stopPrank();

        vm.expectRevert("ERC8183: budget not set");
        vm.prank(client);
        escrow.fund(jid, 0);
    }

    // ── UT-025: provider 未设置 → revert ─────────────────────────────
    function test_UT025_Fund_RevertWhen_ProviderNotSet() public {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setBudget(jid, 100);
        // provider not set (remains 0)
        vm.stopPrank();

        vm.expectRevert("ERC8183: provider not set");
        vm.prank(client);
        escrow.fund(jid, 100);
    }

    // ── UT-026: 非 Client 调用 → revert ──────────────────────────────
    function test_UT026_Fund_RevertWhen_NotClient() public {
        uint256 jid = _setupJobReadyToFund(100);

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller is not client");
        vm.prank(stranger);
        escrow.fund(jid, 100);
    }

    // ── UT-027: 非 Open 状态（已 Funded）→ revert ────────────────────
    function test_UT027_Fund_RevertWhen_NotOpen() public {
        uint256 jid = _setupJobReadyToFund(100);

        vm.prank(client);
        escrow.fund(jid, 100);

        // Second fund attempt
        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(client);
        escrow.fund(jid, 100);
    }

    // ── UT-028: transferFrom 失败（余额不足）→ revert ────────────────
    function test_UT028_Fund_RevertWhen_TransferFromFails() public {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 1000);
        token.mint(client, 500); // insufficient
        token.approve(address(escrow), 1000);
        vm.stopPrank();

        // MockERC20.transferFrom uses require (not return false), so the actual
        // revert comes from MockERC20's "insufficient balance" before the
        // escrow's require(transferFrom(...), "ERC8183: transferFrom failed") is reached.
        vm.expectRevert("insufficient balance");
        vm.prank(client);
        escrow.fund(jid, 1000);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Open));
    }

    // ── UT-029: 无 optParams + 带 optParams 版本均正确路由 ────────────
    function test_UT029_Fund_BothOverloadsRouteCorrectly() public {
        // 2-param version
        vm.prank(client);
        uint256 jid1 = escrow.createJob(address(0), evaluator, expiredAt, "desc1", address(hook));
        vm.startPrank(client);
        escrow.setProvider(jid1, provider);
        escrow.setBudget(jid1, 50);
        token.mint(client, 50);
        token.approve(address(escrow), 50);
        vm.stopPrank();

        bytes4 sel2 = bytes4(keccak256("fund(uint256,uint256)"));

        vm.prank(client);
        escrow.fund(jid1, 50);
        assertEq(uint256(escrow.getStatus(jid1)), uint256(IERC8183.Status.Funded));
        assertEq(hook.lastSelector(), sel2);

        // 3-param version
        vm.prank(client);
        uint256 jid2 = escrow.createJob(address(0), evaluator, expiredAt, "desc2", address(hook));
        vm.startPrank(client);
        escrow.setProvider(jid2, provider);
        escrow.setBudget(jid2, 75);
        token.mint(client, 75);
        token.approve(address(escrow), 75);
        vm.stopPrank();

        bytes4 sel3 = bytes4(keccak256("fund(uint256,uint256,bytes)"));
        bytes memory optParams = hex"ccdd";

        vm.prank(client);
        escrow.fund(jid2, 75, optParams);
        assertEq(uint256(escrow.getStatus(jid2)), uint256(IERC8183.Status.Funded));
        assertEq(hook.lastSelector(), sel3);
        assertEq(hook.lastData(), optParams);
    }
}
