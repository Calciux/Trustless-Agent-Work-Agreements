// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IERC20Minimal
 * @dev 最小 ERC-20 接口，仅包含 ERC8183Escrow 所需的 4 个函数
 */
interface IERC20Minimal {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}
