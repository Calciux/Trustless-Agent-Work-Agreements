// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// @title 最简 ERC-20 Mock（仅用于 forge 测试）
// @notice 只实现 ERC8183Escrow 测试所需的最小函数
// @dev 不做权限控制、不实现标准事件、不依赖 OpenZeppelin
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // @notice 铸造代币（公开，仅用于测试）
    // @param to 接收地址
    // @param amount 铸造数量
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    // @notice 授权额度
    // @param spender 被授权地址
    // @param amount 授权额度
    // @return true
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // @notice 转账
    // @param to 接收地址
    // @param amount 转账数量
    // @return true
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    // @notice 代扣转账
    // @param from 扣款地址
    // @param to 接收地址
    // @param amount 转账数量
    // @return true
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
