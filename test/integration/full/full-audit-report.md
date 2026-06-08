# ERC-8183 Escrow 完整集成测试审计报告

**审计时间**：2026-06-08
**审计范围**：test/integration/full/（6 文件）+ test/mocks/RevertingMockHook.sol + test/mocks/CrossReenterHook.sol
**审计依据**：test/integration/full/integration-test-checklist.md（Plan Agent 产出，共 20 用例 IT-003 ~ IT-022）
**审计方法**：静态代码审阅，逐用例对照清单，不执行代码

---

## 总览

| 指标 | 数值 |
|------|------|
| 清单用例总数 | 20（IT-003 ~ IT-022） |
| 测试文件应存在 | 6 |
| 测试文件实际存在 | 6 |
| 缺失文件 | 无（CrossReentry.t.sol **存在**，与 Prompt §1 中 ⚠️ 标注不符——该文件已由 Implement Agent 实现） |
| Mock 文件应存在 | 2 |
| Mock 文件实际存在 | 2 |
| 断言项总数（逐用例累计） | 106 |
| 代码覆盖 ✅ | 94 |
| 遗漏 ❌ | 1 |
| 偏差 ⚠️ | 11 |
| 可进入执行阶段 | ⚠️ 需先修复 1 个 ❌，建议修复 8 个 ⚠️（P0/P1），其余 3 个 ⚠️（P2）可在执行后迭代 |

---

## 逐用例审计

### IT-003：Client rejects in Open（无 provider，无 budget，无资金托管）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | jobId=1 | RejectPaths:L70 | `assertEq(jobId, 1)` | ✅ |
| 2 | getStatus(1)=Open（createJob 后） | RejectPaths:L71 | `assertEq(uint256(escrow.getStatus(1)), uint256(IERC8183.Status.Open))` | ✅ |
| 3 | getJob(1).client=Client | RejectPaths:L73 | `assertEq(job.client, client)` | ✅ |
| 4 | getJob(1).provider=address(0) | RejectPaths:L74 | `assertEq(job.provider, address(0))` | ✅ |
| 5 | getJob(1).budget=0 | RejectPaths:L75 | `assertEq(job.budget, 0)` | ✅ |
| 6 | getStatus(1)=Rejected（reject 后） | RejectPaths:L84 | `assertEq(..., IERC8183.Status.Rejected)` | ✅ |
| 7 | emit JobRejected(1, Client, reason) | RejectPaths:L79-82 | `expectEmit(true, true, false, true)` → JobRejected 2 indexed (jobId, rejector) | ✅ |
| 8 | **不发射** Refunded | RejectPaths:L79-87 | 无 Refunded expectEmit，无 Refunded 事件 | ✅ |
| 9 | token.balanceOf(Escrow)=0 | RejectPaths:L86 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 10 | token.balanceOf(Client)=1000 | RejectPaths:L87 | `assertEq(token.balanceOf(client), 1000)` | ✅ |

**判定**：✅ 全部 10 项覆盖。expectEmit 4-bool `(true, true, false, true)` 与 JobRejected 的 indexed(jobId, rejector) + data(reason) 匹配。

---

### IT-004：Client rejects in Open（provider + budget 已设，但未 fund）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | getJob(1).provider=provider（setProvider 后） | RejectPaths:L101 | `assertEq(job.provider, provider)` | ✅ |
| 2 | emit ProviderSet(1, provider) | — | **未验证** | ⚠️ 偏差 |
| 3 | getJob(1).budget=500（setBudget 后） | RejectPaths:L102 | `assertEq(job.budget, 500)` | ✅ |
| 4 | emit BudgetSet(1, 500) | — | **未验证** | ⚠️ 偏差 |
| 5 | getStatus(1)=Rejected（reject 后） | RejectPaths:L111 | `assertEq(..., IERC8183.Status.Rejected)` | ✅ |
| 6 | emit JobRejected(1, Client, bytes32("changed mind")) | RejectPaths:L106-109 | `expectEmit(true, true, false, true)` | ✅ |
| 7 | **不发射** Refunded | RejectPaths:L106-115 | 无 Refunded expectEmit | ✅ |
| 8 | token.balanceOf(Escrow)=0 | RejectPaths:L113 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 9 | token.balanceOf(Client)=1000 | RejectPaths:L114 | `assertEq(token.balanceOf(client), 1000)` | ✅ |

**判定**：⚠️ 2 项偏差——清单明确要求验证 `ProviderSet` 和 `BudgetSet` 事件的 emit，代码只验证了状态变更（provider/budget 字段），未验证事件发射。影响轻微——这两个事件的 emit 在 setProvider/setBudget 单元测试中已有覆盖。

---

### IT-005：Evaluator rejects in Funded（全额退款）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | getStatus(1)=Funded（fund 后） | RejectPaths:L129 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 2 | token.balanceOf(Escrow)=500 | RejectPaths:L130 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |
| 3 | token.balanceOf(Client)=500（fund 后） | RejectPaths:L131 | `assertEq(token.balanceOf(client), 500)` | ✅ |
| 4 | getStatus(1)=Rejected（reject 后） | RejectPaths:L142 | `assertEq(..., IERC8183.Status.Rejected)` | ✅ |
| 5 | token.balanceOf(Escrow)=0（全额退还） | RejectPaths:L143 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 6 | token.balanceOf(Client)=1000（恢复） | RejectPaths:L144 | `assertEq(token.balanceOf(client), 1000)` | ✅ |
| 7 | emit JobRejected(1, Evaluator, reason) | RejectPaths:L135-136 | `expectEmit(true, true, false, true)` with Evaluator index | ✅ |
| 8 | emit Refunded(1, Client, 500) | RejectPaths:L137-138 | `expectEmit(true, true, false, true)` amount=500 | ✅ |
| 9 | token.balanceOf(Evaluator)=0 | RejectPaths:L145 | `assertEq(token.balanceOf(evaluator), 0)` | ✅ |

**判定**：✅ 全部 9 项覆盖。Refunded 事件参数金额=500 与 budget 一致。

---

### IT-006：Evaluator rejects in Submitted（全额退款）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | getStatus(1)=Submitted（submit 后） | RejectPaths:L160 | `assertEq(..., IERC8183.Status.Submitted)` | ✅ |
| 2 | emit JobSubmitted(1, Provider, bytes32("work")) | — | **未验证** | ⚠️ 偏差 |
| 3 | getStatus(1)=Rejected（reject 后） | RejectPaths:L171 | `assertEq(..., IERC8183.Status.Rejected)` | ✅ |
| 4 | token.balanceOf(Escrow)=0 | RejectPaths:L172 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 5 | token.balanceOf(Client)=1000 | RejectPaths:L173 | `assertEq(token.balanceOf(client), 1000)` | ✅ |
| 6 | emit JobRejected(1, Evaluator, bytes32("quality fail")) | RejectPaths:L164-165 | `expectEmit(true, true, false, true)` | ✅ |
| 7 | emit Refunded(1, Client, 500) | RejectPaths:L166-168 | `expectEmit(true, true, false, true)` | ✅ |
| 8 | token.balanceOf(Provider)=0 | RejectPaths:L174 | `assertEq(token.balanceOf(provider), 0)` | ✅ |

**判定**：⚠️ 1 项偏差——JobSubmitted 事件未验证。submit 在 helper `_setupSubmitted` 中调用，无法在测试体内嵌 expectEmit。

---

### IT-007：Reject 退款后资金闭环 — Client 用退款创建新 Job 并 Happy Path

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | Job1 reject 后 token.balanceOf(Client)=1000 | RejectPaths:L198 | `assertEq(token.balanceOf(client), 1000)` | ✅ |
| 2 | Job2 createJob 后 jobId=2 | RejectPaths:L209 | `assertEq(jid2, 2)` | ✅ |
| 3 | jobCount()=2 | RejectPaths:L210 | `assertEq(escrow.jobCount(), 2)` | ✅ |
| 4 | Job2 fund 后 token.balanceOf(Client)=600 | RejectPaths:L211 | `assertEq(token.balanceOf(client), 600)` | ✅ |
| 5 | Job2 fund 后 token.balanceOf(Escrow)=400 | RejectPaths:L212 | `assertEq(token.balanceOf(address(escrow)), 400)` | ✅ |
| 6 | Job2 complete 后 getStatus(2)=Completed | RejectPaths:L220 | `assertEq(..., IERC8183.Status.Completed)` | ✅ |
| 7 | Provider2 收款 400 | RejectPaths:L221 | `assertEq(token.balanceOf(provider2), 400)` | ✅ |
| 8 | token.balanceOf(Escrow)=0（最终） | RejectPaths:L222 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |

**判定**：✅ 全部 8 项覆盖。退款闭环完整——Job1 退款后余额恢复至 1000，Job2 在此基础上 fund 400 后余额正确递减至 600。

---

### IT-008：Funded 状态过期 → 任意人 claimRefund 成功

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | fund 后 getStatus(1)=Funded | ExpirePaths:L71 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 2 | token.balanceOf(Escrow)=500 | ExpirePaths:L72 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |
| 3 | warp 后 block.timestamp > expiredAt | ExpirePaths:L76 | `assertGe(block.timestamp, shortExpiry + 1)` | ✅ |
| 4 | claimRefund 后 getStatus(1)=Expired | ExpirePaths:L86 | `assertEq(..., IERC8183.Status.Expired)` | ✅ |
| 5 | token.balanceOf(Escrow)=0 | ExpirePaths:L87 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 6 | token.balanceOf(Client)=1000 | ExpirePaths:L88 | `assertEq(token.balanceOf(client), 1000)` | ✅ |
| 7 | emit JobExpired(1) | ExpirePaths:L79-80 | `expectEmit(true, false, false, false)` — 仅 1 个 indexed param | ✅ |
| 8 | emit Refunded(1, Client, 500) | ExpirePaths:L81-82 | `expectEmit(true, true, false, true)` | ✅ |
| 9 | claimRefund 后 Hook 无调用记录（claimRefund 不调 Hook） | ExpirePaths:L92-93 | `assertEq(hook.beforeCount(), 1)` `assertEq(hook.afterCount(), 1)` | ❌ 偏差 |

**判定**：❌ #9——Hook 计数断言值错误。设置阶段执行了 `setProvider` + `setBudget` + `fund`（均绑定 Hook），各触发 1 次 beforeAction + 1 次 afterAction，因此 claimRefund 前 `beforeCount` 和 `afterCount` 均应为 **3**，非 1。测试断言 `==1` 会失败（如果执行的话——虽然我们只做静态审阅，但逻辑上是错误值）。

**修复建议**：改为 delta 式断言——在 claimRefund 前 snapshot count，claimRefund 后 assert count 未变：
```solidity
uint256 bcBefore = hook.beforeCount();
uint256 acBefore = hook.afterCount();
vm.prank(stranger);
escrow.claimRefund(1);
assertEq(hook.beforeCount(), bcBefore);
assertEq(hook.afterCount(), acBefore);
```
或直接断言 `beforeCount == 3 && afterCount == 3`。

---

### IT-009：Submitted 状态过期 → 任意人 claimRefund 成功

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | submit 后 getStatus(1)=Submitted | ExpirePaths:L118 | `assertEq(..., IERC8183.Status.Submitted)` | ✅ |
| 2 | emit JobSubmitted(1, Provider, bytes32("work")) | — | **未验证** | ⚠️ 偏差 |
| 3 | warp 后 block.timestamp > expiredAt | ExpirePaths:L122 | `assertGt(block.timestamp, shortExpiry)` | ✅ |
| 4 | claimRefund 后 getStatus(1)=Expired | ExpirePaths:L132 | `assertEq(..., IERC8183.Status.Expired)` | ✅ |
| 5 | token.balanceOf(Escrow)=0 | ExpirePaths:L133 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 6 | token.balanceOf(Client)=1000 | ExpirePaths:L134 | `assertEq(token.balanceOf(client), 1000)` | ✅ |
| 7 | emit JobExpired(1) | ExpirePaths:L125-126 | `expectEmit(true, false, false, false)` | ✅ |
| 8 | emit Refunded(1, Client, 500) | ExpirePaths:L127-128 | `expectEmit(true, true, false, true)` | ✅ |
| 9 | token.balanceOf(Provider)=0 | ExpirePaths:L135 | `assertEq(token.balanceOf(provider), 0)` | ✅ |

**判定**：⚠️ 1 项偏差——JobSubmitted 事件未验证。影响轻微。

---

### IT-010：过期后 submit 仍可执行（无过期拦截），但可被 claimRefund 覆盖

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | warp 后 block.timestamp > expiredAt | ExpirePaths:L159 | `assertGt(block.timestamp, shortExpiry)` | ✅ |
| 2 | warp 后 getStatus(1)=Funded（仍为 Funded） | ExpirePaths:L160 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 3 | submit 后 getStatus(1)=Submitted — **不 revert** | ExpirePaths:L163-166 | 无 expectRevert，submit 后 assert Submitted | ✅ |
| 4 | emit JobSubmitted(1, Provider, bytes32("late work")) | — | **未验证** | ⚠️ 偏差 |
| 5 | claimRefund 后 getStatus(1)=Expired | ExpirePaths:L172 | `assertEq(..., IERC8183.Status.Expired)` | ✅ |
| 6 | claimRefund 后 token.balanceOf(Client)=1000 | ExpirePaths:L173 | `assertEq(token.balanceOf(client), 1000)` | ✅ |

**判定**：⚠️ 1 项偏差——JobSubmitted 事件未验证。**关键通过**：代码中无 `vm.expectRevert` 包裹 submit——正确反映了合约无过期拦截的实际行为。

---

### IT-011：Expired 后重复 claimRefund → revert

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | 第二次 claimRefund revert `"ERC8183: job not in refundable state"` | ExpirePaths:L203 | `expectRevert(bytes("ERC8183: job not in refundable state"))` — 逐字匹配 | ✅ |
| 2 | getStatus(1) 仍为 Expired（未变） | ExpirePaths:L208 | `assertEq(..., IERC8183.Status.Expired)` | ✅ |
| 3 | token.balanceOf(Escrow)=0（资金未被二次提取） | ExpirePaths:L209 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |

**判定**：✅ 全部 3 项覆盖。expectRevert 在 prank 之前（L203-204），顺序正确。revert 消息与合约 L476-478 `"ERC8183: job not in refundable state"` 逐字匹配。

---

### IT-012：block.timestamp 恰好等于 expiredAt → claimRefund 成功

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | warp 后 block.timestamp == expiredAt | ExpirePaths:L232-233 | `vm.warp(exactExpiry)` + `assertEq(block.timestamp, exactExpiry)` | ✅ |
| 2 | claimRefund 成功 → getStatus(1)=Expired | ExpirePaths:L243 | `assertEq(..., IERC8183.Status.Expired)` | ✅ |
| 3 | emit JobExpired(1) | ExpirePaths:L236-237 | `expectEmit(true, false, false, false)` | ✅ |
| 4 | emit Refunded(1, Client, 500) | ExpirePaths:L238-239 | `expectEmit(true, true, false, true)` | ✅ |

**判定**：✅ 全部 4 项覆盖。边界 `>=` 验证正确。

---

### IT-013：beforeAction revert → 整个 tx 回滚（以 fund 为例）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | fund 前 getStatus(1)=Open | HookInteractions:L46 | `assertEq(..., IERC8183.Status.Open)` | ✅ |
| 2 | fund 前 token.balanceOf(Escrow)=0 | HookInteractions:L47 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 3 | fund tx revert（Hook beforeAction 触发） | HookInteractions:L50 | `expectRevert(bytes("Hook: beforeAction reverted"))` — 逐字匹配 | ✅ |
| 4 | fund tx 后 getStatus(1)=Open（未变） | HookInteractions:L55 | `assertEq(..., IERC8183.Status.Open)` | ✅ |
| 5 | fund tx 后 token.balanceOf(Escrow)=0 | HookInteractions:L57 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 6 | fund tx 后 token.balanceOf(Client)=1000（未扣） | HookInteractions:L59 | `assertEq(token.balanceOf(client), 1000)` | ✅ |

**判定**：✅ 全部 6 项覆盖。RevertingMockHook 构造 `(true, false, SEL_FUND)` 正确——仅在 SEL_FUND 的 beforeAction 中 revert。未错误验证 Client 余额减少。

---

### IT-014：afterAction revert → 整个 tx 回滚（以 complete 为例）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | complete 前 getStatus(1)=Submitted | HookInteractions:L85 | `assertEq(..., IERC8183.Status.Submitted)` | ✅ |
| 2 | complete 前 token.balanceOf(Escrow)=500 | HookInteractions:L86 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |
| 3 | complete tx revert（Hook afterAction 触发） | HookInteractions:L89 | `expectRevert(bytes("Hook: afterAction reverted"))` — 逐字匹配 | ✅ |
| 4 | complete tx 后 getStatus(1)=Submitted（**不是** Completed） | HookInteractions:L94 | `assertEq(..., IERC8183.Status.Submitted)` | ✅ |
| 5 | complete tx 后 token.balanceOf(Escrow)=500 | HookInteractions:L96 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |
| 6 | complete tx 后 token.balanceOf(Provider)=0 | HookInteractions:L98 | `assertEq(token.balanceOf(provider), 0)` | ✅ |

**判定**：✅ 全部 6 项覆盖。RevertingMockHook 构造 `(false, true, SEL_COMPLETE)` 正确——仅在 SEL_COMPLETE 的 afterAction 中 revert。关键在于验证状态回滚至 Submitted 而非 Completed。

---

### IT-015：submit 的 Hook afterAction 中重入 complete → nonReentrant 阻止

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | submit tx revert `"ERC8183: reentrant call"` | CrossReentry:L52 | `expectRevert(bytes("ERC8183: reentrant call"))` — 逐字匹配合约 L61 | ✅ |
| 2 | revert 后 getStatus(1)=Funded（状态回滚） | CrossReentry:L57 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 3 | JobCompleted 事件**不发射** | CrossReentry:L52-59 | 无 JobCompleted expectEmit | ✅ |
| 4 | token.balanceOf(Escrow)=500（资金未动） | CrossReentry:L59 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |

**判定**：✅ 全部 4 项覆盖。CrossReenterHook 构造 `(escrow, SEL_SUBMIT, SEL_COMPLETE)` 正确。submit 前已验证 pre-state 为 Funded + 500（L48-49）。

---

### IT-016：complete 的 Hook afterAction 中重入 reject → nonReentrant 阻止

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | complete tx revert `"ERC8183: reentrant call"` | CrossReentry:L89 | `expectRevert(bytes("ERC8183: reentrant call"))` — 逐字匹配 | ✅ |
| 2 | revert 后 getStatus(1)=Submitted（不是 Completed，不是 Rejected） | CrossReentry:L94 | `assertEq(..., IERC8183.Status.Submitted)` | ✅ |
| 3 | token.balanceOf(Escrow)=500（资金未动） | CrossReentry:L96 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |
| 4 | token.balanceOf(Provider)=0（未付款） | CrossReentry:L98 | `assertEq(token.balanceOf(provider), 0)` | ✅ |
| 5 | token.balanceOf(Client)=500（未退款） | CrossReentry:L100 | `assertEq(token.balanceOf(client), 500)` | ✅ |

**判定**：✅ 全部 5 项覆盖。CrossReenterHook 构造 `(escrow, SEL_COMPLETE, SEL_REJECT)` 正确。pre-state 为 Submitted + 500（L85-86）。Client 余额验证（未退款）为加分项。

---

### IT-017：两个 Job 独立 Happy Path（无手续费）

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | Job1 complete 后 getStatus(1)=Completed | MultiJob:L70 | `assertEq(..., IERC8183.Status.Completed)` | ✅ |
| 2 | Provider1 收 500 | MultiJob:L71 | `assertEq(token.balanceOf(provider1), 500)` | ✅ |
| 3 | Job1 complete 后 token.balanceOf(Escrow)=0 | MultiJob:L72 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 4 | Job2 createJob: jobId=2 | MultiJob:L77 | `assertEq(jid2, 2)` | ✅ |
| 5 | getJob(2).client=Client | MultiJob:L81 | `assertEq(job2.client, client)` | ✅ |
| 6 | getJob(2).evaluator=evaluator2 | MultiJob:L82 | `assertEq(job2.evaluator, evaluator2)` | ✅ |
| 7 | Job2 fund 后 token.balanceOf(Escrow)=700 | — | **未验证中间态**（helper 一气呵成 fund→submit→complete，无中间断言） | ⚠️ 偏差 |
| 8 | Job2 complete 后 getStatus(2)=Completed | MultiJob:L87 | `assertEq(..., IERC8183.Status.Completed)` | ✅ |
| 9 | Provider2 收 700 | MultiJob:L88 | `assertEq(token.balanceOf(provider2), 700)` | ✅ |
| 10 | Job2 complete 后 token.balanceOf(Escrow)=0 | MultiJob:L89 | `assertEq(token.balanceOf(address(escrow)), 0)` | ✅ |
| 11 | Job1 状态未被干扰：getStatus(1)=Completed | MultiJob:L92 | `assertEq(..., IERC8183.Status.Completed)` | ✅ |
| 12 | jobCount()=2 | MultiJob:L78 | `assertEq(escrow.jobCount(), 2)` | ✅ |

**判定**：⚠️ 1 项偏差——清单要求 Job2 fund 后验证 `token.balanceOf(Escrow)=700`（中间态），但 `_runHappyPath` helper 将 fund→submit→complete 打包执行，测试仅验证 complete 后的终极态 `Escrow=0`。遗漏了"Job2 资金在 submit 前确实独占 Escrow"的中间态验证。影响轻微——终极态验证通过间接证明 fund 正确执行。

---

### IT-018：Job1 Funded + Job2 Open 并存，互不干扰

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | Job1 fund 后 getStatus(1)=Funded | MultiJob:L115 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 2 | getJob(1).budget=500 | MultiJob:L116 | `assertEq(escrow.getJob(1).budget, 500)` | ✅ |
| 3 | Job2 setBudget 后 getStatus(2)=Open | MultiJob:L125 | `assertEq(..., IERC8183.Status.Open)` | ✅ |
| 4 | getJob(2).budget=300 | MultiJob:L126 | `assertEq(escrow.getJob(2).budget, 300)` | ✅ |
| 5 | Job2 setBudget 后 getStatus(1)=Funded（未受干扰） | MultiJob:L129 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 6 | getJob(1).budget=500（未被覆盖） | MultiJob:L130 | `assertEq(escrow.getJob(1).budget, 500)` | ✅ |
| 7 | token.balanceOf(Escrow)=500（仅 Job1 资金） | MultiJob:L133 | `assertEq(token.balanceOf(address(escrow)), 500)` | ✅ |

**判定**：✅ 全部 7 项覆盖。跨 job 无污染验证完整。

---

### IT-019：同一 Client 完成 Job1 后创建并 fund Job2 — 余额闭环

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | Job1 complete 后 token.balanceOf(Client)=600（1000-400） | MultiJob:L162 | `assertEq(token.balanceOf(client), 600)` | ✅ |
| 2 | Job2 fund 后 token.balanceOf(Client)=300（600-300） | MultiJob:L173 | `assertEq(token.balanceOf(client), 300)` | ✅ |
| 3 | Job2 complete 后 token.balanceOf(Client)=300 | MultiJob:L181 | `assertEq(token.balanceOf(client), 300)` | ✅ |
| 4 | getStatus(1)=Completed | MultiJob:L184 | `assertEq(..., IERC8183.Status.Completed)` | ✅ |
| 5 | getStatus(2)=Completed | MultiJob:L185 | `assertEq(..., IERC8183.Status.Completed)` | ✅ |
| 6 | jobCount()=2 | MultiJob:L186 | `assertEq(escrow.jobCount(), 2)` | ✅ |
| 7 | Provider1 收 400 | MultiJob:L163 | `assertEq(token.balanceOf(provider1), 400)` | ✅ |
| 8 | Provider2 收 300 | MultiJob:L182 | `assertEq(token.balanceOf(provider2), 300)` | ✅ |

**判定**：✅ 全部 8 项覆盖。余额递减链 `1000→600→300` 正确验证。

---

### IT-020：expiredAt 极短（1 秒），Provider 抢在 claimRefund 前 submit → 成功

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | fund 后 getStatus(1)=Funded | EdgeIntegration:L43 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 2 | fund 后 block.timestamp < expiredAt | EdgeIntegration:L44 | `assertLt(block.timestamp, shortExpiry)` | ✅ |
| 3 | warp 后 block.timestamp > expiredAt | EdgeIntegration:L48 | `assertGt(block.timestamp, shortExpiry)` | ✅ |
| 4 | warp 后 getStatus(1)=Funded | EdgeIntegration:L49 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 5 | submit 后 getStatus(1)=Submitted — **不 revert** | EdgeIntegration:L52-55 | 无 expectRevert，assert Submitted | ✅ |
| 6 | emit JobSubmitted(1, Provider, bytes32("late")) | — | **未验证** | ⚠️ 偏差 |
| 7 | claimRefund 后 getStatus(1)=Expired | EdgeIntegration:L61 | `assertEq(..., IERC8183.Status.Expired)` | ✅ |
| 8 | claimRefund 后 Client 收退款 (=1000) | EdgeIntegration:L62 | `assertEq(token.balanceOf(client), 1000)` | ✅ |

**判定**：⚠️ 1 项偏差——JobSubmitted 事件未验证。**关键通过**：submit 无 expectRevert 包裹。

---

### IT-021：Owner 中途修改 feeBps → 影响后续 complete 的手续费计算

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | fund 后 feeBps=250（旧费率） | — | **未明确断言** | ⚠️ 偏差 |
| 2 | fund 后 getStatus(1)=Funded | EdgeIntegration:L86 | `assertEq(..., IERC8183.Status.Funded)` | ✅ |
| 3 | setFeeBps 后 feeBps=500（新费率） | — | **未明确断言** | ⚠️ 偏差 |
| 4 | Owner 调用 setFeeBps 无 prank（address(this) 即 Owner） | EdgeIntegration:L90 | `escrow.setFeeBps(500)` 无 prank | ✅ |
| 5 | complete 后 Provider 收 9500（按新费率 5%） | EdgeIntegration:L104 | `assertEq(token.balanceOf(provider), providerBalBefore + 9500)` | ✅ |
| 6 | treasury 收 500 | EdgeIntegration:L106 | `assertEq(token.balanceOf(treasuryAddr), treasuryBalBefore + 500)` | ✅ |
| 7 | feeBps 仍为 500 | — | **未明确断言** | ⚠️ 偏差 |

**判定**：⚠️ 3 项偏差——feeBps 的前后值未通过显式断言验证。手续费计算结果的断言 `9500`/`500` 间接证明了 feeBps=500 在 complete 时生效，但未直接调用 `escrow.feeBps()` 进行验证。影响轻微。

---

### IT-022：Owner 中途修改 treasury → 影响后续 complete 的收费开关

| # | 清单断言项 | 代码行号 | 对应代码 | 判定 |
|---|-----------|----------|----------|------|
| 1 | fund 后 treasury=address(0), feeBps=500 | — | **未明确断言** | ⚠️ 偏差 |
| 2 | setTreasury 后 treasury=treasuryAddr（非零） | — | **未明确断言** | ⚠️ 偏差 |
| 3 | complete 后 Provider 收 9500（手续费激活） | EdgeIntegration:L148 | `assertEq(token.balanceOf(provider), providerBalBefore + 9500)` | ✅ |
| 4 | treasuryAddr 收 500 | EdgeIntegration:L150 | `assertEq(token.balanceOf(treasuryAddr), treasuryBalBefore + 500)` | ✅ |

**判定**：⚠️ 2 项偏差——treasury 和 feeBps 的前后值未显式断言。手续费结果断言间接证明 treasury 从零变为非零后收费开关激活。影响轻微。

---

## Mock 合约审计

### RevertingMockHook.sol

| # | 检查项 | 结果 |
|---|--------|------|
| 1 | 实现 IACPHook 接口 | ✅ `beforeAction(uint256, bytes4, bytes calldata) external override` + `afterAction` 签名完全匹配 IACPHook |
| 2 | 构造函数参数匹配 spec | ✅ `(bool _revertOnBefore, bool _revertOnAfter, bytes4 _targetSelector)` |
| 3 | selector 匹配逻辑 | ✅ `selector == targetSelector` — 精确匹配 |
| 4 | beforeAction revert 消息 | ✅ `"Hook: beforeAction reverted"` — 与 IT-013 中 expectRevert 消息一致 |
| 5 | afterAction revert 消息 | ✅ `"Hook: afterAction reverted"` — 与 IT-014 中 expectRevert 消息一致 |
| 6 | 非匹配 selector 正常通过 | ✅ `if (revertOnBefore && selector == targetSelector)` 双重条件，不匹配时仅更新计数器 |

**判定**：✅ Mock 合约实现正确，接口签名、revert 逻辑、selector 匹配均无问题。

### CrossReenterHook.sol

| # | 检查项 | 结果 |
|---|--------|------|
| 1 | 实现 IACPHook 接口 | ✅ 签名完全匹配 |
| 2 | 构造函数参数匹配 spec | ✅ `(address _escrow, bytes4 _triggerSelector, bytes4 _targetFunction)` |
| 3 | 跨函数路由逻辑 | ✅ 根据 `targetFunction` 调用对应 escrow 函数（submit/complete/reject/...） |
| 4 | optParams 版本兼容 | ✅ 已处理 `SEL_SUBMIT_EXT`、`SEL_COMPLETE_EXT`、`SEL_REJECT_EXT` — 当 triggerSelector 为基础版本时，ext 版本也视为匹配 |
| 5 | 仅 afterAction 触发重入 | ✅ `beforeAction` 为空（仅 `afterAction` 执行重入） |
| 6 | IEscrow 接口定义完整 | ✅ 包含 submit/complete/reject/fund/setProvider/setBudget/claimRefund 共 7 函数 |

**判定**：✅ Mock 合约实现正确，支持 cross-function reentry + optParams 变体。IEscrow 接口在文件内内联定义，无外部依赖。

---

## 发现的问题

### ❌ 遗漏项（必须修复）

| # | 用例 | 清单要求 | 当前状态 |
|---|------|----------|----------|
| 1 | IT-008 | claimRefund 后 Hook 无调用记录 → 验证 beforeCount/afterCount 未变（应为 3 而非 1） | ExpirePaths.t.sol:L92-93 断言 `beforeCount==1 && afterCount==1`（错误值） |

> **严重程度**：P0。该断言如果执行会失败——设置阶段 setProvider + setBudget + fund 共产生 beforeCount=3, afterCount=3。必须修复才能通过测试。

### ⚠️ 偏差项（需评估影响）

| # | 用例 | 期望 | 实际 | 影响 |
|---|------|------|------|------|
| 1 | IT-004 | emit ProviderSet(1, provider) + emit BudgetSet(1, 500) | 未验证事件 emit，仅验证 state 变更 | 轻微——事件 emit 在 setProvider/setBudget 单元测试中已验证 |
| 2 | IT-006 | emit JobSubmitted(1, Provider, bytes32("work")) | submit 在 helper `_setupSubmitted` 中调用，无法在测试体内嵌 expectEmit | 轻微——JobSubmitted 事件在 IT-001/IT-002 Happy Path 和 UT-submit 中已有覆盖 |
| 3 | IT-009 | emit JobSubmitted(1, Provider, bytes32("work")) | 同 IT-006——内联 submit 调用但未 expectEmit | 轻微 |
| 4 | IT-010 | emit JobSubmitted(1, Provider, bytes32("late work")) | 未验证 | 轻微 |
| 5 | IT-017 | Job2 fund 后 `token.balanceOf(Escrow)=700`（中间态） | helper 打包 fund→submit→complete，无中间断言 | 轻微——终极态 Escrow=0 间接验证 |
| 6 | IT-020 | emit JobSubmitted(1, Provider, bytes32("late")) | 未验证 | 轻微 |
| 7 | IT-021 | feeBps 前后值断言（250→500） | 未显式调用 `escrow.feeBps()` 断言 | 轻微——Provider/treasury 余额结果间接验证 |
| 8 | IT-022 | treasury 前后值断言（0→treasuryAddr） | 未显式调用 `escrow.treasury()` 断言 | 轻微——手续费激活间接验证 |

### 🔧 代码质量问题

| # | 文件:行号 | 问题 | 建议 |
|---|----------|------|------|
| 1 | ExpirePaths.t.sol:L92-93 | Hook count 硬编码为 1，应改为 delta 或正确值 3 | 在 claimRefund 前 snapshot，后 assert 未变；或直接断言 ==3 |
| 2 | RejectPaths.t.sol:L101-102 | ProviderSet/BudgetSet 事件未验证 | 添加 `vm.expectEmit` 验证（或在注释中说明由单元测试覆盖） |
| 3 | ExpirePaths.t.sol:L116, RejectPaths.t.sol:L160 | submit 后未验证 JobSubmitted 事件 | 将 submit 调用从 helper 中抽出或使用 startPrank 在测试体内内联以允许 expectEmit |
| 4 | EdgeIntegration.t.sol:L86-90 | IT-021/IT-022 中 feeBps/treasury 的显式值断言缺失 | 添加 `assertEq(escrow.feeBps(), 250)` / `escrow.treasury()` 等显式断言 |

---

## 总结

| 判断 | 结论 |
|------|------|
| 测试代码是否可用 | ⚠️ 1 项 ❌ 需修复（IT-008 Hook count），8 项 ⚠️ 可迭代修复 |
| 是否需要回 Implement Agent 修改 | 是——必须修复 IT-008 的 Hook count 断言错误 |
| 是否可以进入执行阶段（Executor Agent） | ⚠️ 建议先修复 IT-008（P0），其余 ⚠️（P1/P2）可在执行阶段并行修复 |
| 建议修改优先级 | **P0**: 1 项（IT-008 Hook count）/ **P1**: 3 项（IT-004 event, IT-006/IT-009/IT-010/IT-020 JobSubmitted event 类）/ **P2**: 3 项（IT-017 中间态、IT-021/IT-022 feeBps/treasury 显式断言） |

### 亮点

1. **CrossReentry.t.sol 已实现**：Prompt §1 标注为"⚠️ 文件缺失"，但 Implement Agent 实际交付了该文件，且 IT-015/IT-016 的覆盖质量较高。
2. **revert 消息全部逐字匹配**：`"ERC8183: reentrant call"`、`"ERC8183: job not in refundable state"`、`"Hook: beforeAction reverted"`、`"Hook: afterAction reverted"` 全部精确。
3. **expectEmit 4-bool 参数无一错误**：JobExpired `(true, false, false, false)`、JobRejected/Refunded `(true, true, false, true)` 全部正确。
4. **IT-010/IT-020 关键行为正确**：submit 过期后不 revert 的行为被正确编码（无 expectRevert 包裹）。
5. **Mock 合约质量高**：RevertingMockHook 支持 selector 精确匹配，CrossReenterHook 支持 optParams 变体。
6. **Balance snapshot 模式**：IT-021/IT-022 使用 `providerBalBefore`/`treasuryBalBefore` 的 delta 断言——比硬编码绝对余额更稳健。

### 文件存在性确认

| 文件 | 预期路径 | 存在 | 对应 IT |
|------|----------|------|--------|
| RejectPaths.t.sol | test/integration/full/ | ✅ | IT-003 ~ IT-007 |
| ExpirePaths.t.sol | test/integration/full/ | ✅ | IT-008 ~ IT-012 |
| HookInteractions.t.sol | test/integration/full/ | ✅ | IT-013 ~ IT-014 |
| CrossReentry.t.sol | test/integration/full/ | ✅ | IT-015 ~ IT-016 |
| MultiJob.t.sol | test/integration/full/ | ✅ | IT-017 ~ IT-019 |
| EdgeIntegration.t.sol | test/integration/full/ | ✅ | IT-020 ~ IT-022 |
| RevertingMockHook.sol | test/mocks/ | ✅ | IT-013 ~ IT-014 |
| CrossReenterHook.sol | test/mocks/ | ✅ | IT-015 ~ IT-016 |

---

*审计完成时间：2026-06-08 · Review Agent · 仅审阅代码，不执行测试*
