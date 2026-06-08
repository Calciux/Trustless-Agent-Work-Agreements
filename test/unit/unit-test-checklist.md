# ERC-8183 Escrow — 单元测试清单

> **生成环境**：编译器 solc `0.8.21`，EVM `shanghai`，Foundry forge  
> **被测合约**：`contracts/ERC8183Escrow.sol` (540 lines)  
> **Mock 代币**：`test/mocks/MockERC20.sol`  
> **清单类型**：单元测试（每个用例仅测一个外部函数的一个行为分支）

---

## 测试覆盖矩阵

| 被测函数 | 用例数 | P0 | P1 | P2 |
|----------|--------|----|----|-----|
| `constructor` | 3 | 2 | 1 | 0 |
| `createJob` | 5 | 3 | 2 | 0 |
| `setProvider` | 7 | 5 | 2 | 0 |
| `setBudget` | 6 | 4 | 2 | 0 |
| `fund` | 8 | 5 | 3 | 0 |
| `submit` | 5 | 4 | 1 | 0 |
| `complete` | 9 | 6 | 2 | 1 |
| `reject` | 8 | 6 | 2 | 0 |
| `claimRefund` | 8 | 5 | 2 | 1 |
| `getJob` | 3 | 2 | 1 | 0 |
| `getStatus` | 2 | 1 | 1 | 0 |
| `jobCount` | 2 | 1 | 1 | 0 |
| `paymentToken` | 1 | 1 | 0 | 0 |
| `supportsInterface` | 3 | 2 | 1 | 0 |
| `setTreasury` | 2 | 2 | 0 | 0 |
| `setFeeBps` | 3 | 2 | 1 | 0 |
| **Hook 回调（跨函数）** | 13 | 0 | 8 | 5 |
| **防重入（跨函数）** | 7 | 7 | 0 | 0 |
| **边界与边缘** | 9 | 1 | 5 | 3 |
| **总计** | **104** | **59** | **34** | **11** |

---

## 完整测试清单

### A. 构造函数 `constructor`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-001 | `constructor` | `paymentToken=address(0)` 导致部署失败 | 部署时传入 `paymentToken_ = address(0)` | revert `"ERC8183: payment token zero address"` | P0 |
| UT-002 | `constructor` | `feeBps > MAX_FEE_BPS(10000)` 导致部署失败 | 部署时传入 `feeBps_ = 10001` | revert `"ERC8183: fee too high"` | P0 |
| UT-003 | `constructor` | 正常部署后 storage 变量正确初始化 | 传入合法参数 `(token, treasury, 250)` | `owner=msg.sender`，`paymentToken()=token`，`treasury=treasury`，`feeBps=250`，`jobCount()=0` | P1 |

### B. `createJob`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-004 | `createJob` | 正常创建（provider=address(0), hook=address(0)） | 部署后首次调用，合法 evaluator 和 future expiredAt | `jobId=1`，job struct 各字段正确存储（client=msg.sender, provider=0, status=Open, budget=0），发射 `JobCreated(1, client, 0, evaluator, expiredAt)` | P0 |
| UT-005 | `createJob` | `evaluator=address(0)` 导致 revert | 传入 `evaluator = address(0)` | revert `"ERC8183: evaluator is zero address"` | P0 |
| UT-006 | `createJob` | `expiredAt ≤ block.timestamp` 导致 revert | 传入 `expiredAt = block.timestamp` 或 `block.timestamp - 1` | revert `"ERC8183: expiredAt not in future"` | P0 |
| UT-007 | `createJob` | provider≠0 且 hook≠0 时所有字段正确存储 + 事件参数完整 | 传入非零 provider 和 hook 地址 | job struct 中 provider 和 hook 字段非零；`JobCreated` 事件 5 个参数与输入一致 | P1 |
| UT-008 | `createJob` | jobId 连续自增（1→2→3） | 连续调用 3 次 createJob | 返回的 jobId 依次为 1、2、3，`jobCount()` 同步递增 | P1 |

### C. `setProvider`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-009 | `setProvider` | Client 在 Open 状态首次设置 provider → 成功 | 创建 job1（provider=0），Client 调用 setProvider(job1, newProvider) | `job.provider=newProvider`，发射 `ProviderSet(job1, newProvider)` | P0 |
| UT-010 | `setProvider` | `provider=address(0)` 导致 revert | job 处于 Open 且 provider 未设置，Client 调用 setProvider(jobId, 0) | revert `"ERC8183: provider is zero address"` | P0 |
| UT-011 | `setProvider` | provider 已被设置后再次设置 → revert | job 已通过 setProvider 设置过 provider（非零），Client 再次调用 | revert `"ERC8183: provider already set"` | P0 |
| UT-012 | `setProvider` | 非 Open 状态（Funded）调用 → revert | job 已 fund 进入 Funded 状态，Client 调用 setProvider | revert `"ERC8183: invalid job status"` | P0 |
| UT-013 | `setProvider` | 非 Client 调用 → revert | 随机地址（非 job.client）调用 setProvider | revert `"ERC8183: caller is not client"` | P0 |
| UT-014 | `setProvider` | 无 optParams 版本正常路由到 `_setProvider` | 调用 `setProvider(uint256,address)` 两参数版本 | 行为与 UT-009 一致，ProviderSet 事件正确发射 | P1 |
| UT-015 | `setProvider` | 带 optParams 版本正常路由 + optParams 透传给 Hook | 调用 `setProvider(uint256,address,bytes)` 三参数版本，传入非空 optParams | 行为与 UT-009 一致，Hook 收到的 data 参数为 `abi.encode(provider, optParams)` | P1 |

### D. `setBudget`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-016 | `setBudget` | Client 在 Open 状态设置 budget → 成功 | 创建 job1，Client 调用 setBudget(job1, 100) | `job.budget=100`，发射 `BudgetSet(job1, 100)` | P0 |
| UT-017 | `setBudget` | Provider 在 Open 状态设置 budget → 成功 | 创建 job1 并 setProvider(provider)，Provider 调用 setBudget(job1, 200) | `job.budget=200`，发射 `BudgetSet(job1, 200)` | P0 |
| UT-018 | `setBudget` | 既非 Client 也非 Provider 调用 → revert | 随机地址调用 setBudget（job 的 client 和 provider 均不是该地址） | revert `"ERC8183: caller not client or provider"` | P0 |
| UT-019 | `setBudget` | 非 Open 状态（Funded）调用 → revert | job 已 fund，Client 调用 setBudget | revert `"ERC8183: invalid job status"` | P0 |
| UT-020 | `setBudget` | budget 设为 0 应允许（代码无 `>0` 约束） | 创建 job1，Client 调用 setBudget(job1, 0) | `job.budget=0`，不 revert，发射 `BudgetSet(job1, 0)` | P1 |
| UT-021 | `setBudget` | 无 optParams + 带 optParams 版本均正确路由 | 分别调用两参数和三参数版本 | 内部均进入 `_setBudget`，行为一致 | P1 |

### E. `fund`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-022 | `fund` | Happy Path：Client 注资 → Open→Funded | job 已设 provider + budget=100，Client approve 合约 100 token 额度，调用 fund(jobId, 100) | `job.status=Funded`，合约余额+100，Client 余额-100，发射 `JobFunded(jobId, client, 100)` | P0 |
| UT-023 | `fund` | `expectedBudget ≠ job.budget` → revert（防抢跑） | job.budget=100，调用 fund(jobId, 99) | revert `"ERC8183: budget mismatch"`，状态保持 Open | P0 |
| UT-024 | `fund` | budget 未设置（=0）→ revert | job 未调 setBudget（budget=0），Client 调用 fund | revert `"ERC8183: budget not set"` | P0 |
| UT-025 | `fund` | provider 未设置 → revert | job 未设 provider（=address(0)），已设 budget>0，Client 调用 fund | revert `"ERC8183: provider not set"` | P0 |
| UT-026 | `fund` | 非 Client 调用 → revert | 非 job.client 地址调用 fund | revert `"ERC8183: caller is not client"` | P0 |
| UT-027 | `fund` | 非 Open 状态（已 Funded）→ revert | job 已处于 Funded 状态，Client 再次调用 fund | revert `"ERC8183: invalid job status"` | P1 |
| UT-028 | `fund` | transferFrom 失败（Client 余额不足）→ revert 并回滚 | job budget=1000，Client 余额=500，approve 到位 | revert `"ERC8183: transferFrom failed"`，状态保持 Open | P1 |
| UT-029 | `fund` | 无 optParams + 带 optParams 版本均正确路由 | 分别调用两参数和三参数版本 | 均触发完整注资流程，行为一致 | P1 |

### F. `submit`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-030 | `submit` | Provider 在 Funded 状态提交 → Funded→Submitted | job 处于 Funded，Provider 调用 submit(jobId, deliverable) | `job.status=Submitted`，发射 `JobSubmitted(jobId, provider, deliverable)` | P0 |
| UT-031 | `submit` | 非 Funded 状态（Open）→ revert | job 处于 Open，Provider 调用 submit | revert `"ERC8183: invalid job status"` | P0 |
| UT-032 | `submit` | 非 Provider 调用 → revert | 非 job.provider 地址调用 submit | revert `"ERC8183: caller is not provider"` | P0 |
| UT-033 | `submit` | `deliverable=bytes32(0)` 应允许 | job 处于 Funded，Provider 调用 submit(jobId, bytes32(0)) | 正常转为 Submitted，发射事件携带 `deliverable=bytes32(0)` | P1 |
| UT-034 | `submit` | 无 optParams + 带 optParams 版本均正确路由 | 分别调用两参数版和三参数版 | 行为一致 | P0 |

### G. `complete`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-035 | `complete` | Evaluator 在 Submitted 状态 complete → Submitted→Completed | job 处于 Submitted（budget=1000），Evaluator 调用 complete | `job.status=Completed`，Provider 收款 1000，发射 `JobCompleted` + `PaymentReleased(jobId, provider, 1000)` | P0 |
| UT-036 | `complete` | 无手续费时（treasury=address(0)）→ Provider 收全额 | 部署时 treasury=address(0)，feeBps=500 | Provider 收款 = budget（全额），treasury 余额不变，不发射 `PaymentReleased` 以外的转账事件 | P0 |
| UT-037 | `complete` | 无手续费时（feeBps=0）→ Provider 收全额 | treasury≠0 但 feeBps=0 | 同 UT-036，无手续费扣除 | P0 |
| UT-038 | `complete` | 有手续费时 → Provider 收款 = budget - fee，treasury 收 fee | treasury≠0，feeBps=250（2.5%），budget=10000 | Provider 收款 9750，treasury 收款 250 | P0 |
| UT-039 | `complete` | feeBps=MAX_FEE_BPS(10000=100%) → Provider 收 0 | treasury≠0，feeBps=10000，budget=1000 | Provider 收款=0，treasury 收款=1000，`PaymentReleased(jobId, provider, 0)` | P1 |
| UT-040 | `complete` | treasury=address(0) 且 feeBps>0 → 手续费逻辑不触发 | 部署 treasury=0，feeBps=500 | Provider 收全额，条件 `treasury != address(0) && feeBps > 0` 为 false | P1 |
| UT-041 | `complete` | 非 Submitted 状态（Funded）→ revert | job 处于 Funded（未 submit），Evaluator 调用 complete | revert `"ERC8183: invalid job status"` | P0 |
| UT-042 | `complete` | 非 Evaluator 调用 → revert | job 处于 Submitted，非 job.evaluator 调用 complete | revert `"ERC8183: caller is not evaluator"` | P0 |
| UT-043 | `complete` | 无 optParams + 带 optParams 版本均正确路由 | 分别调用两参数和三参数版本 | 行为一致 | P2 |

### H. `reject`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-044 | `reject` | Open 状态 + Client 调用 → Open→Rejected（无退款） | job 处于 Open，Client 调用 reject | `job.status=Rejected`，发射 `JobRejected(jobId, client, reason)`，**不发射** `Refunded`，合约余额不变 | P0 |
| UT-045 | `reject` | Funded 状态 + Evaluator 调用 → Funded→Rejected + 全额退款 | job 处于 Funded（budget=1000），Evaluator 调用 reject | `job.status=Rejected`，Client 收 1000 退款，发射 `JobRejected` + `Refunded(jobId, client, 1000)` | P0 |
| UT-046 | `reject` | Submitted 状态 + Evaluator 调用 → Submitted→Rejected + 全额退款 | job 处于 Submitted（budget=1000），Evaluator 调用 reject | `job.status=Rejected`，Client 收 1000 退款，发射 `JobRejected` + `Refunded(jobId, client, 1000)` | P0 |
| UT-047 | `reject` | Open 状态 + 非 Client 调用 → revert | job 处于 Open，非 Client 地址调用 reject | revert `"ERC8183: caller not client"` | P0 |
| UT-048 | `reject` | Funded 状态 + 非 Evaluator 调用 → revert | job 处于 Funded，非 Evaluator 调用 reject | revert `"ERC8183: caller not evaluator"` | P0 |
| UT-049 | `reject` | Submitted 状态 + 非 Evaluator 调用 → revert | job 处于 Submitted，非 Evaluator 调用 reject | revert `"ERC8183: caller not evaluator"` | P0 |
| UT-050 | `reject` | 终态（Completed/Rejected/Expired）调用 → revert | job 已为终态（如 Completed），调用 reject | revert `"ERC8183: invalid job status for reject"` | P1 |
| UT-051 | `reject` | 无 optParams + 带 optParams 版本均正确路由 | 分别调用两参数和三参数版本 | 行为一致 | P1 |

### I. `claimRefund`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-052 | `claimRefund` | Funded 状态 + 已过期 → Expired + 全额退款 | job 处于 Funded（budget=500），`vm.warp` 至 expiredAt 之后，任意地址调用 claimRefund | `job.status=Expired`，Client 收 500 退款，发射 `JobExpired(jobId)` + `Refunded(jobId, client, 500)` | P0 |
| UT-053 | `claimRefund` | Submitted 状态 + 已过期 → Expired + 全额退款 | job 处于 Submitted（budget=500），warp 过过期时间 | 同 UT-052，Client 收 500 退款 | P0 |
| UT-054 | `claimRefund` | 未过期（block.timestamp < expiredAt）→ revert | job 处于 Funded，未 warp（或 warp 但未到过期时间） | revert `"ERC8183: job not expired"` | P0 |
| UT-055 | `claimRefund` | Open 状态 → revert | job 处于 Open（无论是否过期） | revert `"ERC8183: job not in refundable state"` | P0 |
| UT-056 | `claimRefund` | Completed/Rejected/Expired 状态 → revert | job 已处于终态 | revert `"ERC8183: job not in refundable state"` | P0 |
| UT-057 | `claimRefund` | 任何人可调用（随机地址非 Client/Provider/Evaluator） | job 处于 Funded + 已过期，随机地址调用 | 成功执行退款，证明无 caller 角色限制 | P1 |
| UT-058 | `claimRefund` | 未到期（expiredAt 设为未来很远）→ revert | 未 warp，block.timestamp < expiredAt | revert `"ERC8183: job not expired"`（边界：恰好等于时 block.timestamp >= expiredAt 成立） | P1 |
| UT-059 | `claimRefund` | Hook≠address(0) 时不调用 beforeAction/afterAction | job 绑定合法 Hook 合约，warp 过过期时间 | claimRefund 成功但 Hook 合约无任何调用记录（与下面 §M 对比验证） | P2 |

### J. 查询函数

#### J1. `getJob`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-060 | `getJob` | 存在时返回完整 Job struct | 创建 job1 并获取 | 返回 struct 各字段与存储一致 | P0 |
| UT-061 | `getJob` | `jobId=0` → revert | 调用 getJob(0) | revert `"ERC8183: job not found"` | P0 |
| UT-062 | `getJob` | `jobId > jobCount` → revert | 调用 getJob(999) 或 getJob(jobCount+1) | revert `"ERC8183: job not found"` | P1 |

#### J2. `getStatus`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-063 | `getStatus` | 返回正确状态枚举值 | 分别对 Open 和 Funded 的 job 调用 | 返回 `Status.Open`(0) 和 `Status.Funded`(1) | P0 |
| UT-064 | `getStatus` | 不存在的 jobId → revert | 调用 getStatus(0) | revert `"ERC8183: job not found"` | P1 |

#### J3. `jobCount`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-065 | `jobCount` | 部署后为 0 | 刚部署，未创建任何 job | 返回 0 | P0 |
| UT-066 | `jobCount` | createJob 后递增 | 创建 1 个 job 后查询 | 返回 1；再创建 1 个后返回 2 | P1 |

#### J4. `paymentToken`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-067 | `paymentToken` | 返回部署时传入的代币地址 | 部署时传入 tokenAddr | 返回 tokenAddr | P0 |

### K. ERC-165 `supportsInterface`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-068 | `supportsInterface` | `type(IERC8183).interfaceId` → true | 调用 supportsInterface(IERC8183 的 interfaceId) | 返回 true | P0 |
| UT-069 | `supportsInterface` | `type(IERC165).interfaceId` → true | 调用 supportsInterface(IERC165 的 interfaceId) | 返回 true | P0 |
| UT-070 | `supportsInterface` | 随机 bytes4（如 `0xffffffff`）→ false | 调用 supportsInterface(0xffffffff) | 返回 false | P1 |

### L. 管理函数 `setTreasury` / `setFeeBps`

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-071 | `setTreasury` | owner 调用 → 成功更新 storage | owner 调用 setTreasury(newAddr) | `treasury=newAddr` | P0 |
| UT-072 | `setTreasury` | 非 owner 调用 → revert | 随机地址调用 setTreasury | revert `"ERC8183: caller is not owner"` | P0 |
| UT-073 | `setFeeBps` | owner 调用 + feeBps ≤ MAX_FEE_BPS → 成功 | owner 调用 setFeeBps(500) | `feeBps=500` | P0 |
| UT-074 | `setFeeBps` | feeBps > MAX_FEE_BPS → revert | owner 调用 setFeeBps(10001) | revert `"ERC8183: fee too high"` | P0 |
| UT-075 | `setFeeBps` | 非 owner 调用 → revert | 随机地址调用 setFeeBps(100) | revert `"ERC8183: caller is not owner"` | P1 |

### M. Hook 回调触发

> **说明**：需部署一个 Mock Hook 合约实现 `IACPHook` 接口，通过事件或 storage 标记记录调用。以下每个用例验证一个核心函数在 hook≠0 和 hook=0 时的回调行为。claimRefund 是唯一不可 Hook 的函数（协议级安全要求），需单独验证其反向行为。

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-076 | `setProvider` | hook≠0 时调用 beforeAction + afterAction | job 绑定 Mock Hook，Client 调用 setProvider | Mock Hook 记录到 beforeAction 和 afterAction 各被调用 1 次，selector 为 `setProvider(uint256,address)` 或扩展版 | P1 |
| UT-077 | `setProvider` | hook=0 时不调用 Hook | job.hook=address(0)，Client 调用 setProvider | 操作成功，Mock Hook 无调用记录 | P2 |
| UT-078 | `setBudget` | hook≠0 时调用 beforeAction + afterAction | job 绑定 Mock Hook，Client/Provider 调用 setBudget | beforeAction + afterAction 各 1 次，selector 匹配 | P1 |
| UT-079 | `setBudget` | hook=0 时不调用 Hook | job.hook=address(0) | 操作成功，无 Hook 调用 | P2 |
| UT-080 | `fund` | hook≠0 时调用 beforeAction + afterAction | job 绑定 Mock Hook，Client 调用 fund | beforeAction + afterAction 各 1 次 | P1 |
| UT-081 | `fund` | hook=0 时不调用 Hook | job.hook=address(0) | 操作成功，无 Hook 调用 | P2 |
| UT-082 | `submit` | hook≠0 时调用 beforeAction + afterAction | job 绑定 Mock Hook，Provider 调用 submit | beforeAction + afterAction 各 1 次 | P1 |
| UT-083 | `submit` | hook=0 时不调用 Hook | job.hook=address(0) | 操作成功，无 Hook 调用 | P2 |
| UT-084 | `complete` | hook≠0 时调用 beforeAction + afterAction | job 绑定 Mock Hook，Evaluator 调用 complete | beforeAction + afterAction 各 1 次 | P1 |
| UT-085 | `complete` | hook=0 时不调用 Hook | job.hook=address(0) | 操作成功，无 Hook 调用 | P2 |
| UT-086 | `reject` | hook≠0 时调用 beforeAction + afterAction | job 绑定 Mock Hook，Client(Open)/Evaluator(Funded) 调用 reject | beforeAction + afterAction 各 1 次 | P1 |
| UT-087 | `reject` | hook=0 时不调用 Hook | job.hook=address(0) | 操作成功，无 Hook 调用 | P2 |
| UT-088 | `claimRefund` | **hook≠0 时也不调用 beforeAction/afterAction**（与上述 6 函数行为相反） | job 绑定 Mock Hook，warp 过过期时间，调用 claimRefund | claimRefund 成功执行退款，Mock Hook 无任何调用记录 | P1 |

### N. 防重入

> **方法**：为每个 `nonReentrant` 修饰的函数部署一个恶意 Mock Hook，在 `afterAction` 回调中重入**同一函数**。预期 revert `"ERC8183: reentrant call"`。

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-089 | `setProvider` | 防重入：Hook afterAction 中重入 setProvider → revert | 恶意 Hook 在 afterAction 中调 setProvider(jobId, anotherAddr) | revert `"ERC8183: reentrant call"` | P0 |
| UT-090 | `setBudget` | 防重入：Hook afterAction 中重入 setBudget → revert | 恶意 Hook 在 afterAction 中调 setBudget | revert `"ERC8183: reentrant call"` | P0 |
| UT-091 | `fund` | 防重入：Hook afterAction 中重入 fund → revert | 恶意 Hook 在 afterAction 中调 fund | revert `"ERC8183: reentrant call"` | P0 |
| UT-092 | `submit` | 防重入：Hook afterAction 中重入 submit → revert | 恶意 Hook 在 afterAction 中调 submit | revert `"ERC8183: reentrant call"` | P0 |
| UT-093 | `complete` | 防重入：Hook afterAction 中重入 complete → revert | 恶意 Hook 在 afterAction 中调 complete | revert `"ERC8183: reentrant call"` | P0 |
| UT-094 | `reject` | 防重入：Hook afterAction 中重入 reject → revert | 恶意 Hook 在 afterAction 中调 reject | revert `"ERC8183: reentrant call"` | P0 |
| UT-095 | `claimRefund` | 防重入：直接重入 claimRefund → revert | 不通过 Hook（claimRefund 不调 Hook），需通过其他方式构造重入场景（如 receive fallback） | revert `"ERC8183: reentrant call"` | P0 |

### O. 边界与边缘

| ID | 被测函数 | 测试目标 | 前置条件 | 预期结果 | 优先级 |
|----|----------|----------|----------|----------|--------|
| UT-096 | `createJob` | `expiredAt = block.timestamp + 1` → 成功（恰好 > now） | 传入 `expiredAt = block.timestamp + 1` | 成功创建，job.expiredAt 为该值 | P1 |
| UT-097 | `createJob` / 状态变更函数 | 不存在的 jobId（0 或超大值）调用核心函数 → revert | 对 jobId=0 调用 setProvider/fund/submit/complete/reject/claimRefund | 各函数因 modifier/内联检查 revert（具体消息取决于函数：`"caller is not client"` / `"job not found"` / `"job not in refundable state"`） | P1 |
| UT-098 | `complete` | 同一 job complete 后再次 complete → revert | 先 complete 进入 Completed 终态，再次 complete | revert `"ERC8183: invalid job status"` | P1 |
| UT-099 | `reject` | 同一 job reject 后再次 reject → revert | 先 reject 进入 Rejected 终态，再次 reject | revert `"ERC8183: invalid job status for reject"` | P1 |
| UT-100 | `setBudget` + `fund` | budget 极值 `type(uint256).max` | setBudget(type(uint256).max)，mint+approve 等量，fund | 正常注资和后续结算（注意手续费计算需用 SafeMath 等效逻辑，无溢出） | P1 |
| UT-101 | `createJob` | jobId 自增不回溯：job1 终态后 job2 仍为 2 | createJob→fund→complete（job1 终态），再 createJob | 第二次 createJob 返回 jobId=2，jobCount()=2 | P1 |
| UT-102 | `fund` | `expectedBudget=0` 且 `budget=0`（未 setBudget）→ 验证检查顺序 | job 未 setBudget（budget=0），调用 fund(jobId, 0) | revert `"ERC8183: budget not set"`（`require(budget > 0)` 在 `require(budget == expectedBudget)` 之前执行） | P2 |
| UT-103 | `constructor` | 部署时 `feeBps` 恰好 = `MAX_FEE_BPS(10000)` | 部署传入 feeBps_=10000 | 成功部署，`feeBps=10000` | P2 |
| UT-104 | `claimRefund` | `block.timestamp == expiredAt` 恰好相等 → 可退款 | warp 至 expiredAt（刚好等于），调用 claimRefund | 成功退款（`block.timestamp >= job.expiredAt` 包含等于） | P2 |

---

## 附录 A：测试环境说明

### A.1 MockERC20 能力

| 功能 | 方法 | 备注 |
|------|------|------|
| 铸造代币 | `mint(address to, uint256 amount)` | 无权限控制，任意地址可调用 |
| 授权额度 | `approve(address spender, uint256 amount)` | 直接覆盖写入，非增量 |
| 转账 | `transfer(address to, uint256 amount)` | require 余额足够 |
| 代扣转账 | `transferFrom(address from, address to, uint256 amount)` | require 余额 + 额度双重检查；递减 allowance |
| 余额查询 | `balanceOf(address)` | 公开 mapping |
| 额度查询 | `allowance(address, address)` | 公开 mapping |

**注意**：MockERC20 不发射标准 ERC-20 Transfer/Approval 事件，测试中不能用 `vm.expectEmit` 匹配 Transfer 事件。

### A.2 Foundry Cheatcode 清单

测试中将使用以下 Foundry cheatcode：

| Cheatcode | 用途 | 典型用法 |
|-----------|------|----------|
| `vm.prank(address)` | 下一次调用以指定地址为 msg.sender | `vm.prank(client); escrow.createJob(...);` |
| `vm.startPrank(address)` / `vm.stopPrank()` | 连续多次调用以指定地址为 msg.sender | 设置→注资→submit 连续操作 |
| `vm.warp(uint256)` | 修改 block.timestamp | 跳过过期时间：`vm.warp(expiredAt + 1);` |
| `vm.expectRevert(bytes)` / `vm.expectRevert()` | 断言下一次调用 revert | `vm.expectRevert("ERC8183: budget not set");` |
| `vm.expectEmit(bool,bool,bool,bool)` + emit 语句 | 断言下一次调用发射指定事件 | 需传入 indexed 参数数量和 emitter 地址 |
| `vm.assume(bool)` | Fuzz 测试前置条件过滤 | 限定参数范围（如 `vm.assume(addr != address(0))`） |
| `vm.deal(address, uint256)` | 给地址 ETH 余额（ETH 相关测试） | 本合约不涉及 ETH，可能不需 |
| `vm.getRecordedLogs()` | 获取 emit 的所有日志 | 用于 Hook 调用验证 |
| `vm.recordLogs()` | 开始记录日志 | 配合 getRecordedLogs 使用 |
| `address(escrow).balance` | 查询合约 ETH 余额 | 同上，本合约不涉及 ETH |

### A.3 测试文件结构建议

```
test/
├── unit/
│   ├── unit-test-checklist.md          ← 本文件
│   ├── Constructor.t.sol               # UT-001 ~ UT-003
│   ├── CreateJob.t.sol                 # UT-004 ~ UT-008
│   ├── SetProvider.t.sol               # UT-009 ~ UT-015
│   ├── SetBudget.t.sol                 # UT-016 ~ UT-021
│   ├── Fund.t.sol                      # UT-022 ~ UT-029
│   ├── Submit.t.sol                    # UT-030 ~ UT-034
│   ├── Complete.t.sol                  # UT-035 ~ UT-043
│   ├── Reject.t.sol                    # UT-044 ~ UT-051
│   ├── ClaimRefund.t.sol               # UT-052 ~ UT-059
│   ├── QueryFunctions.t.sol            # UT-060 ~ UT-067
│   ├── ERC165.t.sol                    # UT-068 ~ UT-070
│   ├── AdminFunctions.t.sol            # UT-071 ~ UT-075
│   ├── HookCallbacks.t.sol             # UT-076 ~ UT-088
│   ├── ReentrancyGuard.t.sol           # UT-089 ~ UT-095
│   └── EdgeCases.t.sol                 # UT-096 ~ UT-104
├── integration/
│   ├── happypath/
│   │   ├── HappyPath.t.sol             # IT-001/IT-002（Happy Path）
│   │   ├── happy-path-checklist.md
│   │   └── ...（trace/report 等辅助文件）
│   └── full/
│       ├── integration-test-checklist.md  # IT-003~IT-022 完整集成清单
│       ├── implement-agent-prompt.md
│       └── ...（6 个测试合约文件，待实现）
└── mocks/
    ├── MockERC20.sol                   ← 已存在
    ├── MockHook.sol                    # IACPHook 实现（记录调用）
    └── MaliciousReenterHook.sol        # 恶意 Hook（afterAction 中重入）
```

---

*清单生成日期：2026-06-08 · Plan Agent · 仅设计，不写测试代码*
