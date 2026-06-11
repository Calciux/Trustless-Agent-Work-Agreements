// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {ERC8183Escrow} from "../../contracts/ERC8183Escrow.sol";
import {IERC8183} from "../../contracts/interfaces/IERC8183.sol";
import {BiddingHook} from "../../contracts/hooks/BiddingHook.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title BiddingHookIntegrationTest — BiddingHook + ERC8183Escrow 联调测试
contract BiddingHookIntegrationTest is Test {
    ERC8183Escrow escrow;
    BiddingHook hook;
    MockERC20 token;

    address client = makeAddr("client");
    address evaluator = makeAddr("evaluator");
    uint256 expiredAt;

    /// @notice setProvider(uint256,address,bytes) 的函数选择器
    bytes4 constant SEL_SETPROVIDER_EXT =
        bytes4(keccak256("setProvider(uint256,address,bytes)"));

    function setUp() public {
        token = new MockERC20();
        expiredAt = block.timestamp + 7 days;

        // 部署 Escrow (无手续费)
        escrow = new ERC8183Escrow(address(token), address(0), 0);

        // 部署 BiddingHook
        hook = new BiddingHook();

        // 将 BiddingHook 加入白名单
        escrow.setHookWhitelist(address(hook), true);
    }

    // ─────────────────────────────────────────────────────────
    // Internal helper: 对 (jobId, price) 生成 EIP-191 签名
    // ─────────────────────────────────────────────────────────
    function _signBid(
        uint256 jobId,
        uint256 price,
        uint256 privateKey
    ) internal returns (bytes memory sig) {
        bytes32 messageHash = keccak256(abi.encodePacked(jobId, price));
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        bytes32 r;
        bytes32 s;
        uint8 v;
        (v, r, s) = vm.sign(privateKey, ethSignedHash);
        sig = new bytes(65);
        assembly {
            mstore(add(sig, 32), r)
            mstore(add(sig, 64), s)
            mstore8(add(sig, 96), v)
        }
    }

    // ═════════════════════════════════════════════════════════
    // IT-BID-001: Happy Path — 竞价 + 签名验证 + bid 存储 + Escrow 状态
    // ═════════════════════════════════════════════════════════
    function test_IT_BID_001_HappyPath_SignedBid() public {
        uint256 winnerKey = 0xABCD;
        address winner = vm.addr(winnerKey);
        uint256 jobId;
        uint256 price = 100;

        // ── Step 1: Client 创建 Job（provider=0, hook=BiddingHook）──
        vm.prank(client);
        jobId = escrow.createJob(
            address(0),          // provider=0 表示开放竞价
            evaluator,
            expiredAt,
            "bidding job",
            address(hook)        // 绑定 BiddingHook
        );

        assertEq(jobId, 1);
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.client, client);
        assertEq(job.provider, address(0));
        assertEq(job.hook, address(hook));

        // ── Step 2: Winner 链下签名竞价 ──
        bytes memory sig = _signBid(jobId, price, winnerKey);

        // ── Step 3: Client 调用 setProvider(带签名 optParams) ──
        bytes memory optParams = abi.encode(sig, price);
        vm.prank(client);
        escrow.setProvider(jobId, winner, optParams);

        // ── 验证 Escrow 状态 ──
        assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open));
        job = escrow.getJob(1);
        assertEq(job.provider, winner, "escrow: provider should be winner");

        // ── 验证 BiddingHook bids mapping ──
        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, winner, "hook: provider mismatch");
        assertEq(storedPrice, price, "hook: price mismatch");
    }

    // ═════════════════════════════════════════════════════════
    // IT-BID-002: 签名验证失败 → setProvider revert
    // ═════════════════════════════════════════════════════════
    function test_IT_BID_002_InvalidSignature_Reverts() public {
        uint256 winnerKey = 0xABCD;
        address winner = vm.addr(winnerKey);
        uint256 attackerKey = 0xBAD;
        // attackerKey ≠ winnerKey → signer ≠ provider
        uint256 jobId;
        uint256 price = 100;

        // ── 创建 Job ──
        vm.prank(client);
        jobId = escrow.createJob(
            address(0),
            evaluator,
            expiredAt,
            "bidding job",
            address(hook)
        );

        // ── 用 attacker 私钥签名，但 provider 填 winner ──
        bytes memory badSig = _signBid(jobId, price, attackerKey);
        bytes memory optParams = abi.encode(badSig, price);

        // ── setProvider 应 revert ──
        vm.expectRevert("BiddingHook: invalid signature");
        vm.prank(client);
        escrow.setProvider(jobId, winner, optParams);

        // ── 验证 Escrow 状态未变 ──
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.provider, address(0), "provider should still be zero");

        // ── 验证 Hook bids 未被写入 ──
        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, address(0), "hook: provider should be zero");
        assertEq(storedPrice, 0, "hook: price should be zero");
    }

    // ═════════════════════════════════════════════════════════
    // IT-BID-003: 无签名 setProvider 不经过 Hook → 成功
    // ═════════════════════════════════════════════════════════
    function test_IT_BID_003_NoOptParams_SetProviderSucceeds() public {
        address provider = makeAddr("provider");
        uint256 jobId;

        // ── 创建 Job（带 BiddingHook）──
        vm.prank(client);
        jobId = escrow.createJob(
            address(0),
            evaluator,
            expiredAt,
            "bidding job",
            address(hook)
        );

        assertEq(jobId, 1);

        // ── 直接 setProvider 不带 optParams ──
        //    这会走 SEL_SETPROVIDER 选择器，Hook 不拦截
        vm.prank(client);
        escrow.setProvider(jobId, provider);

        // ── 验证 Escrow 状态：provider 已更新 ──
        IERC8183.Job memory job = escrow.getJob(1);
        assertEq(job.provider, provider, "provider should be set");

        // ── 验证 Hook bids 未被写入（因为 Hook 不拦截无 optParams 版本）──
        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, address(0), "hook: provider should be zero");
        assertEq(storedPrice, 0, "hook: price should be zero");
    }
}
