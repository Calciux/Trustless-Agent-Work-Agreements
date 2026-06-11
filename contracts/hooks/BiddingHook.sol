// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../interfaces/IACPHook.sol";
import {IERC165} from "../interfaces/IERC165.sol";

/**
 * @title BiddingHook
 * @notice 开放竞价 Hook：Client 创建 provider=0 的 Job，多个 Provider
 *         链下签名报价，Client 选出最优者调用 setProvider(jobId, winner, sig+price)
 * @dev 仅拦截 SEL_SETPROVIDER_EXT (带 optParams 的 setProvider 重载)
 *      beforeAction 做签名验证 + 存储竞价信息
 *      afterAction 为空操作
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

    /**
     * @notice 拦截 setProvider 带 optParams 版本，验证 EIP-191 签名
     * @param jobId    任务 ID
     * @param selector 函数选择器（应为 SEL_SETPROVIDER_EXT）
     * @param data     abi.encode(msg.sender, provider, optParams)
     *                 其中 optParams = abi.encode(signature, price)
     * @dev 签名消息 = keccak256(abi.encodePacked(jobId, price))
     *      EIP-191 前缀包裹后 ecrecover 恢复出 signer
     *      require(signer == provider) 确保签名者即被设置为 Provider 的地址
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

        _verifySignature(jobId, price, sig, provider);

        // ---- 存储竞价记录 ----
        bids[jobId] = Bid(provider, price);
    }

    /// @dev 提取签名验证到独立函数，避免 Stack too deep
    function _verifySignature(
        uint256 jobId,
        uint256 price,
        bytes memory sig,
        address expectedSigner
    ) private pure {
        bytes32 messageHash = keccak256(abi.encodePacked(jobId, price));
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;

        address signer = ecrecover(ethSignedMessageHash, v, r, s);
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
