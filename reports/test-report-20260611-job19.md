# ERC-8183 六步流转测试报告 — Job #19（PACT_OPTIMIZED 模式）

> 测试时间: 2026-06-11 00:52-01:00 UTC  
> 测试网络: Sepolia (Chain ID 11155111)  
> 任务: Swap 0.1 ETH → USDT, 报酬 100 TTK  
> 模式: **🟢 PACT_OPTIMIZED=true**（自动审批：3 次 Pact 审批 vs 原版 12 次）  
> **结果: ✅ 全流程通过 — Evaluator 判 Complete，赏金已发放给 Provider**

---

## 角色钱包

| 角色 | 链上地址 | CAW UUID |
|------|---------|----------|
| Client | `0x736859c94664Dd29A1bdae8FA075e928b60541Bc` | `5a8eeb0c-...` |
| Provider | `0xe2b749ce285b86ff058653336191dec2be50f32c` | `7b30435c-...` |
| Evaluator | `0xf6459a8868dc4d6db511f535f27887e54d2f0d6d` | `4cbd29cc-...` |

---

## 六状态流转图（本次 Job #19）

```
  ┌──────────┐              ┌──────────┐              ┌──────────┐
  │  Step 1  │   createJob  │  Step 2  │  setBudget   │  Step 3  │
  │ APPROVED │──────────────→│   OPEN   │──────────────→│ BUDGET SET│
  └──────────┘              └──────────┘              └──────────┘
       ↑                                                    │
  approve(TTK)                                          fund(TTK)
       │                                                    ↓
  ┌──────────┐              ┌──────────┐              ┌──────────┐
  │  IDLE    │              │  Step 6  │   complete   │  Step 4  │
  │          │              │COMPLETED │←──────────────│  FUNDED  │
  └──────────┘              └──────────┘              └──────────┘
                                  │                        ↑
                            Evaluator                  submit
                            LLM judges                    │
                                  │                  ┌──────────┐
                                  └──────────────────│  Step 5  │
                                                     │SUBMITTED │
                                                     └──────────┘
```

**Pact 审批优化**: 本次采用 `PACT_OPTIMIZED=true` 模式，三个角色各持一个合并 Pact（`always_review=false` + 函数白名单）。Client 的 approve/createJob/setBudget/fund 四步共享一个 Pact，Provider 和 Evaluator 各一个独立 Pact。**Pact 审批 3 次后，内部 6 笔交易全部自动执行，无需逐笔在 CAW App 中批准。**

---

## Step 1: 授权托管合约使用代币 (approve_ttk)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `client-merged-19`（合并 Pact） |
| 涵盖步骤 | approve + createJob + setBudget + fund |
| 策略数 | 2（策略1: TTK approve，策略2: ERC-8183 托管操作）|
| 策略1 审批模式 | 🟢 `always_review: false`（自动放行） |
| 策略2 审批模式 | 🟢 `always_review: false`（自动放行） |
| 策略2 函数白名单 | `createJob`, `setBudget`, `fund` |
| 拒绝条件 | 单笔 > 200 TTK / 24h > 6 笔 |
| 完成条件 | tx_count ≥ 4 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x1201319446e77145f04eab170403caf1421852b5b9dd9e42faf97a4bac538a88` |
| 区块 | 11033343 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` (CAW Client) |
| To | `0xCcb1...6cb3` (TTK Token) |
| Gas | 44,729 |
| 函数 | `approve(address,uint256)` |
| 参数 | spender=`0x5C46...dc59`, amount=`100000000000000000000` (100 TTK) |

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x1201319446e77145f04eab170403caf1421852b5b9dd9e42faf97a4bac538a88)

---

## Step 2: 在链上创建托管任务 (create_job)

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xaf53a1792f759df2ea766cbe6588d7b39f1457c6108ec5936cc71b41a22406cb` |
| 区块 | 11033346 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` (ERC-8183 Escrow) |
| Gas | 148,907 |
| 函数 | `createJob(address,address,uint256,string,address)` |
| 参数 | provider=`0xe2b7...f32c`, evaluator=`0xf645...0d6d`, expiredAt=`1781744001`, desc=`"CAW Demo Job"`, hook=`0x0` |

**事件**: `JobCreated(jobId=19, client=0x7368..., provider=0xe2b7..., evaluator=0xf645...)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xaf53a1792f759df2ea766cbe6588d7b39f1457c6108ec5936cc71b41a22406cb)

---

## Step 3: 设置任务赏金预算 (set_budget)

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x2f58a863b8db314705304508a585c94f76b856cb92aa19b2defdfdbb70c33939` |
| 区块 | 11033349 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` |
| Gas | 58,803 |
| 函数 | `setBudget(uint256,uint256)` |
| 参数 | jobId=19, amount=`100000000000000000000` (100 TTK) |

**事件**: `BudgetSet(jobId=19, amount=100000000000000000000)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x2f58a863b8db314705304508a585c94f76b856cb92aa19b2defdfdbb70c33939)

---

## Step 4: 将赏金锁定到托管合约 (fund)

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x1b52f9654f9106dab20c654a640f9248c2a1638764848c4866ed363f58a6b826` |
| 区块 | 11033352 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` |
| Gas | 78,164 |
| 函数 | `fund(uint256,uint256)` |
| 参数 | jobId=19, expectedBudget=`100000000000000000000` (100 TTK) |

**核心操作**: `IERC20(TTK).transferFrom(Client → Escrow, 100 TTK)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x1b52f9654f9106dab20c654a640f9248c2a1638764848c4866ed363f58a6b826)

---

## Step 5: 服务商提交工作成果 (submit)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `provider-submit-19` |
| 策略类型 | `contract_call` |
| 允许链 | SETH |
| 目标合约 | `0x5C46deBd...` |
| 限制函数 | `0x2ecea788` (仅 allow submit) |
| 审批模式 | 🟢 `always_review: false` |
| 拒绝条件 | tx_count > 3/24h |
| 完成条件 | tx_count ≥ 1 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x2fa2f35f6a295ff07338437a9ff2462b27d40db4c3a3479fa52870a9ee1627be` |
| 区块 | 11033370 |
| 状态 | ✅ Success |
| From | `0xe2b7...f32c` (CAW Provider) |
| To | `0x5C46...dc59` |
| Gas | 44,198 |
| 函数 | `submit(uint256,bytes32)` |
| 参数 | jobId=19, deliverable=`0x6752ec7d06f058eeb1661044c983bc9bdcfae38cf4c0f08bfa13d4d95cbd9768` |

**deliverable 来源**: `SHA256("19:swap:ETH:0.1:USDT:...")` — 基于任务内容的真实哈希

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x2fa2f35f6a295ff07338437a9ff2462b27d40db4c3a3479fa52870a9ee1627be)

---

## Step 6: 裁决者验收通过，放款给服务商 (complete)

### Evaluator LLM 评判

- **输入**: Job 状态 (Funded), 任务详情 (ETH→USDT swap, 100 TTK reward)
- **裁决**: ✅ **Complete** — 通过
- **依据**: deliverable 非 dummy 哈希，任务已注资，符合验收标准

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `evaluator-resolve-19` |
| 策略数 | 2（策略1: complete 放款，策略2: reject 退款）|
| 审批模式 | 🟢 `always_review: false` |
| 限制函数 | `0xcd56b1b6` (complete), `0x6be1320b` (reject) |
| 完成条件 | tx_count ≥ 1 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xd6be420a417dd08b3eb200eae3860552b5c6ccdee730239e350cb7fbd9843c2d` |
| 区块 | 11033379 |
| 状态 | ✅ Success |
| From | `0xf645...0D6D` (CAW Evaluator) |
| To | `0x5C46...dc59` |
| Gas | 62,945 |
| 函数 | `complete(uint256,bytes32)` |
| 参数 | jobId=19, reason=`0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` |

**核心操作**: `IERC20(TTK).transfer(Escrow → Provider, 100 TTK)` — 赏金发放

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xd6be420a417dd08b3eb200eae3860552b5c6ccdee730239e350cb7fbd9843c2d)

---

## TTK 代币流转验证

> **TTK (Test Token)** 是本项目部署在 Sepolia 测试网的 Mock ERC-20 代币，用于模拟链上赏金支付。它不具真实价值，仅供开发测试使用。

### 本测试前后对比

| 时间点 | Client TTK | Escrow TTK | Provider TTK | 说明 |
|--------|-----------|-----------|-------------|------|
| 初始 (Job #17 最终状态) | 9,800 | 100 | 5,120 | Escrow 中 100 TTK 来自 Job #16 遗留 |
| Step 4 后 (fund) | **9,700** (-100) | **200** (+100) | 5,120 | Client→Escrow transferFrom |
| Step 6 后 (complete) | 9,700 | **100** (-100) | **5,220** (+100) | Escrow→Provider transfer |

### 链上证据

| 流转 | TTK 变化 | 验证 |
|------|---------|------|
| Client → Escrow (fund) | `-100` | Escrow 余额 100→200, Client 余额 9800→9700 ✅ |
| Escrow → Provider (complete) | `+100` | Provider 余额 5120→5220, Escrow 余额 200→100 ✅ |
| Net: Client → Provider | 100 TTK 成功转移 | ✅ |

> ⚠️ Escrow 中仍剩余 100 TTK，来自前次测试 (Job #16) 的 fund，该 Job 未正确 resolve（同 Job #17 报告中的遗留问题）。

### 链上余额实时查询

以下链接可在 Sepolia Etherscan 上实时查看各地址的 TTK 余额（打开后页面会展示该地址持有的 TTK 数量和转账记录）：

| 角色 | 地址 | 当前 TTK 余额 | 余额查询链接 |
|------|------|-------------|------------|
| Client | `0x7368...41Bc` | 9,700 | [查看余额](https://sepolia.etherscan.io/token/0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3?a=0x736859c94664Dd29A1bdae8FA075e928b60541Bc) |
| Escrow | `0x5C46...dc59` | 100 | [查看余额](https://sepolia.etherscan.io/token/0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3?a=0x5C46deBd8A308e69e56955A8eE647Bf75694dc59) |
| Provider | `0xe2b7...f32c` | 5,220 | [查看余额](https://sepolia.etherscan.io/token/0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3?a=0xe2b749ce285b86ff058653336191dec2be50f32c) |

### 如何在区块浏览器上自行验证

1. **查看代币余额** — 打开上述"查看余额"链接，或访问 [TTK 代币页面](https://sepolia.etherscan.io/token/0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3)，在 "Holders" 标签页可看到所有持币地址及余额
2. **查看转账记录** — 在代币页面点击任一地址，进入 "Token Transfers (ERC-20)" 标签页，可看到该地址所有 TTK 转入/转出记录
3. **追踪单笔转账** — 从上方交易汇总表点击任意 Tx Hash 链接，在交易详情页的 "ERC-20 Tokens Transferred" 区域可看到该笔交易触发的代币流转
4. **命令行验证** — 也可通过 `cast` 直接查询：
   ```bash
   cast call 0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3 \
     "balanceOf(address)(uint256)" <地址> \
     --rpc-url https://1rpc.io/sepolia
   ```

---

## PACT_OPTIMIZED 模式效能对比

| 维度 | Job #17（原版） | Job #19（优化版） | 优化 |
|------|----------------|-------------------|------|
| Pact 数量 | 5-6 个 | 3 个 | **-50%** |
| Pact 模板 | 每步独立 | 每角色合并 | 复用 |
| always_review | true（全需审批） | false（自动放行） | **自动** |
| 函数白名单 | 仅 approve 有 | 全部有 | **更安全** |
| 预算来源 | 写死 1 ETH | 从用户输入推导 | **精准** |
| Pact 审批次数 | 6 次 | 3 次 | **-50%** |
| Contract Call 审批 | 6 次 | 0 次 | **-100%** |
| **总用户操作** | **12 次** | **3 次** | **-75%** |

---

## 全流程交易汇总

| # | 步骤 | Tx Hash | 区块 | From | Gas | 状态 |
|---|------|---------|------|------|-----|------|
| 1 | approve | [`0x120131...`](https://sepolia.etherscan.io/tx/0x1201319446e77145f04eab170403caf1421852b5b9dd9e42faf97a4bac538a88) | 11033343 | Client | 44,729 | ✅ |
| 2 | createJob | [`0xaf53a1...`](https://sepolia.etherscan.io/tx/0xaf53a1792f759df2ea766cbe6588d7b39f1457c6108ec5936cc71b41a22406cb) | 11033346 | Client | 148,907 | ✅ |
| 3 | setBudget | [`0x2f58a8...`](https://sepolia.etherscan.io/tx/0x2f58a863b8db314705304508a585c94f76b856cb92aa19b2defdfdbb70c33939) | 11033349 | Client | 58,803 | ✅ |
| 4 | fund | [`0x1b52f9...`](https://sepolia.etherscan.io/tx/0x1b52f9654f9106dab20c654a640f9248c2a1638764848c4866ed363f58a6b826) | 11033352 | Client | 78,164 | ✅ |
| 5 | submit | [`0x2fa2f3...`](https://sepolia.etherscan.io/tx/0x2fa2f35f6a295ff07338437a9ff2462b27d40db4c3a3479fa52870a9ee1627be) | 11033370 | Provider | 44,198 | ✅ |
| 6 | complete | [`0xd6be42...`](https://sepolia.etherscan.io/tx/0xd6be420a417dd08b3eb200eae3860552b5c6ccdee730239e350cb7fbd9843c2d) | 11033379 | Evaluator | 62,945 | ✅ |

---

## 关键指标

| 指标 | 值 |
|------|-----|
| 总交易数 | 6 (全部链上确认) |
| 总 Gas 消耗 | ~437,746 |
| TTK 赏金 | 100 TTK 成功从 Client → Provider |
| Job 状态 | 3 (Completed) |
| CAW Pact 审批 | **3 次**（vs 原版 12 次 = **节省 75%**） |
| 预算来源 | 用户输入 reward_amount=100 TTK → max_ttk=200; input_amount=0.1 ETH → max_eth=1.0 ETH |
| Evaluator 判定 | Complete (LLM DeepSeek 自动评判) |

---

## 附录: 合约地址

| 合约 | 地址 | Etherscan |
|------|------|-----------|
| ERC-8183 Escrow | `0x5C46deBd8A308e69e56955A8eE647Bf75694dc59` | [查看](https://sepolia.etherscan.io/address/0x5C46deBd8A308e69e56955A8eE647Bf75694dc59) |
| TTK Token | `0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3` | [查看](https://sepolia.etherscan.io/address/0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3) |
| ETH Mock | `0x94022198f8497F98a47d24B754a602AD2A97FE99` | [查看](https://sepolia.etherscan.io/address/0x94022198f8497F98a47d24B754a602AD2A97FE99) |
| USDT Mock | `0x8c7D953c2c897E471Bf5A7BE8532AF79258e0BEb` | [查看](https://sepolia.etherscan.io/address/0x8c7D953c2c897E471Bf5A7BE8532AF79258e0BEb) |
| CAW Client | `0x7368...41Bc` | [查看](https://sepolia.etherscan.io/address/0x736859c94664Dd29A1bdae8FA075e928b60541Bc) |
| CAW Provider | `0xe2b7...f32c` | [查看](https://sepolia.etherscan.io/address/0xe2b749ce285b86ff058653336191dec2be50f32c) |
| CAW Evaluator | `0xf645...0D6D` | [查看](https://sepolia.etherscan.io/address/0xf6459a8868dc4d6db511f535f27887e54d2f0d6d) |
