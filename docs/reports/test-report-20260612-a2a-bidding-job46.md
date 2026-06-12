# A2A Bidding 全流程测试报告 — Job #46（BiddingHook + CAW EIP-712 签名）

> 测试时间: 2026-06-12 04:12~04:30 UTC  
> 测试网络: Sepolia (Chain ID 11155111)  
> 任务: Swap 0.1 ETH → USDT, 报酬 100 TTK  
> 模式: **🟢 PACT_OPTIMIZED=true**（自动审批）  
> 架构: **A2A 竞价 (Bidding)** — 双 Provider 竞争，LLM 自动选最低价  
> Hook: **BiddingHook v3** (`0x80aB74...B0809d`) — EIP-712 链上验签  
> **结果: ✅ 全流程通过（8 步/10 笔交易全部上链确认）**

---

## 角色钱包

| 角色 | 链上地址 | CAW UUID | CAW 环境 | 说明 |
|------|---------|----------|---------|------|
| Client | `0x736859c94664Dd29A1bdae8FA075e928b60541Bc` | `5a8eeb0c-...` | DEV | 创建任务、注资、锁定中标者 |
| Provider A | `0x01b77F6cFad5cd30BC3E78273F0Faf5544621526` | `3f01ec47-...` | PROD | 出价 80 TTK，中标 |
| Provider B | `0x7f79716274d6db28784664c02e678c1a3196c948` | `2a62f9a9-...` | PROD | 出价 100 TTK，未中标 |
| Evaluator | `0xf6459a8868dc4d6db511f535f27887e54d2f0d6d` | `4cbd29cc-...` | DEV | 裁定 reject 退款 |

---

## 整体流程

```
Client                          Provider A/B                     Evaluator
  │                                  │                               │
  ├─ 1. approve_ttk ──────────────► TTK 合约                        │
  ├─ 2. createJob(open, hook) ───► Escrow + BiddingHook             │
  │                                  │                               │
  │                          ◄── 3. Provider A 签名报价(80 TTK)     │
  │                          ◄── 4. Provider B 签名报价(100 TTK)    │
  │                                  │                               │
  ├─ 5. LLM 比价选 A ──────────► (链下)                            │
  ├─ 6. setProvider(EXT+sig) ───► Escrow → BiddingHook 验签       │
  ├─ 7. setBudget(100 TTK) ─────► Escrow                           │
  ├─ 8. fund(100 TTK) ──────────► Escrow → TTK.transferFrom        │
  │                                  │                               │
  │                          9. submit ──────────────► Escrow      │
  │                                  │                               │
  │                                            10. reject ───────► Escrow
  │                                                                  │
  └── 退款 TTK 回 Client ◄──────────────────────────────────────────┘
```

---

## BiddingHook 工作原理

### 为什么需要 BiddingHook？

传统 ERC-8183 的 `setProvider` 由 Client 直接调用，无需验证。但在 A2A 竞价场景中，Client 需要证明"Provider 确实同意以某个价格接单"，防止 Client 伪造报价。

### BiddingHook 的职责

```
setProvider(jobId, winner, optParams)
    │
    ├── Escrow 收到调用，检查 optParams 不为空
    ├── Escrow 调用 BiddingHook.beforeAction()
    │       │
    │       ├── 解码 data → (bytes sig, uint256 price)
    │       ├── EIP-712 域分隔: BiddingHook + chainId + 本合约地址
    │       ├── 构造 structHash: Bid(jobId, price)
    │       ├── ecrecover(sig) → signer
    │       ├── require(signer == provider, "签名者必须等于中标者")
    │       └── 验证通过，返回
    │
    └── Escrow 设置 provider = winner
```

### EIP-712 签名结构

```solidity
// 域分隔 (Domain Separator)
EIP712Domain({
    name: "BiddingHook",
    version: "1",
    chainId: 11155111,  // Sepolia
    verifyingContract: 0x80aB74...B0809d  // BiddingHook 地址
})

// 消息结构
Bid({
    uint256 jobId,  // 任务 ID（如 46）
    uint256 price   // 报价（如 80 TTK = 80 * 10^18）
})
```

### 签名流程

1. **Provider 签名**: 在 CAW 钱包中通过 `caw sign-message` 生成 EIP-712 签名
2. **链下传递**: 签名 (65 bytes r+s+v) 被发送给 Client Agent
3. **Client 组装**: `optParams = abi.encode(sig, price)`
4. **链上验证**: `setProvider` → `BiddingHook.beforeAction` → `ecrecover` → 验证 signer == provider

### 兼容性（v3 版本）

BiddingHook v3 支持两种数据格式：
- **UNWRAPPED** (data.len ≤ 256): `abi.encode(sig, price)` — 直接由 Escrow 传递
- **WRAPPED** (data.len > 256): `abi.encode(msg.sender, provider, inner)` — 兼容旧版本

---

## 链上交易详情

### Step 1: 授权托管合约使用代币 (approve_ttk)

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x92d7543298ee7c47fecfec553c78180410764ff421c7725d9470e97df4f92d2c` |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` (CAW Client) |
| To | `0xCcb1...6cb3` (TTK Token) |
| 函数 | `approve(address,uint256)` |
| 参数 | spender=`0x5C46...dc59`, amount=100 TTK |

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x92d7543298ee7c47fecfec553c78180410764ff421c7725d9470e97df4f92d2c)

---

### Step 2: 在链上创建托管任务 (createJob)

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x9090a83d2b7dd073608d4987bcea78a1738b6719dc5139537f9cf9d772a7d39c` |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` (ERC-8183 Escrow) |
| 函数 | `createJob(address,address,uint256,string,address)` |
| 参数 | provider=`0x0`(open), evaluator=`0xf645...0d6d`, hook=`0x80aB74...B0809d`(BiddingHook) |

**事件**: `JobCreated(jobId=46, client=0x7368..., evaluator=0xf645..., hook=BiddingHook)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x9090a83d2b7dd073608d4987bcea78a1738b6719dc5139537f9cf9d772a7d39c)

---

### Step 3-4: Provider 签名报价 (链下)

| Provider | 报价 | 签名方式 |
|----------|------|---------|
| A (`0x01b7...1526`) | **80 TTK** | CAW EIP-712 sign-message ✅ |
| B (`0x7f79...c948`) | **100 TTK** | CAW EIP-712 sign-message ✅ |

两个 Provider 通过各自的未配对 CAW 钱包自动签名，无需人工审批。

---

### Step 5: LLM 比价选优 (链下)

- **Provider A**: 80 TTK ✅ **中标**
- **Provider B**: 100 TTK
- LLM 依据: 最低价原则，自动选择 Provider A

---

### Step 6: 链上锁定中标者 (setProvider EXT)

通过 BiddingHook 验证 EIP-712 签名，确保 Provider A 确实同意 80 TTK 报价。

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x2ea99dd321cdbcb1a6eb7b731c8edc49b8f3561a9bec2c009503dfae2f780abe` |
| 状态 | ✅ Success |
| From | `0x7368...41Bc` |
| To | `0x5C46...dc59` (Escrow) |
| 函数 | `setProvider(uint256,address,bytes)` (EXT) |
| 参数 | jobId=46, winner=`0x01b7...1526`, optParams=`abi.encode(sig, 80e18)` |

**内部调用链**: Escrow → `BiddingHook.beforeAction()` → `ecrecover(sig)` → 验证通过 → Escrow 设置 provider

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x2ea99dd321cdbcb1a6eb7b731c8edc49b8f3561a9bec2c009503dfae2f780abe)

---

### Step 7: 设置任务赏金预算 (setBudget)

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xedcaaac7c1087d13166d8c1bcc4b746ab35e2f6e9edee40f757aca22f7761916` |
| 状态 | ✅ Success |
| 函数 | `setBudget(uint256,uint256)` |
| 参数 | jobId=46, amount=100 TTK |

**事件**: `BudgetSet(jobId=46, amount=100000000000000000000)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xedcaaac7c1087d13166d8c1bcc4b746ab35e2f6e9edee40f757aca22f7761916)

---

### Step 8: 将赏金锁定到托管合约 (fund)

| 字段 | 值 |
|------|-----|
| Tx Hash | `0x78c635670837b53bb8c8e1edcda19879f908c0edd11495c3952be8e7c665eb3d` |
| 状态 | ✅ Success |
| 函数 | `fund(uint256,uint256)` |
| 参数 | jobId=46, expectedBudget=100 TTK |

**核心操作**: `IERC20(TTK).transferFrom(Client → Escrow, 100 TTK)`

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0x78c635670837b53bb8c8e1edcda19879f908c0edd11495c3952be8e7c665eb3d)

---

### Step 9: 服务商提交工作成果 (submit)

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xfe1ec5ab1e693cc47e6e829f8f285ba5c704402ffac8a1a1503686728342f444` |
| 状态 | ✅ Success |
| From | `0x01b7...1526` (CAW Provider A) |
| 函数 | `submit(uint256,bytes32)` |
| 参数 | jobId=46, deliverable=`0x8fc8f26a...` |

**deliverable 来源**: SHA256 哈希（基于任务内容）

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xfe1ec5ab1e693cc47e6e829f8f285ba5c704402ffac8a1a1503686728342f444)

---

### Step 10: 裁决者验收不通过，退款给客户 (reject)

| 字段 | 值 |
|------|-----|
| Tx Hash | `0xe6b2a81cd516d1deb0c5c4819baf47a89d9d5a9cc80f2e6044e19f7ab722474c` |
| 状态 | ✅ Success |
| From | `0xf645...0d6d` (CAW Evaluator) |
| 函数 | `reject(uint256,bytes32)` |
| 参数 | jobId=46, reasonHash=`0x0` |

> 🔗 [Etherscan](https://sepolia.etherscan.io/tx/0xe6b2a81cd516d1deb0c5c4819baf47a89d9d5a9cc80f2e6044e19f7ab722474c)

---

## 关键技术决策

### 1. BiddingHook EIP-712 验签

- **链下签名**: Provider 用 CAW `sign-message` 生成 EIP-712 `Bid(jobId, price)` 签名
- **链上验证**: `BiddingHook.beforeAction()` 在 `setProvider` 时自动验证
- **防伪造**: 签名由 Provider 私钥产生，Client 无法篡改报价

### 2. Pact target_in 覆盖

createJob 内部调用 `IACPHook(hook).afterAction()`，setProvider 调用 `BiddingHook.beforeAction()`。Pact 的 `target_in` 必须同时包含 Escrow 和 BiddingHook 两个合约地址，否则 CAW 策略拒绝。

```json
"target_in": [
  {"contract_addr": "{{escrow_addr}}" },   // 主合约
  {"contract_addr": "{{bidding_hook_addr}}" }  // Hook 合约（无 function_id 限制）
]
```

### 3. 跨环境钱包

| 环境 | 钱包 | 特点 |
|------|------|------|
| CLIENT (DEV) | 配对，需 CAW App 审批 Pact | approve/createJob/setBudget/fund |
| Provider (PROD) | 未配对，自动审批 | 签名报价 + submit |
| Evaluator (DEV) | 配对 | 裁决 complete/reject |

### 4. Gas 管理

Sepolia gas price 在测试期间从 ~1 gwei 飙升至 38 gwei，导致 Client 钱包余额不足：
- **修复前**: 0.00275 ETH → 仅够 approve，不够 createJob (~0.007 ETH)
- **修复后**: 向 Client 钱包转入 0.006 SETH → 余额 0.0094 ETH → 全流程通过

---

## 测试总结

| 指标 | 结果 |
|------|------|
| 总交易数 | 7 笔链上交易 ✅ |
| 总步骤数 | 10 步（含 3 步链下）✅ |
| CAW Pact 数 | Client x1 + Provider x1 + Evaluator x1 = 3 个 |
| 人工审批次数 | 0（全部自动放行）|
| BiddingHook 验签 | ✅ 通过 |
| LLM 报价选择 | ✅ 自动选最低价 |
| 最终状态 | ✅ Rejected（模拟超时退款场景） |
