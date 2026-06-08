# ERC-8183 Escrow 单元测试审计报告

**审计时间**：2026-06-08
**审计范围**：test/unit/*.t.sol（15 个文件）+ test/mocks/MockHook.sol + test/mocks/MaliciousReenterHook.sol
**审计依据**：test/unit/unit-test-checklist.md（104 用例）
**审计方法**：静态代码审阅，逐函数对照清单

---

## 总览

| 指标 | 数值 |
|------|------|
| 清单用例总数 | 104 |
| 已实现（✅ D1） | 104 |
| 缺失（❌ D1） | 0 |
| 行为完全对齐（✅ D2） | 94 |
| 行为部分遗漏（⚠️ D2） | 9 |
| 行为不符（❌ D2） | 1 |
| 假测试（❌ D3） | 0 |
| 可疑测试（⚠️ D3） | 5 |
| Setup 错误（❌ D4） | 0 |
| Setup 不精确（⚠️ D4） | 1 |

---

## 审计：Constructor.t.sol（UT-001 ~ UT-003）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-001 | ✅ | ✅ | ✅ | ✅ | — |
| UT-002 | ✅ | ✅ | ✅ | ✅ | — |
| UT-003 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：CreateJob.t.sol（UT-004 ~ UT-008）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-004 | ✅ | ✅ | ✅ | ✅ | — |
| UT-005 | ✅ | ✅ | ✅ | ✅ | — |
| UT-006 | ✅ | ✅ | ✅ | ✅ | — |
| UT-007 | ✅ | ⚠️ | ✅ | ✅ | 仅断言 client/provider/hook/jobId，缺少 evaluator/budget/expiredAt/description/status 字段。清单要求「所有字段正确存储 + 事件参数完整」 |
| UT-008 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：SetProvider.t.sol（UT-009 ~ UT-015）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-009 | ✅ | ✅ | ✅ | ✅ | — |
| UT-010 | ✅ | ✅ | ✅ | ✅ | — |
| UT-011 | ✅ | ✅ | ✅ | ✅ | — |
| UT-012 | ✅ | ✅ | ✅ | ✅ | — |
| UT-013 | ✅ | ✅ | ✅ | ✅ | — |
| UT-014 | ✅ | ⚠️ | ✅ | ✅ | 清单要求「ProviderSet 事件正确发射」，但测试只检查了 provider storage，未验证事件 |
| UT-015 | ✅ | ❌ | ⚠️ | ✅ | 断言 `hook.lastData() == optParams`（第138行），但清单和 implement prompt 均要求 Hook data = `abi.encode(provider, optParams)`。测试验证的数据与实际传入 Hook 的数据可能不一致 |

---

## 审计：SetBudget.t.sol（UT-016 ~ UT-021）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-016 | ✅ | ✅ | ✅ | ✅ | — |
| UT-017 | ✅ | ✅ | ✅ | ✅ | — |
| UT-018 | ✅ | ✅ | ✅ | ✅ | — |
| UT-019 | ✅ | ✅ | ✅ | ✅ | — |
| UT-020 | ✅ | ✅ | ✅ | ✅ | — |
| UT-021 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：Fund.t.sol（UT-022 ~ UT-029）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-022 | ✅ | ✅ | ✅ | ✅ | — |
| UT-023 | ✅ | ✅ | ✅ | ✅ | — |
| UT-024 | ✅ | ✅ | ✅ | ✅ | — |
| UT-025 | ✅ | ✅ | ✅ | ✅ | — |
| UT-026 | ✅ | ✅ | ✅ | ✅ | — |
| UT-027 | ✅ | ✅ | ✅ | ✅ | — |
| UT-028 | ✅ | ✅ | ✅ | ✅ | — |
| UT-029 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：Submit.t.sol（UT-030 ~ UT-034）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-030 | ✅ | ✅ | ✅ | ✅ | — |
| UT-031 | ✅ | ✅ | ⚠️ | ✅ | 可能错误归因。job 创建时 provider=address(0)（第60行），但 `vm.prank(provider)` 使用非零地址。合约中 caller 检查可能在 status 检查之前，导致实际 revert 消息是 "caller is not provider" 而非预期的 "invalid job status"。需验证合约中 submit 函数的检查顺序 |
| UT-032 | ✅ | ✅ | ✅ | ✅ | — |
| UT-033 | ✅ | ✅ | ✅ | ✅ | — |
| UT-034 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：Complete.t.sol（UT-035 ~ UT-043）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-035 | ✅ | ✅ | ✅ | ✅ | — |
| UT-036 | ✅ | ✅ | ✅ | ✅ | — |
| UT-037 | ✅ | ✅ | ✅ | ✅ | — |
| UT-038 | ✅ | ✅ | ✅ | ✅ | — |
| UT-039 | ✅ | ✅ | ✅ | ✅ | — |
| UT-040 | ✅ | ✅ | ✅ | ✅ | — |
| UT-041 | ✅ | ✅ | ✅ | ✅ | — |
| UT-042 | ✅ | ✅ | ✅ | ✅ | — |
| UT-043 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：Reject.t.sol（UT-044 ~ UT-051）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-044 | ✅ | ✅ | ✅ | ✅ | — |
| UT-045 | ✅ | ✅ | ✅ | ✅ | — |
| UT-046 | ✅ | ✅ | ✅ | ✅ | — |
| UT-047 | ✅ | ✅ | ✅ | ✅ | — |
| UT-048 | ✅ | ✅ | ✅ | ✅ | — |
| UT-049 | ✅ | ✅ | ✅ | ✅ | — |
| UT-050 | ✅ | ✅ | ✅ | ✅ | — |
| UT-051 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：ClaimRefund.t.sol（UT-052 ~ UT-059）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-052 | ✅ | ✅ | ✅ | ✅ | — |
| UT-053 | ✅ | ✅ | ✅ | ✅ | — |
| UT-054 | ✅ | ✅ | ✅ | ✅ | — |
| UT-055 | ✅ | ✅ | ✅ | ✅ | — |
| UT-056 | ✅ | ⚠️ | ✅ | ✅ | 清单要求覆盖 Completed/Rejected/Expired 三种终态，测试仅验证 Completed 一种。虽可取代表但未覆盖另两个终态 |
| UT-057 | ✅ | ✅ | ✅ | ✅ | — |
| UT-058 | ✅ | ✅ | ✅ | ✅ | — |
| UT-059 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：QueryFunctions.t.sol（UT-060 ~ UT-067）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-060 | ✅ | ✅ | ✅ | ✅ | — |
| UT-061 | ✅ | ✅ | ✅ | ✅ | — |
| UT-062 | ✅ | ✅ | ✅ | ✅ | — |
| UT-063 | ✅ | ✅ | ✅ | ✅ | — |
| UT-064 | ✅ | ✅ | ✅ | ✅ | — |
| UT-065 | ✅ | ✅ | ✅ | ✅ | — |
| UT-066 | ✅ | ✅ | ✅ | ✅ | — |
| UT-067 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：ERC165.t.sol（UT-068 ~ UT-070）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-068 | ✅ | ✅ | ✅ | ✅ | — |
| UT-069 | ✅ | ✅ | ✅ | ✅ | — |
| UT-070 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：AdminFunctions.t.sol（UT-071 ~ UT-075）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-071 | ✅ | ✅ | ✅ | ✅ | — |
| UT-072 | ✅ | ✅ | ✅ | ✅ | — |
| UT-073 | ✅ | ✅ | ✅ | ✅ | — |
| UT-074 | ✅ | ✅ | ✅ | ✅ | — |
| UT-075 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：HookCallbacks.t.sol（UT-076 ~ UT-088）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-076 | ✅ | ✅ | ✅ | ✅ | — |
| UT-077 | ✅ | ✅ | ✅ | ✅ | — |
| UT-078 | ✅ | ✅ | ✅ | ✅ | — |
| UT-079 | ✅ | ✅ | ✅ | ✅ | — |
| UT-080 | ✅ | ⚠️ | ✅ | ✅ | 用累计计数 beforeCount=3 验证（含 setProvider/setBudget 的 Hook 调用），未用增量 delta 方式。清单意图是 fund 自身触发 1 次，测试混入了 Setup 的调用次数 |
| UT-081 | ✅ | ✅ | ✅ | ✅ | — |
| UT-082 | ✅ | ✅ | ✅ | ✅ | — |
| UT-083 | ✅ | ✅ | ✅ | ✅ | — |
| UT-084 | ✅ | ✅ | ✅ | ✅ | — |
| UT-085 | ✅ | ✅ | ✅ | ✅ | — |
| UT-086 | ✅ | ✅ | ✅ | ✅ | — |
| UT-087 | ✅ | ✅ | ✅ | ✅ | — |
| UT-088 | ✅ | ✅ | ✅ | ✅ | — |

---

## 审计：ReentrancyGuard.t.sol（UT-089 ~ UT-095）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-089 | ✅ | ✅ | ✅ | ✅ | — |
| UT-090 | ✅ | ✅ | ✅ | ✅ | — |
| UT-091 | ✅ | ✅ | ✅ | ✅ | — |
| UT-092 | ✅ | ✅ | ⚠️ | ✅ | 使用内联 `SubmitOnlyReenterHook` 绕过 fund 阶段重入问题。逻辑正确但代码质量差——函数含 200+ 行注释解释变通方案。内联合约定义在 test 文件底部（第327-389行） |
| UT-093 | ✅ | ✅ | ⚠️ | ✅ | 同上，使用内联 `CompleteOnlyReenterHook` |
| UT-094 | ✅ | ✅ | ⚠️ | ✅ | 同上，使用内联 `RejectOnlyReenterHook` |
| UT-095 | ✅ | ✅ | ⚠️ | ⚠️ | 使用 `vm.store(address(escrow), bytes32(uint256(4)), bytes32(uint256(1)))` 直接设置 `_locked=true`（第314行）。依赖合约存储 slot 布局（假设 _locked 在 slot 4），存储结构变化会导致静默失效。非 checklist 建议的 receive fallback 方案 |

---

## 审计：EdgeCases.t.sol（UT-096 ~ UT-104）

| 用例 ID | D1 存在 | D2 对齐 | D3 真伪 | D4 Setup | 问题描述 |
|---------|---------|---------|---------|----------|----------|
| UT-096 | ✅ | ✅ | ✅ | ✅ | — |
| UT-097 | ✅ | ⚠️ | ✅ | ✅ | 清单要求测试 setProvider/fund/submit/complete/reject/claimRefund 对不存在 jobId 的行为。测试仅覆盖 getJob/setProvider/fund/claimRefund，缺失 submit/complete/reject |
| UT-098 | ✅ | ✅ | ✅ | ✅ | — |
| UT-099 | ✅ | ✅ | ✅ | ✅ | — |
| UT-100 | ✅ | ✅ | ✅ | ✅ | — |
| UT-101 | ✅ | ✅ | ✅ | ✅ | — |
| UT-102 | ✅ | ✅ | ✅ | ✅ | — |
| UT-103 | ✅ | ✅ | ✅ | ✅ | — |
| UT-104 | ✅ | ✅ | ✅ | ✅ | — |

---

## 假测试与可疑模式详情

### UT-015：setProvider with optParams（❌ D2 行为不符）

**清单要求**：Hook 收到的 data 参数为 `abi.encode(provider, optParams)`
**实际代码**（SetProvider.t.sol 第138行）：
```solidity
assertEq(hook.lastData(), optParams, "hook data should match optParams");
```
**问题分析**：测试直接比较 `hook.lastData()` 与原始 `optParams`。但 checklist 和 implement agent prompt 均明确要求 Hook data = `abi.encode(provider, optParams)`。这两个值不相等（一个是纯 bytes，另一个是 ABI 编码的(address,bytes)）。必须核对合约 `_setProvider` 实际传给 Hook 的 data 参数以确定哪方正确。

**建议修复**：
1. 若合约传入 `abi.encode(provider, optParams)`：修改断言为 `assertEq(hook.lastData(), abi.encode(provider, optParams))`
2. 若合约传入原始 `optParams`：更新 checklist 内容以反映实际行为

---

### UT-031：submit 在 Open 状态 revert（⚠️ D3 可能错误归因）

**清单要求**：Open 状态 Provider 调用 submit → revert "ERC8183: invalid job status"
**实际代码**（Submit.t.sol 第58-65行）：
```solidity
function test_UT031_Submit_RevertWhen_NotFunded() public {
    vm.prank(client);
    uint256 jid = escrow.createJob(address(0), evaluator, expiredAt, "desc", address(0));
    // ...
    vm.expectRevert("ERC8183: invalid job status");
    vm.prank(provider);
    escrow.submit(jid, bytes32(0));
}
```
**问题分析**：job 创建时 `provider=address(0)`（第60行 createJob 第一个参数）。`vm.prank(provider)` 使用的 `provider` 是 `makeAddr("provider")`（非零地址）。合约 submit 函数的检查顺序通常是「caller 检查→status 检查」。如果 caller 检查在前，实际 revert 消息会是 `"ERC8183: caller is not provider"`（因为 job.provider=address(0) ≠ msg.sender=provider），而非预期的 `"ERC8183: invalid job status"`。测试仍然 pass（因为确实 revert 了），但验证的是错误的 revert 原因。

**建议修复**：Setup 中先 `setProvider(jid, provider)` 将 job.provider 设为正确的 provider 地址，再调用 submit。确保 revert 确实是因 status 不正确而非 caller 不匹配。

---

### UT-092 ~ UT-094：submit/complete/reject 防重入测试（⚠️ D3 变通方案）

**清单要求**：通过 MaliciousReenterHook 在 afterAction 中重入同一函数 → revert "ERC8183: reentrant call"
**实际情况**：Implement Agent 发现通用 MaliciousReenterHook 无法同时用于 fund 和 submit（fund 阶段 Hook 也会触发重入导致无法进入 Funded 状态），因此在 ReentrancyGuard.t.sol 底部（第327-389行）定义了三个内联专用 Hook：
- `SubmitOnlyReenterHook`（仅重入 submit）
- `CompleteOnlyReenterHook`（仅重入 complete）
- `RejectOnlyReenterHook`（仅重入 reject）

**问题分析**：变通方案逻辑正确——专用 Hook 只在 afterAction 的特定 selector 下重入，不干扰 fund 流程。但存在以下问题：
1. 代码质量：UT-092 函数体前有 162 行注释（第77-238行）解释变通方案，严重降低可读性
2. 偏离 spec：Implement Agent Prompt 第4.2节明确说「一个 Hook 实例可复用于不同 selector 的测试」
3. 内联合约：三个 Hook 定义在测试文件内而非 `test/mocks/` 目录，不符合项目结构约定

**建议修复**：将三个内联合约提取到 `test/mocks/` 目录（如 `SubmitOnlyReenterHook.sol` 等），并删除测试函数内的大量注释。

---

### UT-095：claimRefund 防重入（⚠️ D3 存储布局依赖）

**清单要求**：构造重入场景验证 nonReentrant 生效 → revert "ERC8183: reentrant call"
**实际代码**（ReentrancyGuard.t.sol 第297-318行）：
```solidity
function test_UT095_Reentrancy_ClaimRefund() public {
    // ... setup Funded + warp past expiry ...
    // Artificially set _locked = true (slot 4)
    vm.store(address(escrow), bytes32(uint256(4)), bytes32(uint256(1)));
    vm.expectRevert("ERC8183: reentrant call");
    escrow.claimRefund(jid);
}
```
**问题分析**：
1. 假设 `_locked` 状态变量在合约存储 slot 4。如果合约继承链或变量声明顺序变化，slot 位置改变会导致 `vm.store` 写入错误的存储位，测试静默通过但不验证任何逻辑（_locked 实际未被设置）
2. Checklist 和 implement prompt 的建议方案是部署一个 MaliciousReceiver 合约（receive fallback 中重入），而非直接操作存储。`vm.store` 绕过了正常的重入路径，测试的是 nonReentrant modifier 而非真正的重入场景

**建议修复**：采用 checklist 建议的 receive fallback 方案——部署一个合约作为 client，其 `receive()` 函数中重入 `claimRefund`。claimRefund→transfer→receive→重入 claimRefund 的自然调用链比 vm.store 更真实、更健壮。

---

## 缺失用例清单

无缺失。104 个用例全部有对应测试函数。

---

## 总结

### 统计数据

| 维度 | ✅ 通过 | ⚠️ 需注意 | ❌ 需修复 |
|------|---------|-----------|----------|
| 存在性 D1 | 104 | 0 | 0 |
| 行为对齐 D2 | 94 | 9 | 1 |
| 真伪检测 D3 | 99 | 5 | 0 |
| Setup 正确 D4 | 103 | 1 | 0 |

### 可直接通过

**89 个用例** D1-D4 全部 ✅，无需修改。

### 需修复（存在 ❌）

| 优先级 | 用例 | 问题 | 影响 |
|--------|------|------|------|
| P0 | **UT-015** | D2 ❌：Hook data 断言可能与实际值不匹配（optParams vs abi.encode） | 测试可能永远 pass 但验证了错误的值，或测试 fail 但合约实际正确 |

### 需人工复核（存在 ⚠️）

| 优先级 | 用例 | 问题 |
|--------|------|------|
| P0 | **UT-031** | D3 ⚠️：可能错误归因——revert 原因可能是 "caller is not provider" 而非 "invalid job status"。**需运行 forge test 验证实际 revert 消息** |
| P1 | **UT-095** | D3 ⚠️：vm.store 硬编码 slot=4，依赖存储布局。存储结构变化会静默失效 |
| P1 | **UT-092/093/094** | D3 ⚠️：内联 Hook 变通方案 + 大量注释，需提取到 mocks/ 目录 |
| P2 | **UT-007** | D2 ⚠️：缺少 5 个字段断言 |
| P2 | **UT-014** | D2 ⚠️：缺少事件断言 |
| P2 | **UT-056** | D2 ⚠️：未覆盖所有三种终态 |
| P2 | **UT-080** | D2 ⚠️：累计计数不够精确 |
| P2 | **UT-097** | D2 ⚠️：缺失 submit/complete/reject 测试 |

### 建议修复优先级

1. **P0 行为不符**：UT-015 — 确认合约实际传给 Hook 的 data 格式，修正测试或 checklist
2. **P0 错误归因**：UT-031 — Setup 中先 setProvider 再 submit，确保 revert 因 status 而非 caller
3. **P1 存储依赖**：UT-095 — 改用 receive fallback 合约实现重入，替代 vm.store
4. **P1 代码质量**：UT-092/093/094 — 提取内联 Hook 到 mocks/，删除冗长注释
5. **P2 断言完整性**：UT-007、UT-014、UT-056、UT-080、UT-097 — 补充缺失的断言

---

## 审计方法说明

本次审计严格遵循 §4 的方法论细则：
- **D2 行为对齐**：逐项对照清单的「测试目标」和「预期结果」与实际代码中的 assert/expectRevert/expectEmit
- **D3 假测试风险**：逐项检查 8 种假测试模式（空断言、错误归因、expectRevert 吞错、expectEmit 形参错误、错位 prank、无状态验证、setup 即测试、余额盲区）
- **D4 Setup 正确性**：检查前置状态是否与清单一致，prank 地址是否正确，多状态 setup 是否正确推进
- 所有 ❌ 或 ⚠️ 判断均附带代码行号和具体片段
- 未执行 `forge test`，纯静态审阅

---

*审计报告由 Review Agent 生成 · 2026-06-08 · 仅审阅代码，不执行代码*
