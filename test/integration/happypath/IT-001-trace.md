# IT-001 链上交易记录 — 无手续费 Happy Path

> 测试函数：`test_IT001_HappyPath_NoFee`
> Gas 消耗：4,127,008
> 状态：✅ PASS

---

## 地址清单

| 角色 | 地址 |
|------|------|
| MockERC20 | `0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f` |
| ERC8183Escrow | `0x2e234DAe75C793f67A35089C9d99245E1C58470b` |
| Client | `0xD5e069BC58dedb2a3A348995ee753Eef0274004F` |
| Provider | `0x9B78803558F9Ea56F4f0a966322C8dD9B2fBebc0` |
| Evaluator | `0xCA5453e74F0CCC802aDd48A547cd965512fFd45d` |
| Treasury | `0x0000000000000000000000000000000000000000` |

## 配置

| 参数 | 值 |
|------|-----|
| feeBps | 0 |
| budget | 100 |
| deliverable | `0x70726f6f6600...` ("proof") |
| reason | `0x6f6b00000000...` ("ok") |

---

## 交易列表（共 10 笔状态变更 tx）

### Tx #1 — 部署 MockERC20

| 字段 | 值 |
|------|-----|
| 合约 | MockERC20 |
| 地址 | `0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f` |
| Gas | 497,328 |

无存储变更（构造时写入的 slot 未在下层列出）。

---

### Tx #2 — 部署 ERC8183Escrow

| 字段 | 值 |
|------|-----|
| 合约 | ERC8183Escrow |
| 地址 | `0x2e234DAe75C793f67A35089C9d99245E1C58470b` |
| Constructor 参数 | `token=MockERC20`, `treasury=address(0)`, `feeBps=0` |
| Gas | 3,729,685 |

---

### Tx #3 — MockERC20.mint(client, 100)

| 字段 | 值 |
|------|-----|
| caller | setUp (部署者) |
| 函数 | `mint(client, 100)` |
| Gas | 23,041 |

**存储变更**：
```
slot 0xc30b735f...e23d6 (client balance): 0 → 100
```

---

### Tx #4 — ERC8183Escrow.createJob (Step 1)

| 字段 | 值 |
|------|-----|
| msg.sender | Client (`0xD5e...004F`) |
| 函数 | `createJob(address(0), evaluator, 604801, "desc", address(0))` |
| Gas | 123,451 |

**事件**：
```
JobCreated(jobId=1, client=0xD5e...004F, provider=0x0,
           evaluator=0xCA5...d45d, expiredAt=604801)
```

**存储变更**：
```
slot 2 (jobCount):                       0 → 1
slot 0xa15b...4e (job[1].evaluator):     0 → 0xCA5...d45d
slot 0xa15b...4c (job[1].client):        0 → 0xD5e...004F
slot 0xa15b...4f (job[1].description):   0 → "desc"
slot 0xa15b...51 (job[1].expiredAt):     0 → 604801
```

**返回值**：`jobId = 1`

---

### Tx #5 — ERC8183Escrow.setProvider (Step 2)

| 字段 | 值 |
|------|-----|
| msg.sender | Client (`0xD5e...004F`) |
| 函数 | `setProvider(1, provider)` |
| Gas | 46,458 |

**事件**：
```
ProviderSet(jobId=1, provider=0x9B7...ebc0)
```

**存储变更**：
```
slot 0xa15b...4d (job[1].provider): 0 → 0x9B7...ebc0
```

---

### Tx #6 — ERC8183Escrow.setBudget (Step 3)

| 字段 | 值 |
|------|-----|
| msg.sender | Client (`0xD5e...004F`) |
| 函数 | `setBudget(1, 100)` |
| Gas | 43,987 |

**事件**：
```
BudgetSet(jobId=1, amount=100)
```

**存储变更**：
```
slot 0xa15b...50 (job[1].budget): 0 → 100
```

---

### Tx #7 — MockERC20.approve (Step 4)

| 字段 | 值 |
|------|-----|
| msg.sender | Client (`0xD5e...004F`) |
| 函数 | `approve(Escrow, 100)` |
| Gas | 23,085 |

**存储变更**：
```
slot 0xc6e3...a35a (allowance[Client][Escrow]): 0 → 100
```

**返回值**：`true`

---

### Tx #8 — ERC8183Escrow.fund (Step 5)

| 字段 | 值 |
|------|-----|
| msg.sender | Client (`0xD5e...004F`) |
| 函数 | `fund(1, expectedBudget=100)` |
| Gas | 69,288 |

**内部调用**：
```
MockERC20.transferFrom(Client → Escrow, 100) — gas 23,032
```

**事件**：
```
JobFunded(jobId=1, client=0xD5e...004F, amount=100)
```

**存储变更**：
```
slot 0xc6e3...a35a (allowance[Client][Escrow]):   100 → 0
slot 0xc30b...e23d6 (Client balance):              100 → 0
slot 0xc6bd...8579 (Escrow balance):                 0 → 100
slot 0xa15b...52 (job[1].status):                    0 → 1 (Funded)
```

---

### Tx #9 — ERC8183Escrow.submit (Step 6)

| 字段 | 值 |
|------|-----|
| msg.sender | Provider (`0x9B7...ebc0`) |
| 函数 | `submit(1, deliverable=0x70726f6f66...)` |
| Gas | 24,731 |

**事件**：
```
JobSubmitted(jobId=1, provider=0x9B7...ebc0,
             deliverable=0x70726f6f6600...)   // "proof"
```

**存储变更**：
```
slot 0xa15b...52 (job[1].status): 1 → 2 (Submitted)
```

---

### Tx #10 — ERC8183Escrow.complete (Step 7)

| 字段 | 值 |
|------|-----|
| msg.sender | Evaluator (`0xCA5...d45d`) |
| 函数 | `complete(1, reason=0x6f6b0000...)` |
| Gas | 49,965 |

**内部调用**：
```
MockERC20.transfer(Provider, 100) — gas 21,994
```

**事件**：
```
JobCompleted(jobId=1, evaluator=0xCA5...d45d, reason=0x6f6b0000...)   // "ok"
PaymentReleased(jobId=1, provider=0x9B7...ebc0, amount=100)
```

**存储变更**：
```
slot 0x8801...c8ec (Provider balance):  0 → 100
slot 0xc6bd...8579 (Escrow balance):  100 → 0
slot 0xa15b...52 (job[1].status):      2 → 3 (Completed)
```

---

## 最终余额

| 账户 | 余额变化 | 最终余额 |
|------|---------|---------|
| Client | `-100` | `0` |
| Escrow | `+100 -100` | `0` |
| Provider | `+100` | `100` |
| Treasury | `0` | `0` |

---

## 原始 Trace（完整）

```
[552408] HappyPathTest::setUp()
  ├─ [497328] → new MockERC20@0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f
  │   └─ ← [Return] 2484 bytes of code
  └─ ← [Stop]

[4286208] HappyPathTest::test_IT001_HappyPath_NoFee()
  ├─ [3729685] → new ERC8183Escrow@0x2e234DAe75C793f67A35089C9d99245E1C58470b
  │   └─ ← [Return] 18600 bytes of code
  ├─ [23041] MockERC20::mint(client, 100)
  │   ├─  storage changes:
  │   │   @ 0xc30b...e23d6: 0 → 100
  │   └─ ← [Stop]
  ├─ [0] VM::prank(client)
  ├─ [0] VM::expectEmit(true,true,true,true)
  ├─ emit JobCreated(jobId=1, client=0xD5e...004F, provider=0x0, evaluator=0xCA5...d45d, expiredAt=604801)
  ├─ [123451] ERC8183Escrow::createJob(0x0, 0xCA5...d45d, 604801, "desc", 0x0)
  │   ├─ emit JobCreated(...)
  │   ├─  storage changes: jobCount→1, job[1].{evaluator,client,description,expiredAt}
  │   └─ ← [Return] 1
  ├─ [0] VM::assertEq(1, 1)
  ├─ [455] ERC8183Escrow::jobCount() [staticcall] → 1
  ├─ [0] VM::assertEq(1, 1)
  ├─ [1128] ERC8183Escrow::getStatus(1) [staticcall] → 0
  ├─ [0] VM::assertEq(0, 0)
  ├─ [4643] ERC8183Escrow::getJob(1) [staticcall]
  │   └─ ← Job({client,provider=0x0,evaluator,desc,budget=0,expiredAt,status=0,hook=0x0})
  ├─ [0] VM::assertEq(client, client)
  ├─ [0] VM::assertEq(evaluator, evaluator)
  ├─ [0] VM::assertEq(0x0, 0x0)
  ├─ [0] VM::assertEq(0, 0)
  ├─ [0] VM::prank(client)
  ├─ [0] VM::expectEmit(true,true,false,false)
  ├─ emit ProviderSet(jobId=1, provider=0x9B7...ebc0)
  ├─ [46458] ERC8183Escrow::setProvider(1, 0x9B7...ebc0)
  │   ├─ emit ProviderSet(...)
  │   ├─  storage changes: job[1].provider → 0x9B7...ebc0
  │   └─ ← [Stop]
  ├─ [4643] ERC8183Escrow::getJob(1) [staticcall] → provider=0x9B7...ebc0
  ├─ [0] VM::assertEq(provider, provider)
  ├─ [0] VM::prank(client)
  ├─ [0] VM::expectEmit(true,false,false,true)
  ├─ emit BudgetSet(jobId=1, amount=100)
  ├─ [43987] ERC8183Escrow::setBudget(1, 100)
  │   ├─ emit BudgetSet(...)
  │   ├─  storage changes: job[1].budget → 100
  │   └─ ← [Stop]
  ├─ [4643] ERC8183Escrow::getJob(1) [staticcall] → budget=100
  ├─ [0] VM::assertEq(100, 100)
  ├─ [0] VM::prank(client)
  ├─ [23085] MockERC20::approve(Escrow, 100)
  │   ├─  storage changes: allowance[Client][Escrow] → 100
  │   └─ ← [Return] true
  ├─ [1170] MockERC20::allowance(Client, Escrow) [staticcall] → 100
  ├─ [0] VM::assertGe(100, 100)
  ├─ [845] MockERC20::balanceOf(Client) [staticcall] → 100
  ├─ [2845] MockERC20::balanceOf(Escrow) [staticcall] → 0
  ├─ [0] VM::prank(client)
  ├─ [0] VM::expectEmit(true,true,false,true)
  ├─ emit JobFunded(jobId=1, client=0xD5e...004F, amount=100)
  ├─ [69288] ERC8183Escrow::fund(1, 100)
  │   ├─ [23032] MockERC20::transferFrom(Client, Escrow, 100)
  │   │   ├─ storage: allowance→0, Client bal→0, Escrow bal→100
  │   │   └─ ← true
  │   ├─ emit JobFunded(...)
  │   ├─  storage changes: job[1].status → 1 (Funded)
  │   └─ ← [Stop]
  ├─ [1128] ERC8183Escrow::getStatus(1) [staticcall] → 1
  ├─ [0] VM::assertEq(1, 1)
  ├─ [845] MockERC20::balanceOf(Client) [staticcall] → 0
  ├─ [0] VM::assertEq(0, 0)
  ├─ [845] MockERC20::balanceOf(Escrow) [staticcall] → 100
  ├─ [0] VM::assertEq(100, 100)
  ├─ [0] VM::prank(provider)
  ├─ [0] VM::expectEmit(true,true,false,true)
  ├─ emit JobSubmitted(jobId=1, provider=0x9B7...ebc0, deliverable=0x70726f6f66...)
  ├─ [24731] ERC8183Escrow::submit(1, 0x70726f6f66...)
  │   ├─ emit JobSubmitted(...)
  │   ├─  storage changes: job[1].status → 2 (Submitted)
  │   └─ ← [Stop]
  ├─ [1128] ERC8183Escrow::getStatus(1) [staticcall] → 2
  ├─ [0] VM::assertEq(2, 2)
  ├─ [2845] MockERC20::balanceOf(Provider) [staticcall] → 0
  ├─ [2845] MockERC20::balanceOf(Treasury=0x0) [staticcall] → 0
  ├─ [0] VM::prank(evaluator)
  ├─ [0] VM::expectEmit(true,true,false,true)
  ├─ emit JobCompleted(jobId=1, evaluator=0xCA5...d45d, reason=0x6f6b00...)
  ├─ [0] VM::expectEmit(true,true,false,true)
  ├─ emit PaymentReleased(jobId=1, provider=0x9B7...ebc0, amount=100)
  ├─ [49965] ERC8183Escrow::complete(1, 0x6f6b00...)
  │   ├─ [21994] MockERC20::transfer(Provider, 100)
  │   │   ├─ storage: Provider bal→100, Escrow bal→0
  │   │   └─ ← true
  │   ├─ emit JobCompleted(...)
  │   ├─ emit PaymentReleased(...)
  │   ├─  storage changes: job[1].status → 3 (Completed)
  │   └─ ← [Stop]
  ├─ [1128] ERC8183Escrow::getStatus(1) [staticcall] → 3
  ├─ [0] VM::assertEq(3, 3)
  ├─ [845] MockERC20::balanceOf(Escrow) [staticcall] → 0
  ├─ [0] VM::assertEq(0, 0)
  ├─ [845] MockERC20::balanceOf(Provider) [staticcall] → 100
  ├─ [0] VM::assertEq(100, 100)
  ├─ [845] MockERC20::balanceOf(Treasury=0x0) [staticcall] → 0
  ├─ [0] VM::assertEq(0, 0)
  └─ ← [Stop]
```
