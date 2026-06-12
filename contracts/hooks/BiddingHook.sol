// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../interfaces/IACPHook.sol";
import {IERC165} from "../interfaces/IERC165.sol";

/**
 * @title BiddingHook
 * @notice 开放竞价 Hook：Client 创建 provider=0 的 Job，多个 Provider
 *         链下 EIP-712 签名报价，Client 选出最优者调用 setProvider(jobId, winner, sig+price)
 * @dev 仅拦截 SEL_SETPROVIDER_EXT (带 optParams 的 setProvider 重载)
 *      beforeAction 做 EIP-712 签名验证 + 存储竞价信息
 *      afterAction 为空操作
 *      v2: 升级到 EIP-712 签名（从 EIP-191），兼容 CAW message_sign 自动审批
 */
contract BiddingHook is IACPHook {
    /**
     * @notice 竞价记录结构体
     * @param provider 中标的 Provider 地址
     * @param price    中标报价金额
     */
    struct Bid {
        address provider;
        uint256 price;
    }

    /// @notice jobId → 竞价记录映射
    mapping(uint256 => Bid) public bids;

    /// @notice setProvider(uint256,address,bytes) 的函数选择器
    bytes4 private constant SEL_SETPROVIDER_EXT =
        bytes4(keccak256("setProvider(uint256,address,bytes)"));

    /// @notice EIP-712 类型哈希
    bytes32 private constant BID_TYPEHASH =
        keccak256("Bid(uint256 jobId,uint256 price)");

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /**
     * @notice 拦截 setProvider 带 optParams 版本，验证 EIP-712 签名
     * @param jobId    任务 ID
     * @param selector 函数选择器（应为 SEL_SETPROVIDER_EXT）
     * @param data     abi.encode(msg.sender, provider, optParams)
     *                 其中 optParams = abi.encode(signature, price)
     * @dev EIP-712 签名消息:
     *      domainSeparator = hash(EIP712Domain(name:"BiddingHook", version:"1",
     *          chainId, verifyingContract: address(this)))
     *      structHash = hash(Bid(jobId, price))
     *      digest = hash("\x19\x01" + domainSeparator + structHash)
     *      CAW message_sign 可直接用此格式自动签名
     */
    function beforeAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external override {
        // 仅拦截带 optParams 的 setProvider；无 optParams 版本直接放行
        if (selector != SEL_SETPROVIDER_EXT) return;

        // ---- 第一层解码 ----
        // data = abi.encode(msg.sender, provider, optParams)
        //        = abi.encode(address,   address,  bytes)
        ( , address provider, bytes memory innerOptParams) =
            abi.decode(data, (address, address, bytes));

        // ---- 第二层解码 ----
        // innerOptParams = abi.encode(signature, price)
        //                = abi.encode(bytes,     uint256)
        (bytes memory sig, uint256 price) =
            abi.decode(innerOptParams, (bytes, uint256));

        _verifyEIP712Signature(jobId, price, sig, provider);

        // ---- 存储竞价记录 ----
        bids[jobId] = Bid(provider, price);
    }

    /**
     * @notice 构建 EIP-712 domain separator
     */
    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("BiddingHook")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice 构建 EIP-712 签名摘要
     * @param jobId 任务 ID
     * @param price 报价金额
     * @return digest EIP-712 摘要（已含 \x19\x01 前缀）
     */
    function _buildDigest(uint256 jobId, uint256 price)
        private view returns (bytes32)
    {
        bytes32 domainSeparator = _buildDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(BID_TYPEHASH, jobId, price));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /**
     * @dev 提取签名中的 r, s, v 并验证 EIP-712 签名
     * @param jobId 任务 ID
     * @param price 报价金额
     * @param sig 65 字节签名 (r[32] || s[32] || v[1])
     * @param expectedSigner 期望的签名者地址
     */
    function _verifyEIP712Signature(
        uint256 jobId,
        uint256 price,
        bytes memory sig,
        address expectedSigner
    ) private view {
        require(sig.length == 65, "BiddingHook: invalid signature length");

        bytes32 digest = _buildDigest(jobId, price);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;

        address signer = ecrecover(digest, v, r, s);
        require(signer == expectedSigner, "BiddingHook: invalid signature");
    }

    /**
     * @notice afterAction — 空操作（竞价 Hook 不需要事后逻辑）
     */
    function afterAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external override {
        // 无操作
    }

    /**
     * @notice ERC-165 接口检测
     * @param interfaceId 4 字节接口标识符
     * @return true 如果实现了该接口
     * @dev 不加 override：IACPHook 不继承 IERC165，不存在冲突
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IACPHook).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
