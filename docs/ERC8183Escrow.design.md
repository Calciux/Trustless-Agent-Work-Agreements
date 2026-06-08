# ERC8183Escrow 工程设计文档

> 合约: `contracts/ERC8183Escrow.sol`
> 标准: EIP-8183 Agentic Commerce Protocol
> 编译器: Solidity ^0.8.21
> 许可证: MIT

---

## 目录

1. [项目概述](#1-项目概述)
2. [合约职责与依赖关系](#2-合约职责与依赖关系)
3. [状态机设计](#3-状态机设计)
4. [角色权限模型](#4-角色权限模型)
5. [存储布局](#5-存储布局)
6. [函数说明](#6-函数说明)
7. [事件说明](#7-事件说明)
8. [资金流说明](#8-资金流说明)
9. [Hook 机制说明](#9-hook-机制说明)
10. [安全考虑](#10-安全考虑)
11. [已知限制与可扩展方向](#11-已知限制与可扩展方向)
12. [与 CAW 集成方式](#12-与-caw-集成方式)

---

## 1. 项目概述

### 1.1 项目目标

ERC8183Escrow 是一个去中心化托管合约，实现 EIP-8183 (Agentic Commerce Protocol) 标准。它为 AI Agent 之间的商业协作提供不可篡改的资金托管、交付验收和争议裁决基础设施。

**核心价值**:

- **去信任化**: 资金由智能合约托管，不依赖任何中心化平台
- **角色分离**: Client（客户）、Provider（提供者）、Evaluator（裁决者）三角色权力制衡
- **完整性保证**: 任何人可在任务过期后触发退款（`claimRefund`），资金永不锁定
- **可扩展性**: Hook 机制允许在核心操作前后注入自定义逻辑（KYC/AML、声誉记录、保险等）
- **标准化**: 完全遵循 EIP-8183 接口，任何兼容客户端可直接接入

### 1.2 适用场景

- AI Agent 雇佣其他 Agent 完成任务并支付报酬
- 自由职业平台（Freelancer 类平台）的链上托管
- DAO 向外部贡献者拨款并验收交付物
- 去中心化 bounty 系统

### 1.3 技术栈

| 组件 | 技术 |
|------|------|
| 智能合约 | Solidity 0.8.21+ |
| 代币标准 | ERC-20 (任意支付代币) |
| 接口标准 | EIP-8183, ERC-165 |
| 扩展机制 | IACPHook (Agentic Commerce Protocol Hook) |
| 开发框架 | Foundry (推测) |

---

## 2. 合约职责与依赖关系

### 2.1 合约职责

```
┌─────────────────────────────────────────────────────────────┐
│                    ERC8183Escrow                             │
│                                                             │
│  1. 任务生命周期管理 (createJob → fund → submit → complete) │
│  2. 资金托管与有条件释放 (ERC-20 transferFrom/transfer)      │
│  3. 争议裁决 (reject/claimRefund)                            │
│  4. 平台手续费计算与分配 (仅在 Completed 时)                  │
│  5. Hook 扩展点管理 (beforeAction/afterAction)               │
│  6. ERC-165 接口发现 (supportsInterface)                    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 依赖关系图

```
                    ┌──────────────┐
                    │   IERC165    │  (ERC-165 接口发现)
                    └──────┬───────┘
                           │ implements
                    ┌──────▼───────┐
                    │   IERC8183   │  (EIP-8183 核心接口)
                    └──────┬───────┘
                           │ implements
              ┌────────────┼────────────┐
              │            │            │
     ┌────────▼───┐  ┌────▼─────┐  ┌───▼──────────┐
     │   IERC20   │  │ IACPHook │  │ ERC8183Escrow │
     │ (支付代币)  │  │ (Hook)   │  │  (主合约)     │
     └────────────┘  └──────────┘  └───────────────┘
```

**依赖说明**:

- **IERC20**: 部署时指定的任意 ERC-20 代币，合约通过 `transferFrom`/`transfer` 与其交互。合约不持有代币逻辑，仅作为调用方。
- **IACPHook**: 可选的外部 Hook 合约，由任务创建者在 `createJob` 时指定。如果为 `address(0)` 则不触发 Hook。
- **IERC165/IERC8183**: 接口继承链。`IERC8183` 继承 `IERC165`，主合约实现 `IERC8183`。

### 2.3 非依赖项（刻意排除）

- **不依赖 OpenZeppelin**: 从头实现修饰器和安全模式，减少外部依赖和审计面
- **不依赖 Ownable**: 使用自定义 `owner` immutable + `onlyOwner` 修饰器
- **不依赖 ReentrancyGuard**: 使用自定义 `_locked` bool + `nonReentrant` 修饰器

---

## 3. 状态机设计

### 3.1 状态枚举

```solidity
enum Status { Open, Funded, Submitted, Completed, Rejected, Expired }
//             0     1        2          3         4        5
```

### 3.2 状态转换图 (ASCII)

```
                         ┌──────────────┐
                         │              │
                   ┌─────┤     Open     │◄──────────── setProvider
                   │     │    (初始)    │◄──────────── setBudget
                   │     └──────┬───────┘
                   │            │
          createJob│            │ fund (客户注资 + transferFrom)
                   │            ▼
                   │     ┌──────────────┐
                   │     │    Funded    │──────────────┐
                   │     │  (资金托管)   │              │
                   │     └──────┬───────┘              │
                   │            │                      │
                   │            │ submit (提供者提交)    │ claimRefund
                   │            ▼                      │ (过期→任何人)
                   │     ┌──────────────┐              │
                   │     │  Submitted   │──────────────┤
                   │     │  (等待裁决)   │              │
                   │     └──┬──────┬────┘              │
                   │        │      │                   │
           reject  │  complete   reject                │
           (Client)│ (Evaluator)(Evaluator)            │
                   │        │      │                   │
                   ▼        ▼      ▼                   ▼
              ┌────────┐┌─────────┐┌─────────┐┌──────────┐
              │Rejected││Completed││Rejected ││ Expired  │
              │ (终态) ││ (终态)  ││ (终态)  ││ (终态)   │
              └────────┘└─────────┘└─────────┘└──────────┘
               无退款     放款       退款       全额退款
                         +手续费    (全额)     (全额)
```

### 3.3 状态转换表

| 当前状态 | 操作 | 调用者 | 目标状态 | 资金变化 | Hook |
|---------|------|--------|---------|---------|------|
| (不存在) | `createJob` | 任何人 | Open | — | 否 |
| Open | `setProvider` | Client | Open | — | 是 |
| Open | `setBudget` | Client/Provider | Open | — | 是 |
| Open | `fund` | Client | Funded | Client→Escrow (transferFrom) | 是 |
| Open | `reject` | Client | Rejected | 无 | 是 |
| Funded | `submit` | Provider | Submitted | — | 是 |
| Funded | `reject` | Evaluator | Rejected | Escrow→Client (退款) | 是 |
| Funded | `claimRefund` | 任何人 | Expired | Escrow→Client (退款) | 否 |
| Submitted | `complete` | Evaluator | Completed | Escrow→Provider (放款-手续费) + Escrow→Treasury (手续费) | 是 |
| Submitted | `reject` | Evaluator | Rejected | Escrow→Client (退款) | 是 |
| Submitted | `claimRefund` | 任何人 | Expired | Escrow→Client (退款) | 否 |
| Completed | — | — | 终态 | — | — |
| Rejected | — | — | 终态 | — | — |
| Expired | — | — | 终态 | — | — |

**重要约束**:

- `reject` 具有三种调用路径，需分别检查权限（Open→Client, Funded/Submitted→Evaluator）
- `claimRefund` 无权限限制（任何人），但需过期条件
- `Completed` 是唯一产生手续费的路径

---

## 4. 角色权限模型

### 4.1 角色定义

```
┌──────────────────────────────────────────────────────────┐
│                      角色权限矩阵                          │
├──────────────┬──────────────────────────────────────────┤
│     Owner    │  部署者，不可转让                          │
│              │  - setTreasury (修改手续费地址)             │
│              │  - setFeeBps (修改费率)                    │
├──────────────┼──────────────────────────────────────────┤
│    Client    │  任务创建者 (msg.sender of createJob)      │
│              │  - setProvider (Open, 一次)                │
│              │  - setBudget (Open, 可反复)                │
│              │  - fund (Open, 需 budget+provider 已设)    │
│              │  - reject (仅 Open 状态)                   │
│              │  - claimRefund (任何人可调, 不限于 Client)  │
├──────────────┼──────────────────────────────────────────┤
│   Provider   │  服务提供者                                │
│              │  - setBudget (Open, 可反复)                │
│              │  - submit (Funded)                         │
│              │  - 收款 (Completed 后自动)                  │
├──────────────┼──────────────────────────────────────────┤
│  Evaluator   │  裁决者                                    │
│              │  - complete (Submitted)                    │
│              │  - reject (Funded/Submitted)               │
├──────────────┼──────────────────────────────────────────┤
│    Anyone    │  任何地址                                  │
│              │  - claimRefund (过期后, 仅 Funded/Submitted)│
└──────────────┴──────────────────────────────────────────┘
```

### 4.2 权限设计理由

**为什么 Provider 也能设置 Budget？**

EIP-8183 将预算设置视为协商过程。提供者可以在看到任务后提议不同价格，客户可选择接受（fund）或拒绝（reject）。`fund` 时的 `expectedBudget` 参数保护客户不被恶意修改预算。

**为什么 Evaluator 权力这么大？**

裁决者是可信第三方（可能是 DAO 委员会、仲裁合约、或双方共同指定的可信个体）。在争议情况下（客户想拒付 vs 提供者已交付），由裁决者做最终判断。这是"乐观执行 + 争议仲裁"模式的基础。

**为什么 Owner 权力有限？**

Owner 只能修改收费参数（`treasury`、`feeBps`），不能操作任何任务或资金。这限制了合约部署者的特权，增强了去中心化程度。

---

## 5. 存储布局

### 5.1 存储变量详细布局

| Slot | 变量 | 类型 | 可见性 | 特殊属性 | 说明 |
|------|------|------|--------|---------|------|
| — | `MAX_FEE_BPS` | `uint256` | `public` | `constant` | 不占 storage，编译时替换为 10000 |
| — | `owner` | `address` | `public` | `immutable` | 不占 storage，存储在合约字节码中 |
| — | `_paymentToken` | `IERC20` | `private` | `immutable` | 不占 storage，存储在合约字节码中 |
| 0 | `treasury` | `address` | `public` | — | 20 字节（占 slot 0 前半） |
| 1 | `feeBps` | `uint256` | `public` | — | 32 字节（独立 slot） |
| 2 | `_jobCounter` | `uint256` | `private` | — | 任务自增计数器 |
| 3 | `_jobs` | `mapping(uint256 => Job)` | `private` | — | mapping 占位 slot（实际数据存储在 keccak256(key . slot)） |
| 4 | `_locked` | `bool` | `private` | — | 防重入锁（1 字节，独占 slot 4） |

### 5.2 mapping 存储设计

`mapping(uint256 => Job)` 的实际存储位置计算公式：

```
storage_location = keccak256(abi.encode(jobId, 3))
// 3 是 _jobs 声明的 slot 编号
```

每个 `Job` 结构体值连续占用多个 slot:

```
Job 结构体存储 (从 storage_location 开始):
Offset 0:  client      (address, 20 bytes, slot N)
Offset 0:  provider    (address, 20 bytes, slot N+1)
Offset 0:  evaluator   (address, 20 bytes, slot N+2)
Offset 0:  description (string, 动态长度 — 短字符串 ≤31 字节存在 slot N+3, 超长存 pointer)
Offset 0:  budget      (uint256, 32 bytes, slot N+4)
Offset 0:  expiredAt   (uint256, 32 bytes, slot N+5)
Offset 0:  status      (enum Status → uint8, slot N+6 — 末尾可能打包 hook)
Offset 0:  hook        (address, slot N+6 或 N+7，取决于与 status 的打包)
```

### 5.3 存储设计理由

**为什么不用数组而用 mapping？**

- `mapping` 支持稀疏存储（jobId 可不连续），不浪费 slot
- `mapping` 的读取是 O(1) 且恒定 gas
- 数组在删除元素时需要维护顺序（或留下空洞），增加复杂度
- 配合 `_jobCounter` 自增 ID，`mapping` 能有效支持边界校验（`jobId > 0 && jobId <= _jobCounter`）

**为什么 `_locked` 独占一个 slot？**

`bool` 仅占 1 字节，理论上可以与 `_jobCounter` 打包到同一 slot（Solidity 编译器会自动优化相邻值类型的打包）。但在实际编译中，`_jobCounter` (uint256) 占满整个 slot，`_locked` 只能放在下一个 slot。考虑未来可将其与新增变量打包。

---

## 6. 函数说明

### 6.1 函数总览

| # | 函数 | 调用者 | 所需状态 | 修改状态 | Hook | 资金操作 |
|---|------|--------|---------|---------|------|---------|
| 1 | `createJob` | 任何人 | (不存在) | → Open | 否 | — |
| 2 | `setProvider` | Client | Open | Open (不变) | 是 | — |
| 3 | `setBudget` | Client/Provider | Open | Open (不变) | 是 | — |
| 4 | `fund` | Client | Open | → Funded | 是 | transferFrom(Client→Escrow) |
| 5 | `submit` | Provider | Funded | → Submitted | 是 | — |
| 6 | `complete` | Evaluator | Submitted | → Completed | 是 | transfer(Escrow→Provider) + transfer(Escrow→Treasury) |
| 7 | `reject` | Client(Open) 或 Evaluator(Funded/Submitted) | Open/Funded/Submitted | → Rejected | 是 | transfer(Escrow→Client) [仅Funded/Submitted] |
| 8 | `claimRefund` | 任何人 | Funded/Submitted | → Expired | 否 | transfer(Escrow→Client) |

### 6.2 各函数详解

#### 6.2.1 createJob

```
签名: createJob(address provider, address evaluator, uint256 expiredAt, string calldata description, address hook)
       returns (uint256 jobId)

权限:    无限制 (Permissionless)
revert 条件:
  - evaluator == address(0)
  - expiredAt <= block.timestamp

行为:
  1. 校验 evaluator 非零、expiredAt 在未来
  2. jobId = ++_jobCounter (从 1 开始自增)
  3. 初始化 Job 结构体 (budget=0, status=Open)
  4. emit JobCreated

optParams: 不支持 (创建时 Hook 无上下文)
Gas 成本: ~120,000 (首次写入 storage 较昂贵)
```

#### 6.2.2 setProvider

```
签名: setProvider(uint256 jobId, address provider [, bytes calldata optParams])

权限:    onlyClient
revert 条件:
  - job.provider != address(0) (已设置过)
  - provider == address(0)
  - job.status != Open

行为:
  1. Hook: beforeAction
  2. job.provider = provider
  3. emit ProviderSet
  4. Hook: afterAction

注意: 提供者只能设置一次（不可变更）
```

#### 6.2.3 setBudget

```
签名: setBudget(uint256 jobId, uint256 amount [, bytes calldata optParams])

权限:    msg.sender == job.client || msg.sender == job.provider
revert 条件:
  - job.status != Open
  - 调用者既非 Client 也非 Provider

行为:
  1. Hook: beforeAction
  2. job.budget = amount (可反复覆盖)
  3. emit BudgetSet
  4. Hook: afterAction

安全注意: budget 可被反复设置，fund 时由 expectedBudget 锁定最终值
```

#### 6.2.4 fund

```
签名: fund(uint256 jobId, uint256 expectedBudget [, bytes calldata optParams])

权限:    onlyClient
revert 条件:
  - job.status != Open
  - job.budget == 0
  - job.provider == address(0)
  - job.budget != expectedBudget (防 front-run)
  - transferFrom 失败 (余额不足或未 approve)

行为:
  1. 三重校验 (budget>0, provider已设, expectedBudget匹配)
  2. Hook: beforeAction
  3. job.status = Funded (先改状态)
  4. transferFrom(Client → 本合约, budget)
  5. emit JobFunded
  6. Hook: afterAction

关键安全: expectedBudget 防止 MEV 抢跑篡改预算
前置条件: Client 需先 approve(本合约, budget) 给支付代币合约
```

#### 6.2.5 submit

```
签名: submit(uint256 jobId, bytes32 deliverable [, bytes calldata optParams])

权限:    onlyProvider
revert 条件:
  - job.status != Funded

行为:
  1. Hook: beforeAction
  2. job.status = Submitted
  3. emit JobSubmitted(jobId, provider, deliverable)
  4. Hook: afterAction

deliverable: bytes32 哈希，通常是链下交付物的内容哈希
```

#### 6.2.6 complete

```
签名: complete(uint256 jobId, bytes32 reason [, bytes calldata optParams])

权限:    onlyEvaluator
revert 条件:
  - job.status != Submitted
  - transfer(Provider) 失败
  - transfer(Treasury) 失败 (如果 fee > 0)

行为:
  1. Hook: beforeAction
  2. job.status = Completed
  3. 快照 budget + provider
  4. 计算手续费 (如果 treasury != address(0) && feeBps > 0):
     fee = budget * feeBps / 10000
     payAmount = budget - fee
  5. transfer(Provider, payAmount)
  6. if fee > 0: transfer(Treasury, fee)
  7. emit JobCompleted + PaymentReleased
  8. Hook: afterAction

手续费: 仅此路径产生手续费。Rejected/Expired 全额退款
```

#### 6.2.7 reject

```
签名: reject(uint256 jobId, bytes32 reason [, bytes calldata optParams])

权限:    分状态:
  - Open: 仅 Client
  - Funded/Submitted: 仅 Evaluator
  - Completed/Rejected/Expired: revert (终态)

revert 条件:
  - 权限不匹配
  - 不支持的当前状态
  - 退款时 transfer 失败

行为:
  1. 读取 currentStatus
  2. 分状态权限检查 (非标准修饰器，在函数体内 if/else 实现)
  3. Hook: beforeAction
  4. job.status = Rejected
  5. 若 currentStatus == Funded/Submitted:
     transfer(Escrow → Client, budget)  (全额退款)
     emit Refunded
  6. emit JobRejected
  7. Hook: afterAction

注意: Open 状态 reject 不涉及资金，仅状态变更
```

#### 6.2.8 claimRefund

```
签名: claimRefund(uint256 jobId)

权限:    无限制 (任何人)
revert 条件:
  - job.status 不是 Funded 或 Submitted
  - block.timestamp < job.expiredAt
  - transfer 失败

行为:
  1. 校验状态 (Funded/Submitted) + 过期条件
  2. job.status = Expired
  3. transfer(Escrow → Client, budget)  (全额退款)
  4. emit JobExpired + Refunded
  5. 故意不调用 Hook

安全设计: 不经过 Hook 确保退款路径永不阻塞
```

### 6.3 查询函数

| 函数 | 返回 | 说明 |
|------|------|------|
| `supportsInterface(bytes4)` | `bool` | ERC-165 接口检测 |
| `paymentToken()` | `address` | 支付代币合约地址 |
| `getJob(uint256)` | `Job memory` | 完整任务信息 |
| `getStatus(uint256)` | `Status` | 任务当前状态 |
| `jobCount()` | `uint256` | 任务总数 |

### 6.4 管理函数

| 函数 | 权限 | 说明 |
|------|------|------|
| `setTreasury(address)` | `onlyOwner` | 更新手续费接收地址（可设 0 停收费） |
| `setFeeBps(uint256)` | `onlyOwner` | 更新手续费费率（≤ 10000） |

---

## 7. 事件说明

### 7.1 事件总览

| # | 事件 | 触发函数 | indexed 参数 | 非 indexed 参数 |
|---|------|---------|-------------|----------------|
| 1 | `JobCreated` | `createJob` | jobId, client, provider | evaluator, expiredAt |
| 2 | `ProviderSet` | `setProvider` | jobId, provider | — |
| 3 | `BudgetSet` | `setBudget` | jobId, amount | — |
| 4 | `JobFunded` | `fund` | jobId, client | amount |
| 5 | `JobSubmitted` | `submit` | jobId, provider | deliverable |
| 6 | `JobCompleted` | `complete` | jobId, evaluator | reason |
| 7 | `JobRejected` | `reject` | jobId, rejector | reason |
| 8 | `JobExpired` | `claimRefund` | jobId | — |
| 9 | `PaymentReleased` | `complete` | jobId, provider | amount |
| 10 | `Refunded` | `reject`, `claimRefund` | jobId, client | amount |

### 7.2 事件设计理由

**为什么 Completed 时有两个事件？**

`JobCompleted` 记录裁决确认，`PaymentReleased` 记录实际付款金额。由于手续费的存在，`PaymentReleased.amount` ≠ `budget`。分离事件使链下索引更清晰。

**为什么 Refunded 复用而非独立事件？**

`Rejected` (Funded/Submitted) 和 `Expired` 都产生退款，使用同一个 `Refunded` 事件简化 DApp 前端的事件订阅。结合 `JobRejected` 或 `JobExpired` 可区分退款原因。

**为什么 amount/budget 有时 indexed 有时不 indexed？**

Ethereum 事件最多 3 个 `indexed` 参数。`uint256` 类型作为 indexed 参数存储为 `bytes32`（哈希），无法直接过滤数值范围（只能过滤精确值）。对于金额类参数，非 indexed 反而更适合链下处理。

---

## 8. 资金流说明

### 8.1 资金流动全景

```
                        ┌──────────────────────────┐
                        │     ERC-20 支付代币        │
                        └──────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │ approve      │ transferFrom │ transfer
                    ▼              ▼              ▼
              ┌──────────┐  ┌───────────────────────┐
              │ Client   │  │  ERC8183Escrow (本合约) │
              │ 钱包     │──▶ 托管资金               │
              └──────────┘  └───┬───────┬───────┬───┘
                                │       │       │
                     complete   │reject │expire │
                     (放款)     │(退款) │(退款) │
                                ▼       ▼       ▼
                          ┌─────────┐ ┌──────────┐
                          │Provider │ │ Client   │
                          │(扣手续费)│ │(全额退款) │
                          └─────────┘ └──────────┘
                                │
                          ┌─────▼─────┐
                          │ Treasury  │
                          │ (手续费)  │
                          └───────────┘
```

### 8.2 各路径资金明细

#### 路径 A: 正常完成 (Complete)

```
资金源:    Client 钱包
托管:     fund() → transferFrom(Client, Escrow, budget)  ← Client 预授权
放款:     complete() → transfer(Escrow, Provider, budget - fee)
手续费:   complete() → transfer(Escrow, Treasury, fee)     ← 仅此路径
手续费 = budget * feeBps / 10000

示例: budget=1000 USDC, feeBps=250 (2.5%)
  → fee = 25, Provider 收 975, Treasury 收 25
```

#### 路径 B: 争议拒绝 (Reject in Funded/Submitted)

```
资金源:    Client 钱包
托管:     fund() → transferFrom(Client, Escrow, budget)
退款:     reject() → transfer(Escrow, Client, budget)  ← 全额退款
手续费:   0 (不收费)
```

#### 路径 C: 过期退款 (claimRefund)

```
资金源:    Client 钱包
托管:     fund() → transferFrom(Client, Escrow, budget)
退款:     claimRefund() → transfer(Escrow, Client, budget)  ← 全额退款, 无 Hook
手续费:   0 (不收费)
```

#### 路径 D: 客户取消 (Reject in Open)

```
资金源:    无 (尚未 fund)
托管:     无
退款:     无
手续费:   无
```

### 8.3 手续费设计决策

| 决策 | 理由 |
|------|------|
| 仅在 Completed 时扣除 | 平台仅在交易成功时获益，与用户利益一致 |
| 拒绝/过期全额退款 | 争议和超时场景不应被平台抽成，降低用户风险 |
| 支持零手续费 | `treasury=address(0)` 或 `feeBps=0` 完全停用收费 |
| 费率可调整 | 部署者可通过 `setFeeBps` 调整（≤100%） |
| 用基点 (bps) | 行业标准精度（1 bps = 0.01%），Solidity 无浮点数 |

---

## 9. Hook 机制说明

### 9.1 Hook 接口

```solidity
interface IACPHook {
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
```

### 9.2 Hook 调用流程

```
User calls fund(jobId, expectedBudget, optParams)
         │
         ▼
    _fund(jobId, expectedBudget, optParams, SEL_FUND_EXT)
         │
         ├── [1] Checks: 修饰器 + require 校验
         │
         ├── [2] _callBeforeHook(hook, jobId, SEL_FUND_EXT, optParams)
         │       └── if hook != address(0): IACPHook(hook).beforeAction(...)
         │
         ├── [3] Effects: job.status = Funded
         │
         ├── [4] Interactions: transferFrom(...)
         │
         ├── [5] emit JobFunded(...)
         │
         └── [6] _callAfterHook(hook, jobId, SEL_FUND_EXT, optParams)
                 └── if hook != address(0): IACPHook(hook).afterAction(...)
```

### 9.3 选择器路由机制

Hook 合约通过 `selector` 参数识别当前操作：

| 调用 | 选择器常量 | 值 (前4字节) |
|------|-----------|-------------|
| `setProvider(jobId, provider)` | `SEL_SETPROVIDER` | `keccak256("setProvider(uint256,address)")[:4]` |
| `setProvider(jobId, provider, optParams)` | `SEL_SETPROVIDER_EXT` | `keccak256("setProvider(uint256,address,bytes)")[:4]` |
| ... | ... | ... |

Hook 合约内部可以根据 `selector` 执行不同逻辑：

```solidity
// Hook 合约示例伪代码
function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external {
    if (selector == SEL_FUND) {
        // KYC 检查: 验证客户是否在白名单
        require(isKYCed(msg.sender), "KYC required");
    } else if (selector == SEL_COMPLETE) {
        // 声誉记录: 记录成功完成任务
        recordReputation(jobId);
    }
}
```

### 9.4 claimRefund 排除 Hook 的设计理由

```
┌──────────────────────────────────────────────────────────────┐
│          为什么 claimRefund 不经过 Hook？                      │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 退款通路是安全底线                                        │
│     - 如果 Hook 可阻断 claimRefund，恶意 Hook 能永久锁死资金   │
│     - 类比：OpenZeppelin PullPayment 不依赖外部调用            │
│                                                              │
│  2. 过期退款是自动执行机制                                     │
│     - 不依赖任何参与方的合作                                   │
│     - Hook 的存在不应改变这个属性                              │
│                                                              │
│  3. EIP-8183 协议级要求                                       │
│     - 标准明确：claimRefund MUST NOT invoke hooks             │
│     - 保证所有合规实现的互操作性                                │
│                                                              │
│  4. 退款已无业务逻辑需要 Hook                                  │
│     - 过期意味着任务失败，无需再执行 KYC/声誉等业务逻辑         │
│     - beforeAction/afterAction 在此场景下无意义               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 9.5 Hook 安全考量

| 风险 | 缓解措施 |
|------|---------|
| Hook revert 导致核心操作失败 | 这是设计意图：Hook 作为准入控制，revert 否决操作 |
| Hook 重入托管合约 | `nonReentrant` 锁阻止所有重入 |
| Hook 消耗异常多 gas | 调用者承担 gas；若无 Hook 则 `if hook != address(0)` 跳过 |
| Hook 地址不可变更 | 在 `createJob` 时确定，这是简化设计 |

---

## 10. 安全考虑

### 10.1 重入攻击防护

**采用方案**: 自定义 `nonReentrant` 修饰器（互斥锁模式）

```
      nonReentrant 修饰器
      ┌────────────────────┐
      │ require(!_locked)  │ ← 入口守卫
      │ _locked = true     │ ← 加锁
      │ _;                 │ ← 执行函数体 (含 Hook 调用)
      │ _locked = false    │ ← 解锁
      └────────────────────┘
```

**防护范围**: 所有会触发 Hook 的核心函数（`_setProvider`, `_setBudget`, `_fund`, `_submit`, `_complete`, `_reject`）+ `claimRefund`。

**局限**: 这是单锁（非计数锁），无法处理同函数中多次调用 Hook 的场景（实际上 Hook 只在 before/after 各调用一次，无此需要）。

### 10.2 前端抢跑防护 (Front-running)

**攻击场景**: 
1. Client 调用 `setBudget(jobId, 100)` 后准备调用 `fund(jobId, 100)`
2. Provider 观测到 mempool 中的 `fund` 交易，提前发送 `setBudget(jobId, 1000000)` 
3. 如果 `fund` 不校验预算，客户将以篡改后的 1000000 注资

**防护方案**: `fund(jobId, expectedBudget)` 参数

```
require(job.budget == expectedBudget, "ERC8183: budget mismatch");
```

客户签名 `fund` 时指定期望的预算值。如果链上预算被篡改，交易 revert。攻击失败。

### 10.3 checks-effects-interactions 模式

所有涉及外部调用的函数均遵循此模式：

```
1. require 校验 (Checks)
2. 状态修改 (Effects) — 在所有外部调用之前
3. 外部调用 (Interactions) — transfer/transferFrom/Hook
```

**示例: `_fund` 函数**
```
[Checks]  require(budget > 0), require(provider != address(0)), require(budget == expectedBudget)
[Effects] job.status = Status.Funded
[Interactions] transferFrom(...), emit events, Hook calls
```

### 10.4 ERC-20 兼容性

**安全实践**:
- 使用 `require(transferFrom(...), ...)` 检查返回值 — 兼容不 revert 的 ERC-20（如 USDT 旧版返回 false 而非 revert）
- 使用 `require(transfer(...), ...)` 同样检查返回值
- 不假设 ERC-20 的 `transfer`/`transferFrom` 一定 revert 失败

**非标准 ERC-20 风险**: 
- 代币有转账手续费（deflationary tokens）→ 实际到账少于 `budget`，合约余额不足——下笔 `transfer` 会失败
- 代币可暂停（pausable tokens）→ `transferFrom` 可能随时失败，阻塞正常流程
- **建议**: 部署时选择标准、不可暂停的支付代币（如 USDC、DAI）

### 10.5 权限分离

```
角色分离原则:
┌──────────┬───────────────────────────────────┐
│ Owner    │ 只管理收费，不操作任务，不碰资金    │
│ Client   │ 创建/注资，不能单方面撤资(已注资后) │
│ Provider │ 提交交付，不能自审自放款            │
│ Evaluator│ 裁决确认，不能创建或注资            │
└──────────┴───────────────────────────────────┘
```

**关键防护**: Client 在 Funded/Submitted 状态不能 refuse——必须由 Evaluator 裁决。防止客户"白嫖"（拿到交付物后拒绝付款）。

---

## 11. 已知限制与可扩展方向

### 11.1 已知限制

| 限制 | 影响 | 可能改进 |
|------|------|---------|
| Hook 地址在 createJob 时固定 | 任务运行中无法更换 Hook | 添加 `setHook(uint256 jobId, address hook)` 函数 |
| Provider 只能设置一次 | 原 Provider 作恶时无法替换 | 添加 Provider 替换机制（需 Evaluator 确认） |
| Evaluator 权力集中 | 单点故障/作恶风险 | 支持多签 Evaluator 或争议升级合约 |
| 手续费固定比例 | 无法支持阶梯费率/大额折扣 | 添加多级费率或外部费率预言机 |
| description 存储在链上 | 长文本 gas 成本高 | 改为仅存 IPFS CID/内容哈希 |
| deliverable 仅为 bytes32 | 无法存储复杂交付物结构 | 扩展为 `struct Deliverable { bytes32 hash; string uri; uint256 timestamp; }` |
| 无原生支持分期付款 | 一次注资，一次放款 | 添加 milestone（里程碑）子任务 |
| 无超时自动完成机制 | 提供者提交后裁决者可能不响应 | 添加裁决超时后自动 complete/reject |

### 11.2 可扩展方向

#### A. Hook 生态

```
┌─────────────────────────────────────────────────────┐
│                 可构建的 Hook 示例                    │
├─────────────────────────────────────────────────────┤
│ KYC/AML Hook        │ 检查参与者是否通过身份验证     │
│ Reputation Hook     │ 记录任务完成情况，更新声誉分   │
│ Insurance Hook      │ 任务失败时触发保险赔付         │
│ Dispute Escalation  │ 争议自动升级到 DAO 投票        │
│ Multi-Sig Evaluator │ Evaluator 变成多签合约         │
│ Time-locked Release │ 延迟放款（给客户反悔窗口）      │
│ Automated Testing   │ 提交前自动验证交付物           │
└─────────────────────────────────────────────────────┘
```

#### B. 治理集成

- Fee 参数可通过 DAO 投票治理（将 Owner 替换为 Governance 合约）
- Evaluator 可由 DAO 选举产生
- 争议处理可接入 Kleros/Aragon Court 等去中心化仲裁

#### C. 跨链扩展

- 使用 LayerZero/Chainlink CCIP 实现跨链托管
- Provider 在链 A 提交，Client 在链 B 付款

---

## 12. 与 CAW 集成方式

### 12.1 CAW 是什么

CAW (Trustless Agent Work Agreements) 是一个去中心化 AI Agent 协作平台，基于 EIP-8183 标准构建。ERC8183Escrow 是 CAW 平台的核心托管合约。

### 12.2 集成架构

```
┌──────────────────────────────────────────────────────────┐
│                     CAW 平台层                            │
│                                                          │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐  │
│  │ AI Agent │  │ AI Agent  │  │   DApp / Frontend    │  │
│  │ (Client) │  │ (Provider)│  │ (链下界面)            │  │
│  └────┬─────┘  └─────┬─────┘  └──────────┬───────────┘  │
│       │              │                    │              │
│       │   ┌──────────┴────────────────────┘              │
│       │   │  通过 ethers.js / viem / wagmi 调用          │
│       ▼   ▼                                             │
│  ┌──────────────────────────────────────────────────┐   │
│  │            ERC8183Escrow (链上托管)               │   │
│  │  - createJob / setProvider / setBudget            │   │
│  │  - fund / submit / complete / reject              │   │
│  │  - claimRefund                                    │   │
│  └──────────────────────────────────────────────────┘   │
│       │                                                  │
│       │ 可选                                              │
│       ▼                                                  │
│  ┌──────────────────────────────────────────────────┐   │
│  │            IACPHook (自定义 Hook)                 │   │
│  │  - ReputationHook (声誉系统)                      │   │
│  │  - KYC Hook (身份验证)                            │   │
│  │  - Testing Hook (交付物自动验证)                   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 12.3 Agent 交互流程

```
1. Client Agent 发现 Provider Agent (通过链下注册表/声誉系统)
       │
2. Client Agent 调用 createJob (链上)
       │  - 指定 provider, evaluator, budget, 过期时间
       │  - 可选指定 Hook (如 ReputationHook)
       ▼
3. Client/Provider Agent 协商 setBudget (链上, 可选反复)
       │
4. Client Agent 调用 fund (链上)
       │  - 先 approve ERC-20 给托管合约
       │  - 传入 expectedBudget 防抢跑
       ▼
5. Provider Agent 完成任务 (链下)
       │  - AI 推理、计算、生成内容等
       │  - 产出交付物 (存储到 IPFS/Arweave)
       ▼
6. Provider Agent 调用 submit (链上)
       │  - 传入 deliverable = keccak256(交付物哈希)
       ▼
7. Evaluator Agent 验证交付物 (链下+链上)
       │  - 检查交付物是否满足要求
       │  - 调用 complete 或 reject
       ▼
8a. complete → PaymentReleased (Provider 收款)
8b. reject → Refunded (Client 退款)
8c. 超时 → claimRefund (任何人触发退款)
```

### 12.4 关键集成点

| 集成点 | 说明 |
|--------|------|
| **gas 支付** | Agent 需要 ETH/MATIC 等原生代币支付 gas fee。CAW 平台可提供 gas 代付服务 |
| **ERC-20 approve** | Client Agent 在 `fund` 前需调用 `IERC20.approve(escrowAddress, budget)` |
| **事件监听** | Agent 通过 WebSocket/轮询监听合约事件，获知状态变更 |
| **Hook 扩展** | 平台可部署自定义 Hook 合约注入声誉记录、自动测试等逻辑 |
| **过期处理** | Agent 应监控 `expiredAt`，及时调用 `claimRefund` 或提醒人类介入 |

---

## 附录 A: 函数选择器速查表

| 函数签名 | 4 字节选择器 (hex) |
|---------|-------------------|
| `createJob(address,address,uint256,string,address)` | 动态计算 |
| `setProvider(uint256,address)` | 编译时常量 |
| `setProvider(uint256,address,bytes)` | 编译时常量 |
| `setBudget(uint256,uint256)` | 编译时常量 |
| `setBudget(uint256,uint256,bytes)` | 编译时常量 |
| `fund(uint256,uint256)` | 编译时常量 |
| `fund(uint256,uint256,bytes)` | 编译时常量 |
| `submit(uint256,bytes32)` | 编译时常量 |
| `submit(uint256,bytes32,bytes)` | 编译时常量 |
| `complete(uint256,bytes32)` | 编译时常量 |
| `complete(uint256,bytes32,bytes)` | 编译时常量 |
| `reject(uint256,bytes32)` | 编译时常量 |
| `reject(uint256,bytes32,bytes)` | 编译时常量 |
| `claimRefund(uint256)` | 动态计算 |

## 附录 B: 错误消息速查表

| 错误消息 | 触发条件 |
|---------|---------|
| `ERC8183: reentrant call` | 重入调用（nonReentrant） |
| `ERC8183: caller is not owner` | 非部署者调用管理函数 |
| `ERC8183: caller is not client` | 非客户调用 onlyClient 函数 |
| `ERC8183: caller is not provider` | 非提供者调用 onlyProvider 函数 |
| `ERC8183: caller is not evaluator` | 非裁决者调用 onlyEvaluator 函数 |
| `ERC8183: invalid job status` | 状态不匹配（onlyStatus） |
| `ERC8183: payment token zero address` | 构造时 paymentToken=address(0) |
| `ERC8183: fee too high` | feeBps > 10000 |
| `ERC8183: evaluator is zero address` | createJob 时 evaluator=address(0) |
| `ERC8183: expiredAt not in future` | createJob 时 expiredAt ≤ now |
| `ERC8183: provider already set` | provider 已被设置 |
| `ERC8183: provider is zero address` | setProvider 传入 address(0) |
| `ERC8183: caller not client or provider` | setBudget 调用者非双方 |
| `ERC8183: budget not set` | fund 时 budget=0 |
| `ERC8183: provider not set` | fund 时 provider=address(0) |
| `ERC8183: budget mismatch` | fund 的 expectedBudget 不匹配 |
| `ERC8183: transferFrom failed` | ERC-20 转账失败 |
| `ERC8183: payment transfer failed` | complete 付款失败 |
| `ERC8183: fee transfer failed` | 手续费转账失败 |
| `ERC8183: refund transfer failed` | 退款转账失败 |
| `ERC8183: job not found` | getJob/getStatus 的 jobId 无效 |
| `ERC8183: job not in refundable state` | claimRefund 状态不符 |
| `ERC8183: job not expired` | claimRefund 时尚未过期 |
| `ERC8183: invalid job status for reject` | reject 时状态不可拒绝 |

---

*文档生成时间: 2026-06-07*
*合约版本: ERC8183Escrow (EIP-8183)*
