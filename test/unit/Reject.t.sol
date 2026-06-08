// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title RejectTest — UT-044 ~ UT-051
contract RejectTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    address public client;
    address public provider;
    address public evaluator;
    uint256 public expiredAt;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: create job (Open)
    function _createOpenJob() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
    }

    // @dev Helper: setup to Funded
    function _setupFundedJob(uint256 budgetAmt) internal returns (uint256) {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        token.mint(client, budgetAmt);
        token.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();
        return jid;
    }

    // @dev Helper: setup to Submitted
    function _setupSubmittedJob(uint256 budgetAmt) internal returns (uint256) {
        uint256 jid = _setupFundedJob(budgetAmt);
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
        return jid;
    }

    // ── UT-044: Open 状态 + Client 调用 → Open→Rejected（无退款） ─────
    function test_UT044_Reject_OpenByClient_NoRefund() public {
        uint256 jid = _createOpenJob();

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(jid, client, bytes32(uint256(1)));

        // "不发射 Refunded" — we just verify status and balances
        vm.prank(client);
        escrow.reject(jid, bytes32(uint256(1)));

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Rejected));
        // No funds were escrowed, so no refund
        assertEq(token.balanceOf(client), 0);
    }

    // ── UT-045: Funded 状态 + Evaluator 调用 → Funded→Rejected + 退款 ─
    function test_UT045_Reject_FundedByEvaluator_RefundsClient() public {
        uint256 jid = _setupFundedJob(1000);
        bytes32 reason = keccak256("not good");

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(jid, evaluator, reason);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(jid, client, 1000);

        vm.prank(evaluator);
        escrow.reject(jid, reason);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Rejected));
        assertEq(token.balanceOf(client), 1000, "client should be refunded 1000");
        assertEq(token.balanceOf(address(escrow)), 0, "escrow should be 0");
    }

    // ── UT-046: Submitted + Evaluator 调用 → Submitted→Rejected + 退款 ─
    function test_UT046_Reject_SubmittedByEvaluator_RefundsClient() public {
        uint256 jid = _setupSubmittedJob(1000);
        bytes32 reason = keccak256("bad work");

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobRejected(jid, evaluator, reason);
        vm.expectEmit(true, true, false, true);
        emit IERC8183.Refunded(jid, client, 1000);

        vm.prank(evaluator);
        escrow.reject(jid, reason);

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Rejected));
        assertEq(token.balanceOf(client), 1000, "client should be refunded 1000");
    }

    // ── UT-047: Open + 非 Client → revert ─────────────────────────────
    function test_UT047_Reject_RevertWhen_OpenNotClient() public {
        uint256 jid = _createOpenJob();

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller not client");
        vm.prank(stranger);
        escrow.reject(jid, bytes32(0));
    }

    // ── UT-048: Funded + 非 Evaluator → revert ────────────────────────
    function test_UT048_Reject_RevertWhen_FundedNotEvaluator() public {
        uint256 jid = _setupFundedJob(100);

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller not evaluator");
        vm.prank(stranger);
        escrow.reject(jid, bytes32(0));
    }

    // ── UT-049: Submitted + 非 Evaluator → revert ─────────────────────
    function test_UT049_Reject_RevertWhen_SubmittedNotEvaluator() public {
        uint256 jid = _setupSubmittedJob(100);

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller not evaluator");
        vm.prank(stranger);
        escrow.reject(jid, bytes32(0));
    }

    // ── UT-050: 终态（Completed）调用 → revert ─────────────────────────
    function test_UT050_Reject_RevertWhen_TerminalState() public {
        uint256 jid = _setupSubmittedJob(100);
        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0)); // Now Completed (terminal)

        vm.expectRevert("ERC8183: invalid job status for reject");
        vm.prank(evaluator);
        escrow.reject(jid, bytes32(0));
    }

    // ── UT-051: 无 optParams + 带 optParams 版本均正确路由 ────────────
    function test_UT051_Reject_BothOverloadsRouteCorrectly() public {
        // 2-param version
        uint256 jid1 = _createOpenJob();
        vm.prank(client);
        escrow.reject(jid1, bytes32(uint256(1)));
        assertEq(uint256(escrow.getStatus(jid1)), uint256(IERC8183.Status.Rejected));

        // 3-param version
        uint256 jid2 = _createOpenJob();
        bytes memory optParams = hex"dead";
        vm.prank(client);
        escrow.reject(jid2, bytes32(uint256(2)), optParams);
        assertEq(uint256(escrow.getStatus(jid2)), uint256(IERC8183.Status.Rejected));
    }
}
