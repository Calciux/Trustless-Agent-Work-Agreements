# ERC-8183 Escrow 集成测试 — Happy Path Checklist

> 被测合约：`ERC8183Escrow`（EIP-8183 托管合约）
> 测试框架：Foundry (forge-std)
> 代币：MockERC20（18 位精度）
> 前置条件：Client 已对 Escrow 合约执行 `token.approve(escrow, budget)` 授信

---

## IT-001: 无手续费 Happy Path

| 参数 | 值 |
|------|-----|
| Constructor | `treasury=address(0)`, `feeBps=0` |
| Budget | `100` (即 `100 * 10^18`) |
| Hook | `address(0)` |
| 预期结果 | Provider 收 100，treasury 收 0，Escrow 余额 = 0 |

| # | 步骤 | msg.sender | 函数调用 / 关键参数 | 断言清单 |
|---|------|-----------|---------------------|----------|
| 1 | createJob | Client | `createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0))` | `jobId == 1`；`jobCount() == 1`；`getStatus(1) == Status.Open`；`getJob(1).client == Client`；`getJob(1).evaluator == evaluator`；`getJob(1).provider == address(0)`；`getJob(1).budget == 0`；emit `JobCreated(1, Client, address(0), evaluator, expiredAt)` |
| 2 | setProvider | Client | `setProvider(1, provider)` | `getJob(1).provider == provider`；emit `ProviderSet(1, provider)` |
| 3 | setBudget | Client | `setBudget(1, 100)` | `getJob(1).budget == 100`；emit `BudgetSet(1, 100)` |
| 4 | approve | Client | `token.approve(escrow, 100)`（在 fund 前完成） | `token.allowance(Client, escrow) >= 100` |
| 5 | fund | Client | `fund(1, expectedBudget=100)` | `getStatus(1) == Status.Funded`；`token.balanceOf(Client)` 减少 100；`token.balanceOf(escrow)` 增加 100；emit `JobFunded(1, Client, 100)` |
| 6 | submit | Provider | `submit(1, deliverable=bytes32("proof"))` | `getStatus(1) == Status.Submitted`；emit `JobSubmitted(1, provider, bytes32("proof"))` |
| 7 | complete | Evaluator | `complete(1, reason=bytes32("ok"))` | `getStatus(1) == Status.Completed`；`token.balanceOf(escrow) == 0`；`token.balanceOf(provider)` 增加 100；`token.balanceOf(treasury)` 不变；emit `JobCompleted(1, evaluator, bytes32("ok"))`；emit `PaymentReleased(1, provider, 100)` |

---

## IT-002: 有手续费 Happy Path

| 参数 | 值 |
|------|-----|
| Constructor | `treasury≠address(0)`, `feeBps=250`（2.5%） |
| Budget | `10000` (即 `10000 * 10^18`) |
| Hook | `address(0)` |
| 预期结果 | Provider 收 9750，treasury 收 250，Escrow 余额 = 0 |

| # | 步骤 | msg.sender | 函数调用 / 关键参数 | 断言清单 |
|---|------|-----------|---------------------|----------|
| 1 | createJob | Client | `createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0))` | `jobId == 1`；`jobCount() == 1`；`getStatus(1) == Status.Open`；`getJob(1).client == Client`；`getJob(1).evaluator == evaluator`；`getJob(1).provider == address(0)`；`getJob(1).budget == 0`；emit `JobCreated(1, Client, address(0), evaluator, expiredAt)` |
| 2 | setProvider | Client | `setProvider(1, provider)` | `getJob(1).provider == provider`；emit `ProviderSet(1, provider)` |
| 3 | setBudget | Client | `setBudget(1, 10000)` | `getJob(1).budget == 10000`；emit `BudgetSet(1, 10000)` |
| 4 | approve | Client | `token.approve(escrow, 10000)`（在 fund 前完成） | `token.allowance(Client, escrow) >= 10000` |
| 5 | fund | Client | `fund(1, expectedBudget=10000)` | `getStatus(1) == Status.Funded`；`token.balanceOf(Client)` 减少 10000；`token.balanceOf(escrow)` 增加 10000；emit `JobFunded(1, Client, 10000)` |
| 6 | submit | Provider | `submit(1, deliverable=bytes32("proof"))` | `getStatus(1) == Status.Submitted`；emit `JobSubmitted(1, provider, bytes32("proof"))` |
| 7 | complete | Evaluator | `complete(1, reason=bytes32("ok"))` | `getStatus(1) == Status.Completed`；`token.balanceOf(escrow) == 0`；`token.balanceOf(provider)` 增加 9750；`token.balanceOf(treasury)` 增加 250；emit `JobCompleted(1, evaluator, bytes32("ok"))`；emit `PaymentReleased(1, provider, 9750)` |

---

## 汇总表

| ID | 场景名称 | 操作序列 | 每步断言 | 优先级 |
|----|----------|----------|----------|--------|
| IT-001 | 无手续费 Happy Path | `createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)` → `setProvider(1, provider, sender=Client)` → `setBudget(1, 100, sender=Client)` → `fund(1, 100, sender=Client)` → `submit(1, bytes32("proof"), sender=Provider)` → `complete(1, bytes32("ok"), sender=Evaluator)` | createJob: jobId=1/count=1/Status.Open；setProvider: job.provider=provider；setBudget: budget=100；fund: Status.Funded + transferFrom(Client→Escrow, 100)；submit: Status.Submitted；complete: Status.Completed + Provider+100/Treasury+0/Escrow=0 + JobCompleted+PaymentReleased | P0 |
| IT-002 | 有手续费 Happy Path | `createJob(provider=address(0), evaluator, expiredAt, "desc", hook=address(0), sender=Client)` → `setProvider(1, provider, sender=Client)` → `setBudget(1, 10000, sender=Client)` → `fund(1, 10000, sender=Client)` → `submit(1, bytes32("proof"), sender=Provider)` → `complete(1, bytes32("ok"), sender=Evaluator)` | createJob: jobId=1/count=1/Status.Open；setProvider: job.provider=provider；setBudget: budget=10000；fund: Status.Funded + transferFrom(Client→Escrow, 10000)；submit: Status.Submitted；complete: Status.Completed + Provider+9750/Treasury+250/Escrow=0 + JobCompleted+PaymentReleased | P0 |

---

## 测试环境准备清单

| # | 操作 | 说明 |
|---|------|------|
| E-1 | 部署 MockERC20 | `new MockERC20("Test Token", "TTK", 18)`，给 Client mint `≥11000` token |
| E-2 | 部署 ERC8183Escrow (IT-001) | `new ERC8183Escrow(token, address(0), 0)` — 零手续费配置 |
| E-3 | 部署 ERC8183Escrow (IT-002) | `new ERC8183Escrow(token, treasury, 250)` — 2.5% 手续费配置 |
| E-4 | Client approve | `token.approve(escrow, budget)` — 在 fund 前执行 |
