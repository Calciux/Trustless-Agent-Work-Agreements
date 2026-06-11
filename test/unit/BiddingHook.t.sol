// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {BiddingHook} from "../../contracts/hooks/BiddingHook.sol";
import {IACPHook} from "../../contracts/interfaces/IACPHook.sol";
import {IERC165} from "../../contracts/interfaces/IERC165.sol";

/// @title BiddingHookTest — 14 unit tests for BiddingHook
/// @dev Pure unit tests, no Escrow dependency
contract BiddingHookTest is Test {
    BiddingHook public hook;

    /// @notice setProvider(uint256,address,bytes) 的函数选择器
    bytes4 internal constant SEL_SETPROVIDER_EXT =
        bytes4(keccak256("setProvider(uint256,address,bytes)"));

    /// @notice 非目标选择器（用于 selector 路由测试）
    bytes4 internal constant SEL_OTHER =
        bytes4(keccak256("fund(uint256,uint256)"));

    // ─────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────

    function setUp() public {
        hook = new BiddingHook();
    }

    // ─────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────

    /// @dev 对 (jobId, price) 生成 EIP-191 签名
    function _signBid(
        uint256 jobId,
        uint256 price,
        uint256 privateKey
    ) internal returns (bytes memory sig) {
        bytes32 messageHash = keccak256(abi.encodePacked(jobId, price));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
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

    /// @dev 构造 beforeAction 的 data 参数
    function _encodeData(
        address caller,
        address provider,
        bytes memory sig,
        uint256 price
    ) internal pure returns (bytes memory) {
        return abi.encode(caller, provider, abi.encode(sig, price));
    }

    /// @dev 对 (jobId, price) 签名并返回完整 data（caller 默认为 address(this)）
    function _signAndEncode(
        uint256 jobId,
        uint256 price,
        uint256 privateKey
    ) internal returns (address provider, bytes memory data) {
        provider = vm.addr(privateKey);
        bytes memory sig = _signBid(jobId, price, privateKey);
        data = _encodeData(address(this), provider, sig, price);
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-001: 有效签名 + bid 正确存储
    // ═════════════════════════════════════════════════════════
    function test_BID_001_ValidSignature_StoresBid() public {
        uint256 providerKey = 0xABCD;
        uint256 jobId = 1;
        uint256 price = 100;

        (address provider, bytes memory data) =
            _signAndEncode(jobId, price, providerKey);

        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);

        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, provider, "provider mismatch");
        assertEq(storedPrice, price, "price mismatch");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-002: 不同 jobId 竞价记录独立
    // ═════════════════════════════════════════════════════════
    function test_BID_002_DifferentJobIds_IndependentBids() public {
        uint256 keyA = 0xA000;
        uint256 keyB = 0xB000;
        address providerA = vm.addr(keyA);
        address providerB = vm.addr(keyB);

        uint256 jobIdA = 1;
        uint256 priceA = 100;
        uint256 jobIdB = 2;
        uint256 priceB = 200;

        bytes memory sigA = _signBid(jobIdA, priceA, keyA);
        bytes memory sigB = _signBid(jobIdB, priceB, keyB);
        bytes memory dataA = _encodeData(address(this), providerA, sigA, priceA);
        bytes memory dataB = _encodeData(address(this), providerB, sigB, priceB);

        hook.beforeAction(jobIdA, SEL_SETPROVIDER_EXT, dataA);
        hook.beforeAction(jobIdB, SEL_SETPROVIDER_EXT, dataB);

        (address pa, uint256 pra) = hook.bids(jobIdA);
        (address pb, uint256 prb) = hook.bids(jobIdB);

        assertEq(pa, providerA, "job 1 provider");
        assertEq(pra, priceA, "job 1 price");
        assertEq(pb, providerB, "job 2 provider");
        assertEq(prb, priceB, "job 2 price");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-003: selector 不匹配时静默返回
    // ═════════════════════════════════════════════════════════
    function test_BID_003_SelectorMismatch_SilentReturn() public {
        uint256 jobId = 1;

        // 使用非目标选择器调用，data 可以是任意无效格式
        bytes memory garbageData = hex"DEADBEEF";

        // 不应 revert
        hook.beforeAction(jobId, SEL_OTHER, garbageData);

        // bids 未被写入
        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, address(0), "provider should be zero");
        assertEq(storedPrice, 0, "price should be zero");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-004: 签名消息被篡改 (price 不匹配) → revert
    // ═════════════════════════════════════════════════════════
    function test_BID_004_TamperedPrice_Reverts() public {
        uint256 providerKey = 0xABCD;
        address provider = vm.addr(providerKey);
        uint256 jobId = 1;
        uint256 originalPrice = 100;
        uint256 tamperedPrice = 200;

        // 对 originalPrice 签名
        bytes memory sig = _signBid(jobId, originalPrice, providerKey);

        // 构造 data 时使用篡改后的 price
        bytes memory data = _encodeData(address(this), provider, sig, tamperedPrice);

        vm.expectRevert("BiddingHook: invalid signature");
        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-005: 签名消息被篡改 (jobId 不匹配) → revert
    // ═════════════════════════════════════════════════════════
    function test_BID_005_TamperedJobId_Reverts() public {
        uint256 providerKey = 0xABCD;
        address provider = vm.addr(providerKey);
        uint256 signedJobId = 1;
        uint256 usedJobId = 2;
        uint256 price = 100;

        // 对 jobId=1 签名
        bytes memory sig = _signBid(signedJobId, price, providerKey);

        // 构造 data 时传入 jobId=2（与签名不符）
        bytes memory data = _encodeData(address(this), provider, sig, price);

        vm.expectRevert("BiddingHook: invalid signature");
        hook.beforeAction(usedJobId, SEL_SETPROVIDER_EXT, data);
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-006: signer ≠ provider（用他人私钥签名）→ revert
    // ═════════════════════════════════════════════════════════
    function test_BID_006_SignerNotProvider_Reverts() public {
        uint256 attackerKey = 0xBAD;
        address attacker = vm.addr(attackerKey);
        address legitimateProvider = makeAddr("provider");
        uint256 jobId = 1;
        uint256 price = 100;

        // 用 attacker 私钥签名
        bytes memory sig = _signBid(jobId, price, attackerKey);

        // 但 data 中的 provider 填 legitimateProvider
        bytes memory data =
            _encodeData(address(this), legitimateProvider, sig, price);

        vm.expectRevert("BiddingHook: invalid signature");
        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-007: 签名长度错误（< 65 字节）→ revert
    // ═════════════════════════════════════════════════════════
    function test_BID_007_SignatureTooShort_Reverts() public {
        uint256 providerKey = 0xABCD;
        address provider = vm.addr(providerKey);
        uint256 jobId = 1;
        uint256 price = 100;

        // 构造仅 32 字节的短签名
        bytes memory shortSig = abi.encodePacked(bytes32(uint256(0x42)));

        bytes memory data = _encodeData(address(this), provider, shortSig, price);

        // assembly 读取越界 → ecrecover 返回 address(0) → signer ≠ provider
        vm.expectRevert("BiddingHook: invalid signature");
        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-008: 签名长度错误（> 65 字节）→ 行为记录
    // ═════════════════════════════════════════════════════════
    function test_BID_008_SignatureTooLong_Behavior() public {
        uint256 providerKey = 0xABCD;
        address provider = vm.addr(providerKey);
        uint256 jobId = 1;
        uint256 price = 100;

        // 生成有效签名（65 字节），然后追加 31 字节垃圾数据 → 96 字节
        bytes memory validSig = _signBid(jobId, price, providerKey);
        bytes memory longSig = abi.encodePacked(validSig, bytes31(0));
        // longSig 长度 = 65 + 31 = 96

        // assembly 只读取前 65 字节 → 签名有效 → 应成功存储
        bytes memory data = _encodeData(address(this), provider, longSig, price);

        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);

        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, provider, "long sig: provider should match");
        assertEq(storedPrice, price, "long sig: price should match");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-009: price = 0 的有效竞价
    // ═════════════════════════════════════════════════════════
    function test_BID_009_PriceZero_ValidBid() public {
        uint256 providerKey = 0xABCD;
        uint256 jobId = 1;
        uint256 price = 0;

        (address provider, bytes memory data) =
            _signAndEncode(jobId, price, providerKey);

        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);

        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, provider, "provider mismatch");
        assertEq(storedPrice, 0, "price should be zero");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-010: v 值 27 的签名验证通过
    // ═════════════════════════════════════════════════════════
    function test_BID_010_V27_ValidSignature() public {
        // 通过尝试不同的 privateKey 找到 v=27 的签名
        uint256 providerKey = _findKeyWithV(27, 1, 100);
        uint256 jobId = 1;
        uint256 price = 100;
        address provider = vm.addr(providerKey);

        bytes memory sig = _signBid(jobId, price, providerKey);
        bytes memory data = _encodeData(address(this), provider, sig, price);

        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);

        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, provider, "v=27: provider mismatch");
        assertEq(storedPrice, price, "v=27: price mismatch");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-011: v 值 28 的签名验证通过
    // ═════════════════════════════════════════════════════════
    function test_BID_011_V28_ValidSignature() public {
        // 通过尝试不同的 privateKey 找到 v=28 的签名
        uint256 providerKey = _findKeyWithV(28, 2, 200);
        uint256 jobId = 2;
        uint256 price = 200;
        address provider = vm.addr(providerKey);

        bytes memory sig = _signBid(jobId, price, providerKey);
        bytes memory data = _encodeData(address(this), provider, sig, price);

        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);

        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedProvider, provider, "v=28: provider mismatch");
        assertEq(storedPrice, price, "v=28: price mismatch");
    }

    /// @dev 辅助函数：遍历 privateKey 找到签名 v 值匹配的 key
    function _findKeyWithV(
        uint8 targetV,
        uint256 jobId,
        uint256 price
    ) internal returns (uint256) {
        bytes32 messageHash = keccak256(abi.encodePacked(jobId, price));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        // 从 0x1000 开始搜索，最多尝试 256 个 key
        for (uint256 k = 0x1000; k < 0x1100; k++) {
            bytes32 r_;
            bytes32 s_;
            uint8 v_;
            (v_, r_, s_) = vm.sign(k, ethSignedHash);
            if (v_ == targetV) {
                return k;
            }
        }
        revert("_findKeyWithV: could not find matching v");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-012: supportsInterface 对已实现接口返回 true
    // ═════════════════════════════════════════════════════════
    function test_BID_012_SupportsInterface_True() public {
        bool supportsHook = hook.supportsInterface(type(IACPHook).interfaceId);
        bool supports165 = hook.supportsInterface(type(IERC165).interfaceId);

        assertTrue(supportsHook, "should support IACPHook");
        assertTrue(supports165, "should support IERC165");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-013: supportsInterface 对未实现接口返回 false
    // ═════════════════════════════════════════════════════════
    function test_BID_013_SupportsInterface_False() public {
        bool r1 = hook.supportsInterface(0xFFFFFFFF);
        bool r2 = hook.supportsInterface(bytes4(keccak256("nonexistent()")));

        assertFalse(r1, "0xFFFFFFFF should return false");
        assertFalse(r2, "unknown interface should return false");
    }

    // ═════════════════════════════════════════════════════════
    // UT-BID-014: afterAction 调用不 revert 且无副作用
    // ═════════════════════════════════════════════════════════
    function test_BID_014_AfterAction_NoopNoRevert() public {
        uint256 jobId = 1;
        uint256 providerKey = 0xABCD;
        uint256 price = 100;

        // 先通过 beforeAction 存储一个 bid
        (address provider, bytes memory data) =
            _signAndEncode(jobId, price, providerKey);
        hook.beforeAction(jobId, SEL_SETPROVIDER_EXT, data);

        // 记录 afterAction 前的状态
        (address providerBefore, uint256 priceBefore) = hook.bids(jobId);

        // 调用 afterAction — 任意 selector 和 data
        hook.afterAction(jobId, SEL_SETPROVIDER_EXT, data);
        hook.afterAction(jobId, SEL_OTHER, hex"CAFEBABE");
        hook.afterAction(42, bytes4(0), hex"");

        // 验证状态不变
        (address providerAfter, uint256 priceAfter) = hook.bids(jobId);
        assertEq(providerAfter, providerBefore, "afterAction: provider unchanged");
        assertEq(priceAfter, priceBefore, "afterAction: price unchanged");
    }
}
