# ERC-8183 Escrow — 完整集成测试清单

> **生成者**：Plan Agent（仅设计，不写测试代码）
> **被测合约**：`contracts/ERC8183Escrow.sol`（516 行，solc `0.8.21`，EVM `shanghai`）
> **已有覆盖**：104 单元测试（UT-001~UT-104）✅ + 2 Happy Path 集成（IT-001/IT-002）✅
> **本清单覆盖**：Happy Path 之外的所有跨函数用户旅程（IT-003 ~ IT-022，共 20 用例）
> **参考接口**：`contracts/interfaces/IERC8183.sol`（6 状态枚举）、`contracts/interfaces/IACPHook.sol`

---

## 1. 覆盖矩阵总览

| 场景类别 | 用例数 | P0 | P1 | P2 | ID 范围 |
|----------|--------|----|----|-----|---------|
| Reject（拒绝路径） | 5 | 4 | 1 | 0 | IT-003 ~ IT-007 |
| Expire（过期路径） | 5 | 3 | 1 | 1 | IT-008 ~ IT-012 |
| Hook（Hook 交互） | 2 | 2 | 0 | 0 | IT-013 ~ IT-014 |
| Reentry（跨函数重入） | 2 | 2 | 0 | 0 | IT-015 ~ IT-016 |
| MultiJob（多 Job 并存） | 3 | 2 | 1 | 0 | IT-017 ~ IT-019 |
| Edge（边界集成） | 3 | 1 | 2 | 0 | IT-020 ~ IT-022 |
| **总计** | **20** | **14** | **5** | **1** | |

---

## 2. 完整测试清单

### A. 拒绝路径（Reject）

#### IT-003：Client rejects in Open（无 provider，无 budget，无资金托管）

| 属性 | 内容 |
|------|------|
| **场景类别** | Reject |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow（any treasury/fee），Client mint 1000 token |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → reject(1, reason=bytes32("no"), sender=Client)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | createJob 后 | `jobId=1`，`getStatus(1)=Open`，`getJob(1).client=Client`，`getJob(1).provider=address(0)`，`getJob(1).budget=0` |
| 2 | reject 后 | `getStatus(1)=Rejected` |
| 3 | reject 后 | emit `JobRejected(1, Client, bytes32("no"))` |
| 4 | reject 后 | **不发射** `Refunded` 事件（无托管资金，无退款） |
| 5 | reject 后 | `token.balanceOf(Escrow)=0`（合约余额从未变化） |
| 6 | reject 后 | `token.balanceOf(Client)=1000`（Client 余额从未减少） |

**合约依据**：`_reject()` L430-432 — Open 状态下 `shouldRefund=false`，跳过退款逻辑。

---

#### IT-004：Client rejects in Open（provider + budget 已设，但未 fund）

| 属性 | 内容 |
|------|------|
| **场景类别** | Reject |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow，Client mint 1000 token |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → reject(1, reason=bytes32("changed mind"), sender=Client)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | setProvider 后 | `getJob(1).provider=provider`，emit `ProviderSet(1, provider)` |
| 2 | setBudget 后 | `getJob(1).budget=500`，emit `BudgetSet(1, 500)` |
| 3 | reject 后 | `getStatus(1)=Rejected` |
| 4 | reject 后 | emit `JobRejected(1, Client, bytes32("changed mind"))` |
| 5 | reject 后 | **不发射** `Refunded`（budget 仅为链上数字，资金从未转入合约） |
| 6 | reject 后 | `token.balanceOf(Escrow)=0`，`token.balanceOf(Client)=1000` |

**合约依据**：`_reject()` L430-432 — reject 在 Open 状态只看 `currentStatus`，不读 `job.budget`。资金从未托管故无退款。

---

#### IT-005：Evaluator rejects in Funded（全额退款）

| 属性 | 内容 |
|------|------|
| **场景类别** | Reject |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），Client mint 1000 token，Client approve Escrow 1000 |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → reject(1, reason=bytes32("not qualified"), sender=Evaluator)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | fund 后 | `getStatus(1)=Funded`，`token.balanceOf(Escrow)=500`，`token.balanceOf(Client)=500` |
| 2 | reject 后 | `getStatus(1)=Rejected` |
| 3 | reject 后 | `token.balanceOf(Escrow)=0`（全额退还） |
| 4 | reject 后 | `token.balanceOf(Client)=1000`（恢复 fund 前余额） |
| 5 | reject 后 | emit `JobRejected(1, Evaluator, bytes32("not qualified"))` |
| 6 | reject 后 | emit `Refunded(1, Client, 500)` |
| 7 | reject 后 | `token.balanceOf(Evaluator)=0`（Evaluator 永不触碰资金） |

**合约依据**：`_reject()` L433-435, L448-455 — Funded 状态下 `shouldRefund=true`，`refundAmount=job.budget`，通过 `_paymentToken.transfer(refundTarget, refundAmount)` 全额退款。

---

#### IT-006：Evaluator rejects in Submitted（全额退款）

| 属性 | 内容 |
|------|------|
| **场景类别** | Reject |
| **优先级** | P0 |
| **前置条件** | 同 IT-005 |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → submit(1, deliverable=bytes32("work"), sender=Provider)
  → reject(1, reason=bytes32("quality fail"), sender=Evaluator)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | submit 后 | `getStatus(1)=Submitted`，emit `JobSubmitted(1, Provider, bytes32("work"))` |
| 2 | reject 后 | `getStatus(1)=Rejected` |
| 3 | reject 后 | `token.balanceOf(Escrow)=0`，`token.balanceOf(Client)=1000` |
| 4 | reject 后 | emit `JobRejected(1, Evaluator, bytes32("quality fail"))` |
| 5 | reject 后 | emit `Refunded(1, Client, 500)` |
| 6 | reject 后 | `token.balanceOf(Provider)=0`（Provider 未收款） |

**合约依据**：`_reject()` L433-435 — Funded 和 Submitted 共享同一分支，逻辑相同（`currentStatus == Status.Funded || currentStatus == Status.Submitted`）。

---

#### IT-007：Reject 退款后资金闭环 — Client 用退款创建新 Job 并 Happy Path

| 属性 | 内容 |
|------|------|
| **场景类别** | Reject / MultiJob |
| **优先级** | P1 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），Client mint 1000 token，Client approve Escrow 1000 |

**操作序列**：

```
=== Job 1: 被拒退款 ===
createJob(provider=address(0), evaluator, expiredAt, "job1", hook=address(0), sender=Client)
  → setProvider(1, provider1, sender=Client)
  → setBudget(1, 400, sender=Client)
  → fund(1, expectedBudget=400, sender=Client)
  → reject(1, reason=bytes32("rejected"), sender=Evaluator)

=== Job 2: 用退款资金（Happy Path）===
createJob(provider=address(0), evaluator2, expiredAt2, "job2", hook=address(0), sender=Client)
  → setProvider(2, provider2, sender=Client)
  → setBudget(2, 400, sender=Client)
  → fund(2, expectedBudget=400, sender=Client)
  → submit(2, deliverable=bytes32("work2"), sender=Provider2)
  → complete(2, reason=bytes32("ok"), sender=Evaluator2)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | Job1 reject 后 | `token.balanceOf(Client)=1000`（退款全额到账，与初始余额一致） |
| 2 | Job2 createJob 后 | `jobId=2`，`jobCount()=2`（jobId 不回退） |
| 3 | Job2 fund 后 | `token.balanceOf(Client)=600`（1000 - 400），`token.balanceOf(Escrow)=400` |
| 4 | Job2 complete 后 | `getStatus(2)=Completed`，Provider2 收款 400，`token.balanceOf(Escrow)=0` |

**验证点**：退款金额 = 新 job budget；资金闭环无泄漏；jobId 自增不因拒绝而回退（`_jobCounter` 只增不减）。

---

### B. 过期路径（Expire）

#### IT-008：Funded 状态过期 → 任意人 claimRefund 成功

| 属性 | 内容 |
|------|------|
| **场景类别** | Expire |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），Client mint 1000 token，Client approve 1000 |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt=now+3600, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → vm.warp(expiredAt + 1)
  → claimRefund(1, sender=任意地址)    ← 非 Client、非 Provider、非 Evaluator 的随机地址
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | fund 后 | `getStatus(1)=Funded`，`token.balanceOf(Escrow)=500` |
| 2 | warp 后 | `block.timestamp = expiredAt + 1 > expiredAt` |
| 3 | claimRefund 后 | `getStatus(1)=Expired` |
| 4 | claimRefund 后 | `token.balanceOf(Escrow)=0`，`token.balanceOf(Client)=1000` |
| 5 | claimRefund 后 | emit `JobExpired(1)` |
| 6 | claimRefund 后 | emit `Refunded(1, Client, 500)` |
| 7 | claimRefund 后 | Hook 合约无任何调用记录（claimRefund 是不可 Hook 函数，L497-498） |

**合约依据**：`claimRefund()` L472-498 — `require(block.timestamp >= job.expiredAt)`，无调用者角色限制，**故意不调 Hook**。

---

#### IT-009：Submitted 状态过期 → 任意人 claimRefund 成功

| 属性 | 内容 |
|------|------|
| **场景类别** | Expire |
| **优先级** | P0 |
| **前置条件** | 同 IT-008 |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → submit(1, deliverable=bytes32("work"), sender=Provider)
  → vm.warp(expiredAt + 1)
  → claimRefund(1, sender=任意地址)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | submit 后 | `getStatus(1)=Submitted`，emit `JobSubmitted(1, Provider, bytes32("work"))` |
| 2 | warp 后 | `block.timestamp > expiredAt` |
| 3 | claimRefund 后 | `getStatus(1)=Expired`，`token.balanceOf(Escrow)=0` |
| 4 | claimRefund 后 | emit `JobExpired(1)` + emit `Refunded(1, Client, 500)` |
| 5 | claimRefund 后 | `token.balanceOf(Provider)=0`（Provider 分文未得） |

**验证点**：Submitted→Expired 与 Funded→Expired 逻辑完全一致；Provider 提交了工作但因过期无法收款 — 对 Provider 的经济安全至关重要。

---

#### IT-010：过期后 submit 仍可执行（无过期拦截），但可被 claimRefund 覆盖

| 属性 | 内容 |
|------|------|
| **场景类别** | Expire / Edge |
| **优先级** | P1 |
| **前置条件** | 同 IT-008 |

> ⚠️ **合约行为分析**：`submit()` 的 modifier 为 `onlyStatus(Funded)` + `onlyProvider`，**无 `block.timestamp` 检查**。因此 Provider 在过期后仍可 submit。这与用户直觉预期（"过期后 submit 应 revert"）不符，是合约当前实际行为。本用例验证此行为并暴露潜在风险。

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt=now+3600, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → vm.warp(expiredAt + 1)
  → submit(1, deliverable=bytes32("late work"), sender=Provider)     ← 预期：成功（合约未拦截）
  → claimRefund(1, sender=任意地址)                                   ← 覆盖为 Expired
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | warp 后 | `block.timestamp > expiredAt`，`getStatus(1)=Funded`（仍为 Funded，因为无人调用 claimRefund） |
| 2 | submit 后 | `getStatus(1)=Submitted`，emit `JobSubmitted(1, Provider, bytes32("late work"))` — submit **不 revert** |
| 3 | claimRefund 后 | `getStatus(1)=Expired`，`token.balanceOf(Client)=1000`（退款） |

**风险标注**：`submit()` 缺少 `require(block.timestamp < job.expiredAt)` 检查。恶意 Provider 可在过期后抢在 claimRefund 之前 submit，将状态从 Funded 推至 Submitted，延长 Evaluator 可操作窗口。是否需要在合约层面添加拦截取决于业务需求。

---

#### IT-011：Expired 后重复 claimRefund → revert

| 属性 | 内容 |
|------|------|
| **场景类别** | Expire |
| **优先级** | P0 |
| **前置条件** | 先完成 IT-008 的全部前置步骤（job 已 Expired） |

**操作序列**：

```
（前置：job1 已通过 claimRefund 进入 Expired 终态）

claimRefund(1, sender=任意地址)    ← 第二次调用
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | 第二次 claimRefund | revert `"ERC8183: job not in refundable state"` |
| 2 | 状态 | `getStatus(1)` 仍为 `Expired`（未变） |
| 3 | 余额 | `token.balanceOf(Escrow)=0`（资金未被二次提取） |

**合约依据**：`claimRefund()` L476-478 — `require(currentStatus == Status.Funded || currentStatus == Status.Submitted)`，Expired 不满足条件。

---

#### IT-012：block.timestamp 恰好等于 expiredAt → claimRefund 成功

| 属性 | 内容 |
|------|------|
| **场景类别** | Expire / Edge |
| **优先级** | P2 |
| **前置条件** | 同 IT-008 |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt=now+3600, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → vm.warp(expiredAt)             ← 恰好等于，不 +1
  → claimRefund(1, sender=任意地址)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | warp 后 | `block.timestamp == expiredAt` |
| 2 | claimRefund 后 | `getStatus(1)=Expired`，退款成功，emit `JobExpired(1)` + `Refunded(1, Client, 500)` |

**合约依据**：`claimRefund()` L481 — `require(block.timestamp >= job.expiredAt)`，`>=` 包含等于。

---

### C. Hook 交互场景

> **需新增 Mock**：本节需要可配置的 Reverting Hook 合约（`test/mocks/RevertingMockHook.sol`），支持在 `beforeAction` 或 `afterAction` 中按指定 selector 触发 revert。现有 `MockHook.sol` 和 `MaliciousReenterHook.sol` 不满足本节需求。

#### IT-013：beforeAction revert → 整个 tx 回滚（以 fund 为例）

| 属性 | 内容 |
|------|------|
| **场景类别** | Hook |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow，部署 RevertingMockHook（`beforeAction` 在 selector=SEL_FUND 时 revert），Client mint + approve |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=RevertingMockHook, sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)    ← 预期：tx 整体 revert
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | fund 调用前 | `getStatus(1)=Open`，`token.balanceOf(Escrow)=0` |
| 2 | fund tx 后 | tx revert（原因来自 Hook 的 beforeAction revert） |
| 3 | fund tx 后 | `getStatus(1)=Open`（状态未变） |
| 4 | fund tx 后 | `token.balanceOf(Escrow)=0`（资金未转入） |
| 5 | fund tx 后 | `token.balanceOf(Client)=1000`（资金未扣除） |

**合约依据**：`_fund()` L301 — `_callBeforeHook` 在状态变更 L304 和 transferFrom L308 **之前**执行，revert 后无任何副作用。

---

#### IT-014：afterAction revert → 整个 tx 回滚（以 complete 为例）

| 属性 | 内容 |
|------|------|
| **场景类别** | Hook |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），部署 RevertingMockHook（`afterAction` 在 selector=SEL_COMPLETE 时 revert），Client mint 1000 + approve |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=RevertingMockHook, sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → submit(1, deliverable=bytes32("work"), sender=Provider)
  → complete(1, reason=bytes32("ok"), sender=Evaluator)   ← 预期：tx 整体 revert
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | complete 调用前 | `getStatus(1)=Submitted`，`token.balanceOf(Escrow)=500` |
| 2 | complete tx 后 | tx revert（原因来自 Hook 的 afterAction revert） |
| 3 | complete tx 后 | `getStatus(1)=Submitted`（**不是** Completed — Solidity tx 原子回滚） |
| 4 | complete tx 后 | `token.balanceOf(Escrow)=500`（资金未动） |
| 5 | complete tx 后 | `token.balanceOf(Provider)=0`（Provider 未收款） |

**合约依据**：`_complete()` L378（状态变更） → L385-398（转账） → L405（afterAction）。`afterAction` 在函数末尾，但 Solidity 的 tx 级原子性保证所有内部状态变更随 revert 一起回滚。**checks-effects-interactions 模式不保护 afterAction revert — 整个 tx 回滚包括状态变更**。

> 🔬 **设计讨论**：虽然 tx 级别状态安全，但 afterAction revert 会导致 complete 操作永远无法成功（只要 Hook 不修复），这在生产环境中可能导致资金永久锁定在 Submitted 状态。EIP-8183 标准未规定如何处理此场景。

---

### D. 跨函数重入

> **需新增 Mock**：本节需要跨函数重入 Hook（`test/mocks/CrossReenterHook.sol`），在 `afterAction` 中根据被触发函数选择器调用**不同**的核心函数（如 submit→complete、complete→reject）。现有 `MaliciousReenterHook.sol` 只做同函数重入（submit→submit），不满足本节需求。

#### IT-015：submit 的 Hook afterAction 中重入 complete → 被 nonReentrant 阻止

| 属性 | 内容 |
|------|------|
| **场景类别** | Reentry |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow + CrossReenterHook（afterAction: 收到 SEL_SUBMIT 时调用 escrow.complete(jobId, reason)），Client mint + approve，Provider 和 Evaluator 各自角色就位 |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=CrossReenterHook, sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → submit(1, deliverable=bytes32("work"), sender=Provider)    ← 预期：tx 整体 revert
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | submit tx 后 | tx revert `"ERC8183: reentrant call"` |
| 2 | submit tx 后 | `getStatus(1)=Funded`（submit 的状态变更被回滚） |
| 3 | submit tx 后 | complete 的 `JobCompleted` 事件**不发射** |
| 4 | submit tx 后 | `token.balanceOf(Escrow)=500`（资金未动） |

**调用链分析**：
```
Provider → submit(jobId)                                           [_locked=false→true]
  → _callAfterHook → CrossReenterHook.afterAction()
    → escrow.complete(jobId, reason)                               [_locked=true → revert]
      → nonReentrant: require(!_locked) → "ERC8183: reentrant call"
```

`submit` 的 `nonReentrant` modifier 先设置 `_locked=true`（L61-62），Hook 的 `afterAction` 在内部重入 `complete`，`complete` 的 `nonReentrant` 检测到 `_locked=true` → revert。整个 submit tx 回滚。

---

#### IT-016：complete 的 Hook afterAction 中重入 reject → 被 nonReentrant 阻止

| 属性 | 内容 |
|------|------|
| **场景类别** | Reentry |
| **优先级** | P0 |
| **前置条件** | 同上，CrossReenterHook 配置为：收到 SEL_COMPLETE 时调用 escrow.reject(jobId, reason) |

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=CrossReenterHook, sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → submit(1, deliverable=bytes32("work"), sender=Provider)
  → complete(1, reason=bytes32("ok"), sender=Evaluator)    ← 预期：tx 整体 revert
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | complete tx 后 | tx revert `"ERC8183: reentrant call"` |
| 2 | complete tx 后 | `getStatus(1)=Submitted`（不是 Completed，也不是 Rejected） |
| 3 | complete tx 后 | `token.balanceOf(Escrow)=500`（资金未动） |
| 4 | complete tx 后 | `token.balanceOf(Provider)=0`（未付款） |
| 5 | complete tx 后 | `token.balanceOf(Client)=500`（未退款） |

**调用链分析**：
```
Evaluator → complete(jobId)                                        [_locked=false→true]
  → _callAfterHook → CrossReenterHook.afterAction()
    → escrow.reject(jobId, reason)                                 [_locked=true → revert]
      → nonReentrant: require(!_locked) → "ERC8183: reentrant call"
```

逻辑与 IT-015 对称：`complete` 持有锁，`reject` 的 `nonReentrant` 检测到锁 → revert → 整个 complete tx 回滚。

---

### E. 多 Job 并存

#### IT-017：两个 Job 独立 Happy Path（无手续费）

| 属性 | 内容 |
|------|------|
| **场景类别** | MultiJob |
| **优先级** | P0 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），Client mint 2000 token，Client approve 2000 |

**操作序列**：

```
=== Job 1: 全流程 ===
createJob(provider=address(0), evaluator1, expiredAt1, "job1", hook=address(0), sender=Client)
  → setProvider(1, provider1, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
  → submit(1, deliverable=bytes32("work1"), sender=Provider1)
  → complete(1, reason=bytes32("ok"), sender=Evaluator1)

=== Job 2: 全流程（不同角色）===
createJob(provider=address(0), evaluator2, expiredAt2, "job2", hook=address(0), sender=Client)
  → setProvider(2, provider2, sender=Client)
  → setBudget(2, 700, sender=Client)
  → fund(2, expectedBudget=700, sender=Client)
  → submit(2, deliverable=bytes32("work2"), sender=Provider2)
  → complete(2, reason=bytes32("ok"), sender=Evaluator2)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | Job1 complete 后 | `getStatus(1)=Completed`，Provider1 收 500，`token.balanceOf(Escrow)=0` |
| 2 | Job2 createJob | `jobId=2`，`getJob(2).client=Client`，`getJob(2).evaluator=evaluator2`（与 Job1 独立） |
| 3 | Job2 fund 后 | `token.balanceOf(Escrow)=700`（仅 Job2 资金） |
| 4 | Job2 complete 后 | `getStatus(2)=Completed`，Provider2 收 700 |
| 5 | Job2 complete 后 | `getStatus(1)=Completed`（Job1 状态未被 Job2 操作干扰） |
| 6 | 最终 | `jobCount()=2` |

---

#### IT-018：Job1 Funded + Job2 Open 并存，互不干扰

| 属性 | 内容 |
|------|------|
| **场景类别** | MultiJob |
| **优先级** | P0 |
| **前置条件** | 同 IT-017 |

**操作序列**：

```
=== Job 1: fund 后停留 ===
createJob(provider=address(0), evaluator1, expiredAt1, "job1", hook=address(0), sender=Client)
  → setProvider(1, provider1, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)
（此时 status=Funded，escrow 余额=500）

=== Job 2: 仅创建（Open）===
createJob(provider=address(0), evaluator2, expiredAt2, "job2", hook=address(0), sender=Client)
  → setProvider(2, provider2, sender=Client)
  → setBudget(2, 300, sender=Client)
（此时 status=Open，未 fund）
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | Job1 fund 后 | `getStatus(1)=Funded`，`getJob(1).budget=500` |
| 2 | Job2 setBudget 后 | `getStatus(2)=Open`，`getJob(2).budget=300` |
| 3 | Job2 setBudget 后 | `getStatus(1)=Funded`（Job1 状态未受 Job2 操作影响） |
| 4 | Job2 setBudget 后 | `getJob(1).budget=500`（Job1 budget 未被覆盖） |
| 5 | 最终 | `token.balanceOf(Escrow)=500`（仅 Job1 资金，Job2 未 fund） |

**验证点**：不同 `jobId` 的 `Job struct` 在 `_jobs` mapping 中完全独立；`setBudget` 写入 `_jobs[jobId].budget` 不会跨 jobId 污染。

---

#### IT-019：同一 Client 完成 Job1 后创建并 fund Job2 — 余额闭环

| 属性 | 内容 |
|------|------|
| **场景类别** | MultiJob |
| **优先级** | P1 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），Client mint 1000 token，Client approve 1000 |

**操作序列**：

```
=== Job 1: Happy Path（Client 支付 Provider）===
createJob(provider=address(0), evaluator1, expiredAt1, "job1", hook=address(0), sender=Client)
  → setProvider(1, provider1, sender=Client)
  → setBudget(1, 400, sender=Client)
  → fund(1, expectedBudget=400, sender=Client)
  → submit(1, deliverable=bytes32("work1"), sender=Provider1)
  → complete(1, reason=bytes32("ok"), sender=Evaluator1)

=== Job 2: 同一 Client 创建（余额已减少 400）===
createJob(provider=address(0), evaluator2, expiredAt2, "job2", hook=address(0), sender=Client)
  → setProvider(2, provider2, sender=Client)
  → setBudget(2, 300, sender=Client)
  → fund(2, expectedBudget=300, sender=Client)
  → submit(2, deliverable=bytes32("work2"), sender=Provider2)
  → complete(2, reason=bytes32("ok"), sender=Evaluator2)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | Job1 complete 后 | `token.balanceOf(Client)=600`（1000 - 400，无退款） |
| 2 | Job2 fund 后 | `token.balanceOf(Client)=300`（600 - 300） |
| 3 | Job2 complete 后 | `token.balanceOf(Client)=300`，`getStatus(1)=Completed`，`getStatus(2)=Completed` |
| 4 | 最终 | `jobCount()=2`，Provider1 收 400，Provider2 收 300 |

**验证点**：Client 的 ERC20 余额追踪正确；两次 job 间的余额无串扰。

---

### F. 边界集成

#### IT-020：expiredAt 极短（1 秒），Provider 抢在 claimRefund 前 submit → 成功

| 属性 | 内容 |
|------|------|
| **场景类别** | Edge / Expire |
| **优先级** | P1 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=0），Client mint 1000 + approve |

> ⚠️ **合约行为分析**（同 IT-010）：`submit()` 无过期检查。本节验证在极短过期窗口下 Provider 的 racing 行为。

**操作序列**：

```
createJob(provider=address(0), evaluator, expiredAt=block.timestamp+1, "urgent", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 500, sender=Client)
  → fund(1, expectedBudget=500, sender=Client)       ← 此时 block.timestamp < expiredAt
  → vm.warp(block.timestamp + 2)                      ← 过期 1 秒
  → submit(1, deliverable=bytes32("late"), sender=Provider)   ← 不 revert
  → claimRefund(1, sender=任意地址)                   ← 可覆盖
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | fund 后 | `getStatus(1)=Funded`，`block.timestamp < expiredAt` |
| 2 | warp 后 | `block.timestamp > expiredAt`（已过期），`getStatus(1)=Funded` |
| 3 | submit 后 | `getStatus(1)=Submitted` — submit **成功**（合约无过期拦截） |
| 4 | claimRefund 后 | `getStatus(1)=Expired`，Client 收退款 500 |

**设计讨论**：如果 `submit()` 添加 `require(block.timestamp < job.expiredAt)`，则步骤 3 应 revert。当前行为允许 Provider 在过期后继续操作，需确认是否符合 EIP-8183 意图。参见 IT-010 详细分析。

---

#### IT-021：Owner 中途修改 feeBps → 影响后续 complete 的手续费计算

| 属性 | 内容 |
|------|------|
| **场景类别** | Edge / Admin |
| **优先级** | P1 |
| **前置条件** | 部署 Escrow（treasury≠address(0), feeBps=250 = 2.5%），Client mint 10000 + approve |

**操作序列**：

```
=== 阶段 1: 旧费率下创建 + fund ===
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 10000, sender=Client)
  → fund(1, expectedBudget=10000, sender=Client)

=== 阶段 2: Owner 改费率 ===
setFeeBps(500, sender=Owner)              ← 改为 5%

=== 阶段 3: 新费率下 submit + complete ===
submit(1, deliverable=bytes32("work"), sender=Provider)
  → complete(1, reason=bytes32("ok"), sender=Evaluator)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | fund 后 | `feeBps=250`（旧费率），`getStatus(1)=Funded` |
| 2 | setFeeBps 后 | `feeBps=500`（新费率） |
| 3 | complete 后 | Provider 收款 = 10000 - 500 = **9500**（按新费率 5% 计算） |
| 4 | complete 后 | treasury 收款 = **500** |
| 5 | complete 后 | `feeBps` 仍为 500 |

**合约依据**：`_complete()` L387 — `fee = (escrowBalance * feeBps) / MAX_FEE_BPS`，`feeBps` 是 storage 变量，在 complete 执行时当场读取。**费率在 job 生命周期中可变，complete 时刻的值决定最终手续费。**

> 🔬 **业务含义**：如果 EIP-8183 意图是"创建 job 时固定费率"，则合约应在 `createJob` 时 snapshot `feeBps` 并存入 `Job struct`。当前行为是运行时可变。

---

#### IT-022：Owner 中途修改 treasury → 影响后续 complete 的收费开关

| 属性 | 内容 |
|------|------|
| **场景类别** | Edge / Admin |
| **优先级** | P2 |
| **前置条件** | 部署 Escrow（treasury=address(0), feeBps=500），Client mint 10000 + approve |

**操作序列**：

```
=== 部署: treasury=address(0), feeBps=500 ===

=== 阶段 1: 零 treasury 下创建 + fund ===
createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)
  → setProvider(1, provider, sender=Client)
  → setBudget(1, 10000, sender=Client)
  → fund(1, expectedBudget=10000, sender=Client)

=== 阶段 2: Owner 设置 treasury ===
setTreasury(treasuryAddr, sender=Owner)    ← 从 address(0) 改为非零

=== 阶段 3: 新 treasury 下 submit + complete ===
submit(1, deliverable=bytes32("work"), sender=Provider)
  → complete(1, reason=bytes32("ok"), sender=Evaluator)
```

**关键断言**：

| # | 时机 | 断言内容 |
|---|------|----------|
| 1 | fund 后 | `treasury=address(0)`，`feeBps=500` |
| 2 | setTreasury 后 | `treasury=treasuryAddr`（非零） |
| 3 | complete 后 | Provider 收款 = **9500**（手续费 5% 被触发） |
| 4 | complete 后 | treasuryAddr 收款 = **500** |

**合约依据**：`_complete()` L387 — `if (treasury != address(0) && feeBps > 0)`。`treasury` 在 complete 时当场读取，从 0 改为非 0 后手续费开关激活。

**反向验证**（可选补充）：

```
=== 部署: treasury≠0, feeBps=500 ===
→ createJob + fund
→ setTreasury(address(0), sender=Owner)
→ submit + complete
→ Provider 收款 = 10000（全额，手续费未触发）
```

---

## 3. 所需 Mock 合约清单

| Mock 合约 | 文件路径 | 用途 | 对应用例 |
|-----------|----------|------|----------|
| `MockERC20` | `test/mocks/MockERC20.sol` ✅ 已存在 | 支付代币 | 全部 |
| `MockHook` | `test/mocks/MockHook.sol` ✅ 已存在 | 记录 Hook 调用（不 revert） | IT-008(claimRefund 无 Hook 验证) |
| `MaliciousReenterHook` | `test/mocks/MaliciousReenterHook.sol` ✅ 已存在 | 同函数重入（submit→submit 等） | 单元测试 UT-089~UT-094 |
| **`RevertingMockHook`** | `test/mocks/RevertingMockHook.sol` 🆕 需新建 | 可在 beforeAction/afterAction 中按 selector 触发 revert | IT-013, IT-014 |
| **`CrossReenterHook`** | `test/mocks/CrossReenterHook.sol` 🆕 需新建 | 跨函数重入（submit→complete, complete→reject） | IT-015, IT-016 |

### 3.1 RevertingMockHook 接口建议

```solidity
// 构造函数参数：
//   - bool _revertOnBefore:   beforeAction 是否 revert
//   - bool _revertOnAfter:    afterAction 是否 revert
//   - bytes4 _targetSelector: 仅在匹配的 selector 触发时 revert
//   (其他 selector 正常通过)
contract RevertingMockHook is IACPHook {
    bool public revertOnBefore;
    bool public revertOnAfter;
    bytes4 public targetSelector;

    function beforeAction(uint256, bytes4 selector, bytes calldata) external override {
        if (revertOnBefore && selector == targetSelector) revert("Hook: before revert");
    }
    function afterAction(uint256, bytes4 selector, bytes calldata) external override {
        if (revertOnAfter && selector == targetSelector) revert("Hook: after revert");
    }
}
```

### 3.2 CrossReenterHook 接口建议

```solidity
// 构造函数参数：
//   - address _escrow: ERC8183Escrow 合约地址
//   - mapping(bytes4 => bytes4) _reentryMap: 触发 selector → 重入目标 selector
//     例: SEL_SUBMIT → SEL_COMPLETE, SEL_COMPLETE → SEL_REJECT
// 重入时使用固定参数 (jobId, bytes32(0))
contract CrossReenterHook is IACPHook {
    // 在 afterAction 中根据当前 selector 查表，调用 escrow 的对应目标函数
}
```

---

## 4. 与已有测试的互补关系

### 4.1 与 Happy Path（IT-001/IT-002）的分工

| 覆盖内容 | 归属 |
|----------|------|
| createJob→setProvider→setBudget→fund→submit→complete（无手续费） | IT-001 ✅ |
| 同上（2.5% 手续费） | IT-002 ✅ |
| Client rejects in Open（无托管资金） | **IT-003/IT-004** |
| Evaluator rejects in Funded（全额退款） | **IT-005** |
| Evaluator rejects in Submitted（全额退款） | **IT-006** |
| 退款资金闭环再建 job | **IT-007** |
| 过期退款（Funded/Submitted） | **IT-008/IT-009** |
| 两个 job 独立 Happy Path | **IT-017** |

### 4.2 与单元测试（UT-001~UT-104）的分工

| 覆盖内容 | 归属 |
|----------|------|
| `fund()` 在 Open 状态注资成功（单函数） | UT-022 ✅ |
| `fund()` 在非 Open 状态 revert（单函数） | UT-027 ✅ |
| `reject()` Open 状态 Client 调用（单函数） | UT-044 ✅ |
| `reject()` Funded 状态 Evaluator 调用（单函数） | UT-045 ✅ |
| `claimRefund()` 过期成功（单函数） | UT-052/UT-053 ✅ |
| `claimRefund()` 未过期 revert（单函数） | UT-054 ✅ |
| 防重入同函数（submit→submit）（单函数） | UT-092 ✅ |
| Hook beforeAction/afterAction 触发（单函数） | UT-076~UT-088 ✅ |
| **跨函数旅程**：createJob→...→reject→createJob→...→complete | **IT-007** |
| **跨函数旅程**：createJob→...→fund→expire→claimRefund→submit 被拒 | **IT-008+IT-010** |
| **跨函数重入**：submit→Hook→complete→nonReentrant revert | **IT-015** |
| **两个 job 并存不互污染** | **IT-017/IT-018** |
| **Owner 中途改 feeBps/treasury** | **IT-021/IT-022** |

---

## 5. 附录

### A. 状态机回顾

```
                    ┌──────────────────────────────────────────┐
                    │              claimRefund (anyone)        │
                    │  ┌───────────────────────────────────┐   │
                    │  │           过期（>= expiredAt）      │   │
                    ▼  │                                   │   │
  Open ──fund──► Funded ──submit──► Submitted ──complete──► Completed
   │               │                    │
   │  reject       │  reject            │  reject
   │  (Client)     │  (Evaluator)       │  (Evaluator)
   ▼               ▼                    ▼
 Rejected ◄─── Rejected ◄────────── Rejected
                    │                    │
                    └─ refund ───────────┘
                         (全额退 Client)
```

### B. 关键函数约束速查

| 函数 | msg.sender 要求 | 状态要求 | 过期检查 | Hook 调用 | nonReentrant |
|------|----------------|----------|----------|-----------|--------------|
| `createJob` | 无限制 | N/A | `expiredAt > now` | N/A | ❌ |
| `setProvider` | Client | Open | ❌ | before + after | ✅ |
| `setBudget` | Client 或 Provider | Open | ❌ | before + after | ✅ |
| `fund` | Client | Open | ❌ | before + after | ✅ |
| `submit` | Provider | Funded | ❌ | before + after | ✅ |
| `complete` | Evaluator | Submitted | ❌ | before + after | ✅ |
| `reject` | Client（Open）/ Evaluator（Funded/Submitted） | 非终态 | ❌ | before + after | ✅ |
| `claimRefund` | 任何人 | Funded/Submitted | `>= expiredAt` | ❌ 故意不调 | ✅ |

### C. 手续费逻辑

```
if (treasury != address(0) && feeBps > 0) {
    fee      = budget * feeBps / 10000
    payAmount = budget - fee
}
// Rejected/Expired: 不收费，全额退 Client
```

### D. 已知合约行为与标准预期的差异

| 差异点 | 合约实际行为 | 可能预期 | 影响用例 |
|--------|-------------|---------|----------|
| `submit()` 无过期检查 | Provider 过期后仍可 submit | 过期后不应 submit | IT-010, IT-020 |
| `complete()` 无过期检查 | Evaluator 过期后仍可 complete | 过期后不应 complete | 类似 IT-010 |
| `feeBps`/`treasury` 运行时可变 | complete 时刻读取当前值 | createJob 时 snapshot | IT-021, IT-022 |
| `afterAction` 在 complete 转账之后 | Hook revert → 整个 tx 回滚（包括转账） | 资金应安全 | IT-014 |

---

*清单生成日期：2026-06-08 · Plan Agent · 仅设计，不写测试代码 · 基于合约 `ERC8183Escrow.sol` L1-L516 逐行分析*
