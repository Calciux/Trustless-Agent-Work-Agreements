// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IACPHook} from "../interfaces/IACPHook.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";

// @title SimpleSwapHook — 最简 swap Hook
// @notice 资本代币(USDT)由 Client 直接转 Provider（链下/手动）
//         Hook 只管理产出代币(ETH)：submit 时 Provider 存入，complete 时释放给 buyer
//         setBudget optParams: abi.encode(buyer, outputToken, outputAmount)
contract SimpleSwapHook is IACPHook {
    bytes4 private constant S_SETBUDGET = bytes4(keccak256("setBudget(uint256,uint256,bytes)"));
    bytes4 private constant S_SUBMIT    = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 private constant S_COMPLETE  = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 private constant S_REJECT    = bytes4(keccak256("reject(uint256,bytes32)"));

    struct Swap {
        address buyer;
        address outputToken;
        uint256 outputAmount;
    }

    mapping(uint256 => Swap) public swaps;
    mapping(uint256 => uint256) public deposited;

    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override {
        // setBudget: store swap params
        if (selector == S_SETBUDGET) {
            if (data.length >= 96) {
                (address buyer, address outT, uint256 outA)
                    = abi.decode(data, (address, address, uint256));
                swaps[jobId] = Swap(buyer, outT, outA);
            }
        }
        // submit: pull output tokens from Provider (tx.origin)
        if (selector == S_SUBMIT) {
            Swap memory s = swaps[jobId];
            if (s.outputAmount > 0 && deposited[jobId] == 0) {
                IERC20Minimal(s.outputToken).transferFrom(tx.origin, address(this), s.outputAmount);
                deposited[jobId] = s.outputAmount;
            }
        }
    }

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata) external override {
        // complete: release output to buyer
        if (selector == S_COMPLETE) {
            Swap memory s = swaps[jobId];
            uint256 amount = deposited[jobId];
            if (s.buyer != address(0) && amount > 0) {
                deposited[jobId] = 0;
                IERC20Minimal(s.outputToken).transfer(s.buyer, amount);
            }
        }
        // reject: return output to Provider (tx.origin)
        if (selector == S_REJECT) {
            uint256 amount = deposited[jobId];
            if (amount > 0) {
                deposited[jobId] = 0;
                IERC20Minimal(swaps[jobId].outputToken).transfer(tx.origin, amount);
            }
        }
    }
}
