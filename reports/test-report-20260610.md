# ERC-8183 六步流转测试报告（成功用例）

> 测试时间: 2026-06-10 21:20 UTC  
> 测试网络: Sepolia (Chain ID 11155111)  
> 任务: Swap 0.1 ETH → USDT, 报酬 100 TTK  
> **结果: ✅ 全流程通过 — Evaluator 判 Complete，赏金已发放给 Provider**

---

## 角色钱包

| 角色 | 链上地址 | CAW UUID |
|------|---------|----------|
| Client | `0x736859c94664Dd29A1bdae8FA075e928b60541Bc` | `5a8eeb0c-...` |
| Provider | `0xe2b749ce285b86ff058653336191dec2be50f32c` | `7b30435c-...` |
| Evaluator | `0xf6459a8868dc4d6db511f535f27887e54d2f0d6d` | `4cbd29cc-...` |

---

## 六状态流转图（本次 Job #17）

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

---

## Step 1: 授权托管合约使用代币 (approve_ttk)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `ttk-approve-auto` |
| 策略类型 | `contract_call` |
| 允许链 | SETH |
| 目标合约 | `0xCcb19a9e...` (TTK Token) |
| 限制函数 | `0x095ea7b3` (仅 allow approve) |
| 拒绝条件 | 单笔金额 > 200 TTK |
| 审查模式 | `always_review: true` |
| 完成条件 | tx_count ≥ 1 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x7d8922434e7b4c1b961f408aae4d8ed312a7480cf2e100508f222a960039b34a` |
| 区块 | 11032304 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` (CAW Client) |
| To | `0xCcb1...6cb3` (TTK Token) |
| Gas | 24,371 |
| 函数 | `approve(address,uint256)` |
| 参数 | spender=`0x5C46...dc59`, amount=`100000000000000000000` (100 TTK) |

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x7d8922434e7b4c1b961f408aae4d8ed312a7480cf2e100508f222a960039b34a)

---

## Step 2: 在链上创建托管任务 (create_job)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `erc8183-client-auto` |
| 策略类型 | `contract_call` |
| 允许链 | SETH |
| 目标合约 | `0x5C46deBd...` (ERC-8183 Escrow) |
| 限制函数 | 不限 (所有函数) |
| 拒绝条件 | amount > 1 ETH, tx_count > 5/24h |
| 审查模式 | `always_review: true` |
| 完成条件 | tx_count ≥ 3 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x0950c217e549b5edfca088d4f10ea3d899318a92f07b783dc0964faa1a3fc902` |
| 区块 | 11032309 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` (ERC-8183 Escrow) |
| Gas | 148,907 |
| 函数 | `createJob(address,address,uint256,string,address)` |
| 参数 | provider=`0xe2b7...f32c`, evaluator=`0xf645...0d6d`, expiredAt=`1781731532`, desc=`"CAW Demo Job"`, hook=`0x0` |

**事件**: `JobCreated(jobId=17, client=0x7368..., provider=0xe2b7..., evaluator=0xf645...)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x0950c217e549b5edfca088d4f10ea3d899318a92f07b783dc0964faa1a3fc902)

---

## Step 3: 设置任务赏金预算 (set_budget)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `erc8183-client-17` |
| 目标合约 | `0x5C46deBd...` (ERC-8183 Escrow) |
| 完成条件 | tx_count ≥ 3 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xd0bc31b700be9d87744ecc32d794846984f13337b1c666694b07a4dc5466b723` |
| 区块 | 11032315 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` |
| Gas | 44,083 |
| 函数 | `setBudget(uint256,uint256)` |
| 参数 | jobId=17, amount=`100000000000000000000` (100 TTK) |

**事件**: `BudgetSet(jobId=17, amount=100000000000000000000)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xd0bc31b700be9d87744ecc32d794846984f13337b1c666694b07a4dc5466b723)

---

## Step 4: 将赏金锁定到托管合约 (fund)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `erc8183-client-17` |
| 目标合约 | `0x5C46deBd...` (ERC-8183 Escrow) |
| 完成条件 | tx_count ≥ 3 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x2b594594f25ed8c18e2f63238710b27bb68d398554285f536ba6c1755f5d15ae` |
| 区块 | 11032319 |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` |
| 函数 | `fund(uint256,uint256)` |
| 参数 | jobId=17, expectedBudget=`100000000000000000000` (100 TTK) |

**核心操作**: `IERC20(TTK).transferFrom(Client → Escrow, 100 TTK)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x2b594594f25ed8c18e2f63238710b27bb68d398554285f536ba6c1755f5d15ae)

---

## Step 5: 服务商提交工作成果 (submit)

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `erc8183-submit-17` |
| 策略类型 | `contract_call` |
| 允许链 | SETH |
| 目标合约 | `0x5C46deBd...` |
| 限制函数 | `0x2ecea788` (仅 allow submit) |
| 拒绝条件 | tx_count > 3/24h |
| 审查模式 | `always_review: true` |
| 完成条件 | tx_count ≥ 1 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xbfcf93f29543b990eb31bcc0ed3073e34adb2014266846fad345ecffe688d074` |
| 区块 | 11032325 |
| 状态 | ✅ Success |
| From | `0xe2b7...f32c` (CAW Provider) |
| To | `0x5C46...dc59` |
| 函数 | `submit(uint256,bytes32)` |
| 参数 | jobId=17, deliverable=`0xed6b302a00b4f815248a0abd40fdb27a2bbc05e16694da54ae326b3501d7b627` |

**deliverable 来源**: `SHA256("17:swap:ETH:0.1:USDT:...")` — 基于任务内容的真实哈希

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xbfcf93f29543b990eb31bcc0ed3073e34adb2014266846fad345ecffe688d074)

---

## Step 6: 裁决者验收通过，放款给服务商 (complete)

### Evaluator LLM 评判

- **输入**: Job 状态 (Funded), 任务详情 (ETH→USDT swap, 100 TTK reward)
- **裁决**: ✅ **Complete** — 通过
- **依据**: deliverable 非 dummy 哈希，任务已注资，符合验收标准

### Pact 内容

| 字段 | 值 |
|------|-----|
| Pact 名 | `erc8183-complete-17` |
| 策略类型 | `contract_call` |
| 目标合约 | `0x5C46deBd...` |
| 限制函数 | `0xcd56b1b6` (仅 allow complete) |
| 完成条件 | tx_count ≥ 1 |

### 链上交易 ✅

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x8ae9944f3a86eca5a4bb961859173abc0894684de9f0c2ce4a7f095415bd7e75` |
| 区块 | 11032332 |
| 状态 | ✅ Success |
| From | `0xf645...0D6D` (CAW Evaluator) |
| To | `0x5C46...dc59` |
| 函数 | `complete(uint256,bytes32)` |
| 参数 | jobId=17, reason=`0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` |

**核心操作**: `IERC20(TTK).transfer(Escrow → Provider, 100 TTK)` — 赏金发放

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x8ae9944f3a86eca5a4bb961859173abc0894684de9f0c2ce4a7f095415bd7e75)

---

## TTK 代币流转验证

### 本测试前后对比

| 时间点 | Client TTK | Escrow TTK | Provider TTK | 说明 |
|--------|-----------|-----------|-------------|------|
| 初始 (测试前) | 9,900 | 100 | 5,020 | 上次残留 100 在 Escrow |
| Step 4 后 (fund) | **9,800** (-100) | **200** (+100) | 5,020 | Client→Escrow transferFrom |
| Step 6 后 (complete) | 9,800 | **100** (-100) | **5,120** (+100) | Escrow→Provider transfer |

### 链上证据

| 流转 | TTK 变化 | 验证 |
|------|---------|------|
| Client → Escrow (fund) | `-100` | Escrow 余额 100→200, Client 余额 9900→9800 ✅ |
| Escrow → Provider (complete) | `+100` | Provider 余额 5020→5120, Escrow 余额 200→100 ✅ |
| Net: Client → Provider | 100 TTK 成功转移 | ✅ |

> ⚠️ Escrow 中剩余 100 TTK 来自前次测试 (Job #16) 的 fund，该 Job 未正确 resolve。

---

## ETH / USDT Mock 互换说明

本次测试中"Swap 0.1 ETH → USDT"为任务**描述**，未使用 SimpleSwapHook 进行链上 swap。原因：

- ERC-8183 的 `createJob` 未指定 Hook 地址 (hook=`0x0`)
- `setBudget` 使用简化版函数签名字 `setBudget(uint256,uint256)`，未传 `optParams`
- SimpleSwapHook 需要在 `setBudget` 时传递 `(buyer, outputToken, outputAmount)` 编码参数，且 `submit` 时 Hook 会从 Provider 拉取产出代币

**当前链上状态 (ETH Mock)**:

| 账户 | ETH Mock 余额 |
|------|-------------|
| Client | 0 |
| Provider | 10 ETH (之前铸造) |
| Escrow | 0 |

Provider 已持有 10 ETH mock，为后续集成 Hook 做好了准备。

---

## 全流程交易汇总

| # | 步骤 | Tx Hash | 区块 | From | 状态 |
|---|------|---------|------|------|------|
| 1 | approve | [`0x7d8922...`](https://sepolia.etherscan.io/tx/0x7d8922434e7b4c1b961f408aae4d8ed312a7480cf2e100508f222a960039b34a) | 11032304 | Client | ✅ |
| 2 | createJob | [`0x0950c2...`](https://sepolia.etherscan.io/tx/0x0950c217e549b5edfca088d4f10ea3d899318a92f07b783dc0964faa1a3fc902) | 11032309 | Client | ✅ |
| 3 | setBudget | [`0xd0bc31...`](https://sepolia.etherscan.io/tx/0xd0bc31b700be9d87744ecc32d794846984f13337b1c666694b07a4dc5466b723) | 11032315 | Client | ✅ |
| 4 | fund | [`0x2b5945...`](https://sepolia.etherscan.io/tx/0x2b594594f25ed8c18e2f63238710b27bb68d398554285f536ba6c1755f5d15ae) | 11032319 | Client | ✅ |
| 5 | submit | [`0xbfcf93...`](https://sepolia.etherscan.io/tx/0xbfcf93f29543b990eb31bcc0ed3073e34adb2014266846fad345ecffe688d074) | 11032325 | Provider | ✅ |
| 6 | complete | [`0x8ae994...`](https://sepolia.etherscan.io/tx/0x8ae9944f3a86eca5a4bb961859173abc0894684de9f0c2ce4a7f095415bd7e75) | 11032332 | Evaluator | ✅ |

---

## 关键指标

| 指标 | 值 |
|------|-----|
| 总交易数 | 6 (全部链上确认) |
| 总 Gas 消耗 | ~350,000 |
| TTK 赏金 | 100 TTK 成功从 Client → Provider |
| Job 状态 | 3 (Completed) |
| CAW Pact 审批 | 6 次 Pact + 6 次 Contract Call = 12 次用户确认 |
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
