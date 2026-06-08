// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MaliciousReenterHook} from "../mocks/MaliciousReenterHook.sol";
import {SubmitOnlyReenterHook} from "../mocks/SubmitOnlyReenterHook.sol";
import {CompleteOnlyReenterHook} from "../mocks/CompleteOnlyReenterHook.sol";
import {RejectOnlyReenterHook} from "../mocks/RejectOnlyReenterHook.sol";
import {FundOnlyReenterHook} from "../mocks/FundOnlyReenterHook.sol";

// @title ReentrancyGuardTest — UT-089 ~ UT-095
contract ReentrancyGuardTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    address public client;
    address public provider;
    address public evaluator;
    address public reenterProvider;
    uint256 public expiredAt;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        reenterProvider = makeAddr("reenterProvider");
        expiredAt = block.timestamp + 7 days;
    }

    // Helper: deploy MaliciousReenterHook and create a job with it
    function _setupJobWithMaliciousHook() internal returns (uint256 jid, MaliciousReenterHook mHook) {
        mHook = new MaliciousReenterHook(address(escrow), reenterProvider);
        vm.prank(client);
        jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(mHook));
    }

    // @dev Helper: setup job to be ready for fund with malicious hook
    function _setupFundedWithMaliciousHook() internal returns (uint256 jid, MaliciousReenterHook mHook) {
        (jid, mHook) = _setupJobWithMaliciousHook();
        vm.startPrank(client);
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        vm.stopPrank();
    }

    // ── UT-089: setProvider 防重入 ────────────────────────────────────
    function test_UT089_Reentrancy_SetProvider() public {
        (uint256 jid, MaliciousReenterHook mHook) = _setupJobWithMaliciousHook();

        vm.expectRevert("ERC8183: reentrant call");
        vm.prank(client);
        escrow.setProvider(jid, provider);
    }

    // ── UT-090: setBudget 防重入 ──────────────────────────────────────
    function test_UT090_Reentrancy_SetBudget() public {
        (uint256 jid, MaliciousReenterHook mHook) = _setupJobWithMaliciousHook();

        vm.expectRevert("ERC8183: reentrant call");
        vm.prank(client);
        escrow.setBudget(jid, 100);
    }

    // ── UT-091: fund 防重入 ───────────────────────────────────────────
    // @dev Uses FundOnlyReenterHook because the generic MaliciousReenterHook
    // would also reenter on setProvider()/setBudget() during setup, preventing
    // the job from reaching Funded state.
    function test_UT091_Reentrancy_Fund() public {
        FundOnlyReenterHook fundHook = new FundOnlyReenterHook(address(escrow));

        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(fundHook));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        // setup completes without triggering reentrancy — the hook only
        // reenters on fund selector, which fires in afterAction
        vm.stopPrank();

        vm.expectRevert("ERC8183: reentrant call");
        vm.prank(client);
        escrow.fund(jid, 100);
    }

    // ── UT-092: submit 防重入 ─────────────────────────────────────────
    // @dev Uses SubmitOnlyReenterHook because the generic MaliciousReenterHook
    // would also reenter on fund(), preventing the job from reaching Funded state.
    function test_UT092_Reentrancy_Submit() public {
        SubmitOnlyReenterHook submitHook = new SubmitOnlyReenterHook(address(escrow), reenterProvider);

        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(submitHook));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100); // fund succeeds — hook only reenters on submit
        vm.stopPrank();

        vm.expectRevert("ERC8183: reentrant call");
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));
    }

    // ── UT-093: complete 防重入 ────────────────────────────────────────
    // @dev Uses CompleteOnlyReenterHook for the same reason as UT-092.
    function test_UT093_Reentrancy_Complete() public {
        CompleteOnlyReenterHook completeHook = new CompleteOnlyReenterHook(address(escrow));

        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(completeHook));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();
        vm.prank(provider);
        escrow.submit(jid, bytes32(0));

        vm.expectRevert("ERC8183: reentrant call");
        vm.prank(evaluator);
        escrow.complete(jid, bytes32(0));
    }

    // ── UT-094: reject 防重入 ─────────────────────────────────────────
    // @dev Uses RejectOnlyReenterHook for the same reason as UT-092.
    function test_UT094_Reentrancy_Reject() public {
        RejectOnlyReenterHook rejectHook = new RejectOnlyReenterHook(address(escrow));

        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(rejectHook));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();

        // Evaluator rejects from Funded state
        vm.expectRevert("ERC8183: reentrant call");
        vm.prank(evaluator);
        escrow.reject(jid, bytes32(0));
    }

    // ── UT-095: claimRefund 防重入 ─────────────────────────────────────
    function test_UT095_Reentrancy_ClaimRefund() public {
        // claimRefund does NOT call any Hook, so there is no natural
        // reentrancy path. The receive-fallback approach (suggested by the
        // checklist) requires a token with transfer callbacks, which
        // MockERC20 does not have. We therefore use vm.store to
        // artificially set _locked=true and verify the nonReentrant
        // modifier catches it.
        //
        // Storage layout (verified against ERC8183Escrow.sol):
        //   slot 0: treasury   (address, 20 bytes)
        //   slot 1: feeBps     (uint256)
        //   slot 2: _jobCounter (uint256)
        //   slot 3: _jobs      (mapping — base slot)
        //   slot 4: _locked    (bool)
        //
        // immutables (owner, _paymentToken) and constants (MAX_FEE_BPS)
        // are not in storage and do not affect slot numbering.

        // Setup: create + fund a job, warp past expiry
        vm.startPrank(client);
        uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
        escrow.setProvider(jid, provider);
        escrow.setBudget(jid, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(jid, 100);
        vm.stopPrank();
        vm.warp(expiredAt + 1);

        // Artificially set _locked = true (slot 4)
        vm.store(address(escrow), bytes32(uint256(4)), bytes32(uint256(1)));

        vm.expectRevert("ERC8183: reentrant call");
        escrow.claimRefund(jid);
    }
}
