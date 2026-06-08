// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockHook} from "../mocks/MockHook.sol";

// @title CreateJobTest — UT-004 ~ UT-008
contract CreateJobTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);
    }

    // ── UT-004: 正常创建（provider=0, hook=0） ───────────────────────
    function test_UT004_CreateJob_WithZeroProviderAndHook() public {
        address client = makeAddr("client");
        address evaluator = makeAddr("evaluator");
        uint256 expiredAt = block.timestamp + 7 days;

        vm.expectEmit(true, true, true, true);
        emit IERC8183.JobCreated(1, client, address(0), evaluator, expiredAt);

        vm.prank(client);
        uint256 jobId = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));

        assertEq(jobId, 1, "jobId should be 1");
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client, "client mismatch");
        assertEq(job.provider, address(0), "provider should be 0");
        assertEq(job.evaluator, evaluator, "evaluator mismatch");
        assertEq(job.budget, 0, "budget should be 0");
        assertEq(job.expiredAt, expiredAt, "expiredAt mismatch");
        assertEq(uint256(job.status), uint256(IERC8183.Status.Open), "status should be Open");
        assertEq(job.hook, address(0), "hook should be 0");
    }

    // ── UT-005: evaluator=address(0) → revert ───────────────────────
    function test_UT005_RevertWhen_EvaluatorIsZeroAddress() public {
        vm.expectRevert("ERC8183: evaluator is zero address");
        escrow.createJob(address(0), address(0), block.timestamp + 1, "desc", address(0));
    }

    // ── UT-006: expiredAt ≤ block.timestamp → revert ───────────────
    function test_UT006_RevertWhen_ExpiredAtNotInFuture() public {
        address evaluator = makeAddr("evaluator");

        // expiredAt == block.timestamp
        vm.expectRevert("ERC8183: expiredAt too soon");
        escrow.createJob(address(0), evaluator, block.timestamp, "desc", address(0));

        // expiredAt == block.timestamp - 1
        vm.expectRevert("ERC8183: expiredAt too soon");
        escrow.createJob(address(0), evaluator, block.timestamp - 1, "desc", address(0));
    }

    // ── UT-007: provider≠0 且 hook≠0 时所有字段正确 ─────────────────
    function test_UT007_CreateJob_WithProviderAndHook() public {
        address client = makeAddr("client");
        address provider = makeAddr("provider");
        address evaluator = makeAddr("evaluator");
        MockHook hookContract = new MockHook();
        address hook = address(hookContract);
        uint256 expiredAt = block.timestamp + 30 days;

        // Whitelist the hook address so createJob succeeds
        escrow.setHookWhitelist(hook, true);

        vm.expectEmit(true, true, true, true);
        emit IERC8183.JobCreated(1, client, provider, evaluator, expiredAt);

        vm.prank(client);
        uint256 jobId = escrow.createJob(provider, evaluator, expiredAt, "desc", hook);

        assertEq(jobId, 1);
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client);
        assertEq(job.provider, provider, "provider should be non-zero");
        assertEq(job.evaluator, evaluator, "evaluator mismatch");
        assertEq(job.budget, 0, "budget should be 0");
        assertEq(job.expiredAt, expiredAt, "expiredAt mismatch");
        assertEq(uint256(job.status), uint256(IERC8183.Status.Open), "status should be Open");
        assertEq(job.hook, hook, "hook should be non-zero");
    }

    // ── UT-008: jobId 连续自增（1→2→3） ────────────────────────────
    function test_UT008_CreateJob_JobIdAutoIncrement() public {
        address evaluator = makeAddr("evaluator");
        uint256 expiredAt = block.timestamp + 7 days;

        assertEq(escrow.jobCount(), 0, "initial jobCount should be 0");

        uint256 id1 = escrow.createJob(address(0), evaluator, expiredAt, "job1", address(0));
        assertEq(id1, 1);
        assertEq(escrow.jobCount(), 1);

        uint256 id2 = escrow.createJob(address(0), evaluator, expiredAt, "job2", address(0));
        assertEq(id2, 2);
        assertEq(escrow.jobCount(), 2);

        uint256 id3 = escrow.createJob(address(0), evaluator, expiredAt, "job3", address(0));
        assertEq(id3, 3);
        assertEq(escrow.jobCount(), 3);
    }
}
