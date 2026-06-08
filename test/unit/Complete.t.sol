// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title CompleteTest — UT-035 ~ UT-043
contract CompleteTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    address public client;
    address public provider;
    address public evaluator;
    uint256 public expiredAt;

    function setUp() public {
        token = new MockERC20();
        // Default: treasury=address(0), feeBps=0 (no fees)
        escrow = new ERC8183Escrow(address(token), address(0), 0);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: create + fund + submit → Submitted
    function _setupSubmittedJob(uint256 budgetAmt) internal returns (uint256) {
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, budgetAmt);
        token.mint(client, budgetAmt);
        token.approve(address(escrow), budgetAmt);
        escrow.fund(jid, budgetAmt);
        vm.stopPrank();

        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
        return jid;
    }

    // ── UT-035: Evaluator complete → Submitted→Completed, no fees ─────
    function test_UT035_Complete_HappyPath_SubmittedToCompleted() public {
        uint256 jid = _setupSubmittedJob(1000);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.JobCompleted(jid, evaluator, bytes32(0));
        vm.expectEmit(true, true, false, true);
        emit IERC8183.PaymentReleased(jid, provider, 1000);

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(uint256(escrow.getStatus(jid)), uint256(IERC8183.Status.Completed));
        assertEq(token.balanceOf(provider), 1000, "provider should receive 1000");
        assertEq(token.balanceOf(address(escrow)), 0, "escrow should be zero");
    }

    // ── UT-036: treasury=address(0) 时 → Provider 收全额 ──────────────
    function test_UT036_Complete_NoTreasury_ProviderGetsFull() public {
        // Deploy with treasury=0, but set feeBps > 0
        escrow.setFeeBps(500);
        uint256 jid = _setupSubmittedJob(1000);

        uint256 providerBefore = token.balanceOf(provider);

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(token.balanceOf(provider) - providerBefore, 1000, "provider should get full 1000");
    }

    // ── UT-037: feeBps=0 时 → Provider 收全额 ────────────────────────
    function test_UT037_Complete_ZeroFeeBps_ProviderGetsFull() public {
        address treasuryAddr = makeAddr("treasury");
        escrow.setTreasury(treasuryAddr);
        // feeBps is already 0 from constructor
        uint256 jid = _setupSubmittedJob(1000);

        uint256 providerBefore = token.balanceOf(provider);

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(token.balanceOf(provider) - providerBefore, 1000, "provider should get full 1000");
        assertEq(token.balanceOf(treasuryAddr), 0, "treasury should get 0");
    }

    // ── UT-038: 有手续费时 → Provider 收款 = budget - fee ─────────────
    function test_UT038_Complete_WithFees_CorrectSplit() public {
        address treasuryAddr = makeAddr("treasury");
        escrow.setTreasury(treasuryAddr);
        escrow.setFeeBps(250); // 2.5%
        uint256 jid = _setupSubmittedJob(10000);

        uint256 providerBefore = token.balanceOf(provider);
        uint256 treasuryBefore = token.balanceOf(treasuryAddr);

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        // fee = 10000 * 250 / 10000 = 250, payAmount = 9750
        assertEq(token.balanceOf(provider) - providerBefore, 9750, "provider should get 9750");
        assertEq(token.balanceOf(treasuryAddr) - treasuryBefore, 250, "treasury should get 250");
    }

    // ── UT-039: feeBps=10000(100%) → Provider 收 0 ───────────────────
    function test_UT039_Complete_MaxFee_ProviderGetsZero() public {
        address treasuryAddr = makeAddr("treasury");
        escrow.setTreasury(treasuryAddr);
        escrow.setFeeBps(10000);
        uint256 jid = _setupSubmittedJob(1000);

        vm.expectEmit(true, true, false, true);
        emit IERC8183.PaymentReleased(jid, provider, 0);

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(token.balanceOf(provider), 0, "provider should get 0");
        assertEq(token.balanceOf(treasuryAddr), 1000, "treasury should get 1000");
    }

    // ── UT-040: treasury=0 且 feeBps>0 → 手续费逻辑不触发 ─────────────
    function test_UT040_Complete_TreasuryZero_FeeNotTriggered() public {
        // treasury is already 0 from constructor
        escrow.setFeeBps(500);
        uint256 jid = _setupSubmittedJob(1000);

        uint256 providerBefore = token.balanceOf(provider);

        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));

        assertEq(token.balanceOf(provider) - providerBefore, 1000);
    }

    // ── UT-041: 非 Submitted 状态（Funded）→ revert ───────────────────
    function test_UT041_Complete_RevertWhen_NotSubmitted() public {
        // Setup only to Funded (no submit)
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));
    }

    // ── UT-042: 非 Evaluator 调用 → revert ───────────────────────────
    function test_UT042_Complete_RevertWhen_NotEvaluator() public {
        uint256 jid = _setupSubmittedJob(100);

        address stranger = makeAddr("stranger");
        vm.expectRevert("ERC8183: caller is not evaluator");
        vm.prank(stranger);
        escrow.complete(jid, bytes32(0));
    }

    // ── UT-043: 无 optParams + 带 optParams 版本均正确路由 ────────────
    function test_UT043_Complete_BothOverloadsRouteCorrectly() public {
        // 2-param version
        uint256 jid1 = _setupSubmittedJob(50);
        vm.prank(evaluator);
        escrow.complete(jid1, bytes32(uint256(1)));
        assertEq(uint256(escrow.getStatus(jid1)), uint256(IERC8183.Status.Completed));

        // 3-param version (new job since complete is terminal)
        uint256 jid2 = _setupSubmittedJob(75);
        bytes memory optParams = hex"aabbcc";
        vm.prank(evaluator);
        escrow.complete(jid2, bytes32(uint256(2)), optParams);
        assertEq(uint256(escrow.getStatus(jid2)), uint256(IERC8183.Status.Completed));
    }
}
