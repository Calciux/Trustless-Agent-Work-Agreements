// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title QueryFunctionsTest — UT-060 ~ UT-067
contract QueryFunctionsTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);
    }

    // ── UT-060: getJob 存在时返回完整 Job struct ────────────────────
    function test_UT060_GetJob_ReturnsFullStruct() public {
        address client = makeAddr("client");
        address evaluator = makeAddr("evaluator");
        uint256 expiredAt = block.timestamp + 7 days;

        vm.prank(client);
        escrow.createJob(address(0), evaluator, expiredAt, "test desc", address(0));

        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client);
        assertEq(job.provider, address(0));
        assertEq(job.evaluator, evaluator);
        assertEq(job.description, "test desc");
        assertEq(job.budget, 0);
        assertEq(job.expiredAt, expiredAt);
        assertEq(uint256(job.status), uint256(IERC8183.Status.Open));
        assertEq(job.hook, address(0));
    }

    // ── UT-061: getJob(0) → revert ──────────────────────────────────
    function test_UT061_GetJob_RevertWhen_JobIdZero() public {
        vm.expectRevert("ERC8183: job not found");
        escrow.getJob(0);
    }

    // ── UT-062: getJob(jobId > jobCount) → revert ───────────────────
    function test_UT062_GetJob_RevertWhen_JobIdOutOfRange() public {
        // 999 > jobCount(=0)
        vm.expectRevert("ERC8183: job not found");
        escrow.getJob(999);
    }

    // ── UT-063: getStatus 返回正确状态枚举值 ─────────────────────────
    function test_UT063_GetStatus_ReturnsCorrectEnum() public {
        address client = makeAddr("client");
        address evaluator = makeAddr("evaluator");
        address provider = makeAddr("provider");
        uint256 expiredAt = block.timestamp + 7 days;

        // Create job (Open)
        vm.prank(client);
        escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open), "should be Open");

        // Set provider + budget + fund to get Funded
        vm.startPrank(client);
        escrow.setProvider(1, provider);
        escrow.setBudget(1, 100);
        token.mint(client, 100);
        token.approve(address(escrow), 100);
        escrow.fund(1, 100);
        vm.stopPrank();

        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Funded), "should be Funded");
    }

    // ── UT-064: getStatus(0) → revert ───────────────────────────────
    function test_UT064_GetStatus_RevertWhen_JobIdZero() public {
        vm.expectRevert("ERC8183: job not found");
        escrow.getStatus(0);
    }

    // ── UT-065: jobCount 部署后为 0 ─────────────────────────────────
    function test_UT065_JobCount_InitiallyZero() public {
        assertEq(escrow.jobCount(), 0);
    }

    // ── UT-066: jobCount createJob 后递增 ───────────────────────────
    function test_UT066_JobCount_IncrementsAfterCreateJob() public {
        address evaluator = makeAddr("evaluator");
        uint256 expiredAt = block.timestamp + 7 days;

        assertEq(escrow.jobCount(), 0);
        escrow.createJob(address(0), evaluator, expiredAt, "j1", address(0));
        assertEq(escrow.jobCount(), 1);
        escrow.createJob(address(0), evaluator, expiredAt, "j2", address(0));
        assertEq(escrow.jobCount(), 2);
    }

    // ── UT-067: paymentToken 返回部署时传入的代币地址 ────────────────
    function test_UT067_PaymentToken_ReturnsCorrectAddress() public {
        assertEq(escrow.paymentToken(), address(token));
    }
}
