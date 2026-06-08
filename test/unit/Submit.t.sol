// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title SubmitTest — UT-030 ~ UT-034
contract SubmitTest is Test {
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

    // @dev Helper: create + setProvider + setBudget + fund → Funded
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

    // ── UT-030: Provider 在 Funded 状态提交 → Funded→Submitted ────────
    function test_UT030_Submit_HappyPath_FundedToSubmitted() public {
        uint256 jid = _setupFundedJob(100);
        bytes32 deliverable = keccak256("work done");

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(jid, provider, deliverable);

        vm.prank(provider);
        escrow.submit(jid, deliverable);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(uint256(job.status), uint256(IERC8183.Status.Submitted), "status should be Submitted");
    }

    // ── UT-031: 非 Funded 状态（Open）→ revert ────────────────────────
    function test_UT031_Submit_RevertWhen_NotFunded() public {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        // Must set provider first so onlyProvider check passes;
        // the revert should come from onlyStatus(Funded), not onlyProvider.
        escrow.setProvider(jid, provider);
        vm.stopPrank();

        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
    }

    // ── UT-032: 非 Provider 调用 → revert ─────────────────────────────
    function test_UT032_Submit_RevertWhen_NotProvider() public {
        uint256 jid = _setupFundedJob(100);

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller is not provider");
        vm.prank(stranger);
        escrow.submit(jid, bytes32(0));
    }

    // ── UT-033: deliverable=bytes32(0) 应允许 ─────────────────────────
    function test_UT033_Submit_ZeroDeliverableAllowed() public {
        uint256 jid = _setupFundedJob(100);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobSubmitted(jid, provider, bytes32(0));

        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Submitted));
    }

    // ── UT-034: 无 optParams + 带 optParams 版本均正确路由 ────────────
    function test_UT034_Submit_BothOverloadsRouteCorrectly() public {
        // 2-param version
        uint256 jid1 = _setupFundedJob(50);
        vm.prank(provider);
        escrow.submit(jid1, bytes32(uint256(1)));
        assertEq(uint256(escrow.getStatus(jid1)), uint256(IERC8183.Status.Submitted));

        // 3-param version
        uint256 jid2 = _setupFundedJob(75);
        bytes memory optParams = hex"eeff";
        vm.prank(provider);
        escrow.submit(jid2, bytes32(uint256(2)), optParams);
        assertEq(uint256(escrow.getStatus(jid2)), uint256(IERC8183.Status.Submitted));
    }
}
