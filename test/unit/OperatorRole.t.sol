// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// @title OperatorRoleTest — UT-113 ~ UT-119 (operator role)
contract OperatorRoleTest is Test {
    MockERC20 public token;
    ERC8183Escrow public escrow;

    address public client;
    address public provider;
    address public evaluator;
    address public operatorAddr;
    uint256 public expiredAt;

    function setUp() public {
        token = new MockERC20();
        escrow = new ERC8183Escrow(address(token), address(0), 0);

        client = makeAddr("client");
        provider = makeAddr("provider");
        evaluator = makeAddr("evaluator");
        operatorAddr = makeAddr("operator");
        expiredAt = block.timestamp + 7 days;
    }

    // @dev Helper: create job in Open state (provider=0, no operator)
    function _createOpenJob() internal returns (uint256) {
        vm.prank(client);
        return escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
    }

    // @dev Helper: create job and set operator
    function _createJobWithOperator() internal returns (uint256) {
        uint256 jid = _createOpenJob();
        vm.prank(client);
        escrow.setOperator(jid, operatorAddr);
        return jid;
    }

    // @dev Helper: setup job to Funded state
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

    // ═══════════════════════════════════════════════════════════════
    // UT-113: setOperator — Client 设置 operator → 事件 + storage 更新
    // ═══════════════════════════════════════════════════════════════
    function test_UT113_SetOperator_ClientSetsOperator() public {
        uint256 jid = _createOpenJob();

        vm.expectEmit(true, true, false, false);
        emit IERC8183.OperatorSet(jid, operatorAddr);

        vm.prank(client);
        escrow.setOperator(jid, operatorAddr);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.operator, operatorAddr, "operator should be set");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-114: setProvider — operator 调用 setProvider → 成功
    // ═══════════════════════════════════════════════════════════════
    function test_UT114_SetProvider_OperatorCanSetProvider() public {
        uint256 jid = _createJobWithOperator();

        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(jid, provider);

        vm.prank(operatorAddr);
        escrow.setProvider(jid, provider);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.provider, provider, "provider should be set by operator");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-115: setOperator — 非 Client 调用 → revert
    // ═══════════════════════════════════════════════════════════════
    function test_UT115_SetOperator_RevertWhen_NotClient() public {
        uint256 jid = _createOpenJob();

        address randomAddr = makeAddr("randomAddr");
        vm.expectRevert("ERC8183: caller is not client");
        vm.prank(randomAddr);
        escrow.setOperator(jid, operatorAddr);
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-116: setProvider — 非 operator 且非 client 的随机地址 → revert
    // ═══════════════════════════════════════════════════════════════
    function test_UT116_SetProvider_RevertWhen_NotClientOrOperator() public {
        uint256 jid = _createJobWithOperator();

        address randomAddr = makeAddr("randomAddr");
        vm.expectRevert("ERC8183: caller is not client or operator");
        vm.prank(randomAddr);
        escrow.setProvider(jid, provider);
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-117: setOperator + setProvider — 清除 operator 后原 operator 不能再调 setProvider
    // ═══════════════════════════════════════════════════════════════
    function test_UT117_SetOperator_ClearOperatorRevokesAccess() public {
        uint256 jid = _createJobWithOperator();

        // Clear operator (set to address(0))
        vm.prank(client);
        escrow.setOperator(jid, address(0));

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.operator, address(0), "operator should be cleared");

        // Former operator can no longer setProvider
        vm.expectRevert("ERC8183: caller is not client or operator");
        vm.prank(operatorAddr);
        escrow.setProvider(jid, provider);

        // Client can still setProvider
        vm.prank(client);
        escrow.setProvider(jid, provider);

        job = escrow.getJob(jid);
        assertEq(job.provider, provider, "client should still be able to set provider");
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-118: setOperator — 非 Open 状态 (Funded) → revert
    // ═══════════════════════════════════════════════════════════════
    function test_UT118_SetOperator_RevertWhen_NotOpen() public {
        uint256 jid = _setupFundedJob(100);

        vm.expectRevert("ERC8183: invalid job status");
        vm.prank(client);
        escrow.setOperator(jid, operatorAddr);
    }

    // ═══════════════════════════════════════════════════════════════
    // UT-119: setProvider — operator 设置后 Client 仍可调用 setProvider
    // ═══════════════════════════════════════════════════════════════
    function test_UT119_SetProvider_ClientCanStillSetProviderAfterOperator() public {
        uint256 jid = _createJobWithOperator();

        // Client (not operator) sets provider
        vm.expectEmit(true, true, false, false);
        emit IERC8183.ProviderSet(jid, provider);

        vm.prank(client);
        escrow.setProvider(jid, provider);

        IERC8183.Job memory job = escrow.getJob(jid);
        assertEq(job.provider, provider, "provider should be set by client");
        assertEq(job.operator, operatorAddr, "operator should remain set");
    }
}
