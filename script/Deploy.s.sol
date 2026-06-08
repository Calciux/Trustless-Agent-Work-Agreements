// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {ERC8183Escrow} from "../contracts/ERC8183Escrow.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {SimpleSwapHook} from "../contracts/hooks/SimpleSwapHook.sol";
import {FundTransferHook} from "../contracts/hooks/FundTransferHook.sol";
import {IERC8183} from "../contracts/interfaces/IERC8183.sol";

// @title Deploy — ERC-8183 Sepolia 一键部署脚本
// @notice 用法:
//   # 完整部署（新代币 + 新 Escrow + Hook）
//   forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
//
//   # 仅部署 Hook（复用已有代币和 Escrow）
//   forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv \
//     --sig "runDeployHookOnly()"
//
//   # 仅铸币
//   forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv \
//     --sig "runMintOnly()"
//
//   # Demo job（创建→setBudget→fund→submit→complete）
//   forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv \
//     --sig "runDemoJob()"
//
//   环境变量（.env 中设置）：
//     CLIENT_ADDRESS / CLIENT_PRIVATE_KEY
//     PROVIDER_ADDRESS
//     EVALUATOR_ADDRESS
//     TREASURY（可选，默认 address(0)）
//     FEE_BPS（可选，默认 0）
//     TOKEN / ESCROW / HOOK（可选，复用已有地址时设置）

contract Deploy is Script {
    // ── 部署的合约 ──
    MockERC20 public ttToken;
    MockERC20 public usdtToken;
    MockERC20 public ethToken;
    ERC8183Escrow public escrow;
    SimpleSwapHook public simpleHook;
    FundTransferHook public fundHook;

    // ── 角色 ──
    address public client;
    address public provider;
    address public evaluator;
    address public treasury;
    uint256 public feeBps;

    // ── 已有地址（从环境变量读取，非零则跳过部署） ──
    address public existingTToken;
    address public existingEscrow;

    function setUp() public {
        // 从环境变量读取私钥（用于广播交易）
        uint256 deployerKey = vm.envUint("CLIENT_PRIVATE_KEY");
        client = vm.envAddress("CLIENT_ADDRESS");
        provider = vm.envOr("PROVIDER_ADDRESS", address(0));
        evaluator = vm.envOr("EVALUATOR_ADDRESS", address(0));

        // 可选：复用已有地址
        existingTToken = vm.envOr("TOKEN", address(0));
        existingEscrow = vm.envOr("ESCROW", address(0));

        treasury = vm.envOr("TREASURY", address(0));
        feeBps = vm.envOr("FEE_BPS", uint256(0));

        // 用 deployer 的 key 开始广播
        vm.startBroadcast(deployerKey);
    }

    // ═══════════════════════════════════════════════════
    //  run() — 默认入口：完整部署
    // ═══════════════════════════════════════════════════

    function run() external {
        deployTokens();
        deployEscrow();
        deployHooks();
        mintTokens();
        console.log("=== Deploy complete ===");
        printAddresses();
        vm.stopBroadcast();
    }

    // ═══════════════════════════════════════════════════
    //  runDeployHookOnly() — 仅部署 Hook（复用已有代币和 Escrow）
    // ═══════════════════════════════════════════════════

    function runDeployHookOnly() external {
        require(existingEscrow != address(0), "set ESCROW in .env");
        deployHooks();
        console.log("=== Hook deploy complete ===");
        printAddresses();
        vm.stopBroadcast();
    }

    // ═══════════════════════════════════════════════════
    //  runMintOnly() — 仅铸币
    // ═══════════════════════════════════════════════════

    function runMintOnly() external {
        require(existingTToken != address(0), "set TOKEN in .env");
        mintTokens();
        console.log("=== Mint complete ===");
        vm.stopBroadcast();
    }

    // ═══════════════════════════════════════════════════
    //  runDemoJob() — 创建并执行一个 Demo job
    // ═══════════════════════════════════════════════════

    function runDemoJob() external {
        require(existingEscrow != address(0), "set ESCROW in .env");
        require(address(simpleHook) != address(0) || vm.envOr("HOOK", address(0)) != address(0),
                "deploy hook first or set HOOK in .env");

        address hookAddr = address(simpleHook) != address(0)
            ? address(simpleHook)
            : vm.envAddress("HOOK");

        ERC8183Escrow e = ERC8183Escrow(existingEscrow);
        uint256 expiredAt = block.timestamp + 7 days;
        uint256 budget = 50;

        // 1. createJob
        uint256 jobId = e.createJob(provider, evaluator, expiredAt, "demo-swap", hookAddr);
        console.log("createJob: jobId =", jobId);

        // 2. setBudget with swap params (buyer=client, outputToken=ethToken, outputAmount=1)
        bytes memory optParams;
        if (address(ethToken) != address(0)) {
            optParams = abi.encode(client, address(ethToken), uint256(1));
        }
        e.setBudget(jobId, budget, optParams);
        console.log("setBudget done");

        // 3. fund
        ttToken.approve(address(e), budget);
        e.fund(jobId, budget);
        console.log("fund done, status =", uint256(e.getStatus(jobId)));

        // 4. submit (需要 provider 的 key——这里 client 不能 submit)
        //    在实际使用中 runDemoJob 用 deployer key，不适用于多角色场景
        //    建议: forge script 不支持多私钥切换，需用 cast 手动 submit
        console.log("submit + complete: run manually (forge script single-key limit)");
        console.log("  cast send $ESCROW 'submit(uint256,bytes32)'", jobId, "<hash> --private-key $PROVIDER_PRIVATE_KEY");
        console.log("  cast send $ESCROW 'complete(uint256,bytes32)'", jobId, "<hash> --private-key $EVALUATOR_PRIVATE_KEY");

        vm.stopBroadcast();
    }

    // ═══════════════════════════════════════════════════
    //  内部函数
    // ═══════════════════════════════════════════════════

    function deployTokens() internal {
        if (existingTToken != address(0)) {
            console.log("Using existing TTK:", existingTToken);
            ttToken = MockERC20(existingTToken);
        } else {
            ttToken = new MockERC20();
            console.log("TTK deployed:", address(ttToken));
        }

        // 始终部署 USDT 和 ETH（mock）——或检查环境变量
        address existingUSDT = vm.envOr("USDT", address(0));
        if (existingUSDT != address(0)) {
            usdtToken = MockERC20(existingUSDT);
            console.log("Using existing USDT:", existingUSDT);
        } else {
            usdtToken = new MockERC20();
            console.log("USDT deployed:", address(usdtToken));
        }

        address existingETH = vm.envOr("ETH", address(0));
        if (existingETH != address(0)) {
            ethToken = MockERC20(existingETH);
            console.log("Using existing ETH(mock):", existingETH);
        } else {
            ethToken = new MockERC20();
            console.log("ETH(mock) deployed:", address(ethToken));
        }
    }

    function deployEscrow() internal {
        if (existingEscrow != address(0)) {
            console.log("Using existing Escrow:", existingEscrow);
            escrow = ERC8183Escrow(existingEscrow);
        } else {
            require(address(ttToken) != address(0), "deploy TTK first");
            escrow = new ERC8183Escrow(address(ttToken), treasury, feeBps);
            console.log("Escrow deployed:", address(escrow));
            console.log("  paymentToken =", escrow.paymentToken());
            console.log("  treasury     =", treasury);
            console.log("  feeBps       =", feeBps);
        }
    }

    function deployHooks() internal {
        address existingHook = vm.envOr("HOOK", address(0));
        if (existingHook != address(0)) {
            console.log("Using existing SimpleSwapHook:", existingHook);
            simpleHook = SimpleSwapHook(existingHook);
        } else {
            simpleHook = new SimpleSwapHook();
            console.log("SimpleSwapHook deployed:", address(simpleHook));
        }

        address existingFundHook = vm.envOr("FUND_HOOK", address(0));
        if (existingFundHook != address(0)) {
            fundHook = FundTransferHook(existingFundHook);
            console.log("Using existing FundTransferHook:", existingFundHook);
        } else {
            fundHook = new FundTransferHook();
            console.log("FundTransferHook deployed:", address(fundHook));
        }
    }

    function mintTokens() internal {
        if (client == address(0)) return;

        // 给 Client mint 初始资金
        uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(1000));
        ttToken.mint(client, mintAmount);
        console.log("Minted TTK:", mintAmount, "to", client);

        if (address(usdtToken) != address(0)) {
            usdtToken.mint(client, mintAmount);
            console.log("Minted USDT:", mintAmount, "to", client);
        }

        if (address(ethToken) != address(0) && provider != address(0)) {
            ethToken.mint(provider, 10);
            console.log("Minted ETH(mock): 10 to", provider);
        }
    }

    function printAddresses() internal view {
        console.log("=== Contract Addresses ===");
        console.log("TTK:           ", address(ttToken));
        console.log("USDT:          ", address(usdtToken));
        console.log("ETH(mock):     ", address(ethToken));
        console.log("Escrow:        ", address(escrow));
        console.log("SimpleSwapHook:", address(simpleHook));
        console.log("FundTransferHook:", address(fundHook));
    }
}
