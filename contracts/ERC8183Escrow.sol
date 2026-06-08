// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IERC165} from "./interfaces/IERC165.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IACPHook} from "./interfaces/IACPHook.sol";
import {IERC8183} from "./interfaces/IERC8183.sol";

// ============================================================
// ERC8183Escrow — EIP-8183 完整实现
// ============================================================
contract ERC8183Escrow is IERC8183 {
    // ========== 函数选择器常量（用于 Hook 回调，避免重载歧义） ==========

    // 无 optParams 版本的选择器
    bytes4 private constant SEL_SETPROVIDER = bytes4(keccak256("setProvider(uint256,address)"));
    bytes4 private constant SEL_SETBUDGET = bytes4(keccak256("setBudget(uint256,uint256)"));
    bytes4 private constant SEL_FUND = bytes4(keccak256("fund(uint256,uint256)"));
    bytes4 private constant SEL_SUBMIT = bytes4(keccak256("submit(uint256,bytes32)"));
    bytes4 private constant SEL_COMPLETE = bytes4(keccak256("complete(uint256,bytes32)"));
    bytes4 private constant SEL_REJECT = bytes4(keccak256("reject(uint256,bytes32)"));

    // 带 optParams 版本的选择器
    bytes4 private constant SEL_SETPROVIDER_EXT = bytes4(keccak256("setProvider(uint256,address,bytes)"));
    bytes4 private constant SEL_SETBUDGET_EXT = bytes4(keccak256("setBudget(uint256,uint256,bytes)"));
    bytes4 private constant SEL_FUND_EXT = bytes4(keccak256("fund(uint256,uint256,bytes)"));
    bytes4 private constant SEL_SUBMIT_EXT = bytes4(keccak256("submit(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_COMPLETE_EXT = bytes4(keccak256("complete(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_REJECT_EXT = bytes4(keccak256("reject(uint256,bytes32,bytes)"));

    // ========== 存储变量 ==========

    // @notice 合约部署者（拥有管理权限）
    address public immutable owner;

    // @notice 支付代币合约（内部使用 IERC20 接口，对外返回 address）
    IERC20Minimal private immutable _paymentToken;

    // @notice 平台手续费接收地址
    address public treasury;

    // @notice 平台手续费费率（基点 bps：250 = 2.5%，10000 = 100%）
    uint256 public feeBps;

    // @notice 最大手续费费率上限
    uint256 public constant MAX_FEE_BPS = 10000;

    // @notice 任务计数器（自增，从 1 开始）
    uint256 private _jobCounter;

    // @notice 任务映射表：jobId → Job
    mapping(uint256 => Job) private _jobs;

    // @notice 防重入锁
    bool private _locked;

    // ========== 修饰器 ==========

    // @dev 防重入：阻止嵌套调用（包括通过 Hook 回调重入）
    modifier nonReentrant() {
        require(!_locked, "ERC8183: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    // @dev 仅限合约部署者调用
    modifier onlyOwner() {
        require(msg.sender == owner, "ERC8183: caller is not owner");
        _;
    }

    // @dev 仅限任务客户调用
    modifier onlyClient(uint256 jobId) {
        require(_jobs[jobId].client == msg.sender, "ERC8183: caller is not client");
        _;
    }

    // @dev 仅限任务提供者调用
    modifier onlyProvider(uint256 jobId) {
        require(_jobs[jobId].provider == msg.sender, "ERC8183: caller is not provider");
        _;
    }

    // @dev 仅限任务裁决者调用
    modifier onlyEvaluator(uint256 jobId) {
        require(_jobs[jobId].evaluator == msg.sender, "ERC8183: caller is not evaluator");
        _;
    }

    // @dev 要求任务处于指定状态
    modifier onlyStatus(uint256 jobId, Status requiredStatus) {
        require(_jobs[jobId].status == requiredStatus, "ERC8183: invalid job status");
        _;
    }

    // ========== 构造函数 ==========

    // @notice 部署托管合约
    // @param paymentToken_ 支付代币合约地址（不可为零地址）
    // @param treasury_ 平台手续费接收地址（可设为零地址表示不收费）
    // @param feeBps_ 手续费费率（基点，不得超过 MAX_FEE_BPS）
    constructor(address paymentToken_, address treasury_, uint256 feeBps_) {
        require(paymentToken_ != address(0), "ERC8183: payment token zero address");
        require(feeBps_ <= MAX_FEE_BPS, "ERC8183: fee too high");
        owner = msg.sender;
        _paymentToken = IERC20Minimal(paymentToken_);
        treasury = treasury_;
        feeBps = feeBps_;
    }

    // ========== ERC-165 接口检测 ==========

    // @notice 检查合约是否实现了指定接口
    // @param interfaceId 4 字节接口标识符
    // @return true 如果实现了该接口
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC8183).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ========== 管理函数 ==========

    // @notice 更新平台手续费接收地址（仅部署者）
    function setTreasury(address treasury_) external onlyOwner {
        treasury = treasury_;
    }

    // @notice 更新平台手续费费率（仅部署者）
    function setFeeBps(uint256 feeBps_) external onlyOwner {
        require(feeBps_ <= MAX_FEE_BPS, "ERC8183: fee too high");
        feeBps = feeBps_;
    }

    // ========== 查询函数 ==========

    // @notice 获取支付代币合约地址
    function paymentToken() external view override returns (address) {
        return address(_paymentToken);
    }

    // @notice 获取任务完整信息
    function getJob(uint256 jobId) external view override returns (Job memory) {
        require(jobId > 0 && jobId <= _jobCounter, "ERC8183: job not found");
        return _jobs[jobId];
    }

    // @notice 获取任务当前状态
    function getStatus(uint256 jobId) external view override returns (Status) {
        require(jobId > 0 && jobId <= _jobCounter, "ERC8183: job not found");
        return _jobs[jobId].status;
    }

    // @notice 获取当前任务总数
    function jobCount() external view returns (uint256) {
        return _jobCounter;
    }

    // ========== 核心函数：创建任务 ==========

    // @notice 创建新的托管任务
    // @param provider 服务提供者地址（可为 address(0)，后续通过 setProvider 设置）
    // @param evaluator 裁决者地址（不可为 address(0)）
    // @param expiredAt 过期时间戳（必须大于当前区块时间）
    // @param description 任务描述文本
    // @param hook 可选的 Hook 合约地址（address(0) 表示不使用 Hook）
    // @return jobId 新创建的任务 ID
    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external override returns (uint256 jobId) {
        // SHALL revert if evaluator is zero or expiredAt is not in the future
        require(evaluator != address(0), "ERC8183: evaluator is zero address");
        require(expiredAt > block.timestamp, "ERC8183: expiredAt not in future");

        // 自增任务 ID（从 1 开始）
        jobId = ++_jobCounter;

        // Provider MAY be zero; hook MAY be address(0)
        _jobs[jobId] = Job({
            client: msg.sender,
            provider: provider,
            evaluator: evaluator,
            description: description,
            budget: 0,
            expiredAt: expiredAt,
            status: Status.Open,
            hook: hook
        });

        emit JobCreated(jobId, msg.sender, provider, evaluator, expiredAt);
    }

    // ========== 核心函数：设置提供者 ==========

    // @notice 设置服务提供者地址（无 optParams）
    function setProvider(uint256 jobId, address provider) external override {
        _setProvider(jobId, provider, "", SEL_SETPROVIDER);
    }

    // @notice 设置服务提供者地址（带 optParams，透传 Hook）
    function setProvider(uint256 jobId, address provider, bytes calldata optParams) external override {
        _setProvider(jobId, provider, optParams, SEL_SETPROVIDER_EXT);
    }

    // @dev 内部实现：设置提供者
    // @dev SHALL revert if job is not Open, current job.provider != address(0), or provider == address(0)
    function _setProvider(uint256 jobId, address provider, bytes memory optParams, bytes4 selector)
        private
        nonReentrant
        onlyClient(jobId)
        onlyStatus(jobId, Status.Open)
    {
        Job storage job = _jobs[jobId];

        // 提供者只能设置一次，且新提供者不可为零地址
        require(job.provider == address(0), "ERC8183: provider already set");
        require(provider != address(0), "ERC8183: provider is zero address");

        // Hook: beforeAction
        _callBeforeHook(job.hook, jobId, selector, optParams);

        // SHALL set job.provider = provider
        job.provider = provider;

        emit ProviderSet(jobId, provider);

        // Hook: afterAction
        _callAfterHook(job.hook, jobId, selector, optParams);
    }

    // ========== 核心函数：设置预算 ==========

    // @notice 设置任务预算（无 optParams）
    function setBudget(uint256 jobId, uint256 amount) external override {
        _setBudget(jobId, amount, "", SEL_SETBUDGET);
    }

    // @notice 设置任务预算（带 optParams，透传 Hook）
    function setBudget(uint256 jobId, uint256 amount, bytes calldata optParams) external override {
        _setBudget(jobId, amount, optParams, SEL_SETBUDGET_EXT);
    }

    // @dev 内部实现：设置预算
    // @dev SHALL revert if job is not Open or caller is not client or provider
    function _setBudget(uint256 jobId, uint256 amount, bytes memory optParams, bytes4 selector)
        private
        nonReentrant
        onlyStatus(jobId, Status.Open)
    {
        Job storage job = _jobs[jobId];

        // 调用者必须是客户或提供者
        require(msg.sender == job.client || msg.sender == job.provider, "ERC8183: caller not client or provider");

        // Hook: beforeAction
        _callBeforeHook(job.hook, jobId, selector, optParams);

        // SHALL set job.budget = amount
        job.budget = amount;

        emit BudgetSet(jobId, amount);

        // Hook: afterAction
        _callAfterHook(job.hook, jobId, selector, optParams);
    }

    // ========== 核心函数：注资 ==========

    // @notice 客户向托管注资（无 optParams）
    function fund(uint256 jobId, uint256 expectedBudget) external override {
        _fund(jobId, expectedBudget, "", SEL_FUND);
    }

    // @notice 客户向托管注资（带 optParams，透传 Hook）
    function fund(uint256 jobId, uint256 expectedBudget, bytes calldata optParams) external override {
        _fund(jobId, expectedBudget, optParams, SEL_FUND_EXT);
    }

    // @dev 内部实现：注资
    // @dev SHALL revert if job is not Open, caller is not client, budget is zero,
    //      provider is not set, or job.budget != expectedBudget
    function _fund(uint256 jobId, uint256 expectedBudget, bytes memory optParams, bytes4 selector)
        private
        nonReentrant
        onlyClient(jobId)
        onlyStatus(jobId, Status.Open)
    {
        Job storage job = _jobs[jobId];

        // 预算必须已设置（大于 0）
        require(job.budget > 0, "ERC8183: budget not set");
        // 提供者必须已设置
        require(job.provider != address(0), "ERC8183: provider not set");
        // 防前端抢跑：校验 expectedBudget 防止夹子攻击篡改预算
        require(job.budget == expectedBudget, "ERC8183: budget mismatch");

        // Hook: beforeAction
        _callBeforeHook(job.hook, jobId, selector, optParams);

        // 状态转换：Open → Funded（checks-effects-interactions：先改状态）
        job.status = Status.Funded;

        // SHALL transfer job.budget of the payment token from client to escrow
        // （客户需事先对托管合约执行 approve）
        require(_paymentToken.transferFrom(msg.sender, address(this), job.budget), "ERC8183: transferFrom failed");

        emit JobFunded(jobId, msg.sender, job.budget);

        // Hook: afterAction
        _callAfterHook(job.hook, jobId, selector, optParams);
    }

    // ========== 核心函数：提交交付物 ==========

    // @notice 提供者提交交付物（无 optParams）
    function submit(uint256 jobId, bytes32 deliverable) external override {
        _submit(jobId, deliverable, "", SEL_SUBMIT);
    }

    // @notice 提供者提交交付物（带 optParams，透传 Hook）
    function submit(uint256 jobId, bytes32 deliverable, bytes calldata optParams) external override {
        _submit(jobId, deliverable, optParams, SEL_SUBMIT_EXT);
    }

    // @dev 内部实现：提交交付物
    // @dev SHALL revert if job is not Funded or caller is not the job's provider
    function _submit(uint256 jobId, bytes32 deliverable, bytes memory optParams, bytes4 selector)
        private
        nonReentrant
        onlyProvider(jobId)
        onlyStatus(jobId, Status.Funded)
    {
        Job storage job = _jobs[jobId];

        // Hook: beforeAction
        _callBeforeHook(job.hook, jobId, selector, optParams);

        // 状态转换：Funded → Submitted
        job.status = Status.Submitted;

        // deliverable 为 bytes32 哈希（链下交付物证明）
        emit JobSubmitted(jobId, msg.sender, deliverable);

        // Hook: afterAction
        _callAfterHook(job.hook, jobId, selector, optParams);
    }

    // ========== 核心函数：确认完成并放款 ==========

    // @notice 裁决者确认任务完成（无 optParams）
    function complete(uint256 jobId, bytes32 reason) external override {
        _complete(jobId, reason, "", SEL_COMPLETE);
    }

    // @notice 裁决者确认任务完成（带 optParams，透传 Hook）
    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external override {
        _complete(jobId, reason, optParams, SEL_COMPLETE_EXT);
    }

    // @dev 内部实现：确认完成并放款
    // @dev SHALL revert if job is not Submitted or caller is not the job's evaluator
    //      手续费仅在 Completed 时扣除（Rejected/Expired 不收费）
    function _complete(uint256 jobId, bytes32 reason, bytes memory optParams, bytes4 selector)
        private
        nonReentrant
        onlyEvaluator(jobId)
        onlyStatus(jobId, Status.Submitted)
    {
        Job storage job = _jobs[jobId];

        // Hook: beforeAction
        _callBeforeHook(job.hook, jobId, selector, optParams);

        // 状态转换：Submitted → Completed（checks-effects-interactions：先改状态）
        job.status = Status.Completed;

        // 快照值（防止重入场景下读取被修改）
        uint256 escrowBalance = job.budget;
        address providerAddr = job.provider;

        // 计算手续费（仅在配置了 treasury 且 feeBps > 0 时）
        uint256 fee = 0;
        uint256 payAmount = escrowBalance;
        if (treasury != address(0) && feeBps > 0) {
            fee = (escrowBalance * feeBps) / MAX_FEE_BPS;
            payAmount = escrowBalance - fee;
        }

        // 放款给 Provider（扣除手续费后的金额）
        require(_paymentToken.transfer(providerAddr, payAmount), "ERC8183: payment transfer failed");

        // 支付平台手续费（如果有）
        if (fee > 0) {
            require(_paymentToken.transfer(treasury, fee), "ERC8183: fee transfer failed");
        }

        // 事件：状态确认 + 金额明细
        emit JobCompleted(jobId, msg.sender, reason);
        emit PaymentReleased(jobId, providerAddr, payAmount);

        // Hook: afterAction
        _callAfterHook(job.hook, jobId, selector, optParams);
    }

    // ========== 核心函数：拒绝任务 ==========

    // @notice 拒绝任务（无 optParams）
    function reject(uint256 jobId, bytes32 reason) external override {
        _reject(jobId, reason, "", SEL_REJECT);
    }

    // @notice 拒绝任务（带 optParams，透传 Hook）
    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external override {
        _reject(jobId, reason, optParams, SEL_REJECT_EXT);
    }

    // @dev 内部实现：拒绝任务
    // @dev Called by client when job is Open
    //      or by evaluator when job is Funded or Submitted
    //      SHALL revert if job is not Open/Funded/Submitted or caller unauthorized
    //      If Funded/Submitted, SHALL refund escrow to client
    function _reject(uint256 jobId, bytes32 reason, bytes memory optParams, bytes4 selector) private nonReentrant {
        Job storage job = _jobs[jobId];
        Status currentStatus = job.status;

        // 权限检查（根据当前状态分支）
        if (currentStatus == Status.Open) {
            // Open 状态：仅 Client 可拒绝（无资金托管，无需退款）
            require(msg.sender == job.client, "ERC8183: caller not client");
        } else if (currentStatus == Status.Funded || currentStatus == Status.Submitted) {
            // Funded/Submitted 状态：仅 Evaluator 可拒绝
            require(msg.sender == job.evaluator, "ERC8183: caller not evaluator");
        } else {
            // Completed/Rejected/Expired：终态不允许再次拒绝
            revert("ERC8183: invalid job status for reject");
        }

        // Hook: beforeAction
        _callBeforeHook(job.hook, jobId, selector, optParams);

        // 状态转换 → Rejected
        job.status = Status.Rejected;

        // 退款逻辑（仅 Funded/Submitted 有托管资金需退还）
        bool shouldRefund = (currentStatus == Status.Funded || currentStatus == Status.Submitted);
        address refundTarget = job.client;
        uint256 refundAmount = 0;

        if (shouldRefund) {
            refundAmount = job.budget;
            require(_paymentToken.transfer(refundTarget, refundAmount), "ERC8183: refund transfer failed");
        }

        // 事件：rejector = msg.sender（Client 或 Evaluator） + 如有退款则 Refunded
        emit JobRejected(jobId, msg.sender, reason);
        if (shouldRefund && refundAmount > 0) {
            emit Refunded(jobId, refundTarget, refundAmount);
        }

        // Hook: afterAction
        _callAfterHook(job.hook, jobId, selector, optParams);
    }

    // ========== 核心函数：过期退款 ==========

    // @notice 任务过期后任何人可调用，退还托管资金给客户
    // @dev Callable when job is Funded/Submitted and block.timestamp >= expiredAt
    //      ⚠️ 安全底线：此函数不经过 Hook — 防止恶意 Hook 阻断退款通路
    function claimRefund(uint256 jobId) external override nonReentrant {
        Job storage job = _jobs[jobId];
        Status currentStatus = job.status;

        // SHALL revert if job is not Funded or Submitted
        require(
            currentStatus == Status.Funded || currentStatus == Status.Submitted, "ERC8183: job not in refundable state"
        );

        // SHALL revert if the job has not yet expired (EIP: block.timestamp >= expiredAt)
        require(block.timestamp >= job.expiredAt, "ERC8183: job not expired");

        // 状态转换 → Expired（checks-effects-interactions：先改状态）
        job.status = Status.Expired;

        // SHALL transfer full escrow to client
        uint256 refundAmount = job.budget;
        address refundTarget = job.client;

        require(_paymentToken.transfer(refundTarget, refundAmount), "ERC8183: refund transfer failed");

        // 事件：状态确认 + 退款金额明细
        emit JobExpired(jobId);
        emit Refunded(jobId, refundTarget, refundAmount);

        // ⚠️ 故意不调用 Hook — claimRefund 是唯一不可 Hook 的函数
        // 这是 EIP-8183 的协议级安全要求
    }

    // ========== 内部辅助：Hook 调用 ==========

    // @dev 调用 Hook 合约的 beforeAction（如果设置了 Hook）
    function _callBeforeHook(address hook, uint256 jobId, bytes4 selector, bytes memory data) private {
        if (hook != address(0)) {
            IACPHook(hook).beforeAction(jobId, selector, data);
        }
    }

    // @dev 调用 Hook 合约的 afterAction（如果设置了 Hook）
    function _callAfterHook(address hook, uint256 jobId, bytes4 selector, bytes memory data) private {
        if (hook != address(0)) {
            IACPHook(hook).afterAction(jobId, selector, data);
        }
    }
}
