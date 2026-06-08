// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IERC165} from "./IERC165.sol";

/**
 * @title IERC8183 — Agentic Commerce Protocol
 * @dev Job escrow with evaluator attestation for agent commerce.
 * https://eips.ethereum.org/EIPS/eip-8183
 *
 * 6-state machine: Open → Funded → Submitted → Completed / Rejected / Expired
 *
 * Roles:
 *   Client    — creates job, funds escrow, may reject only when Open
 *   Provider  — submits work, receives payment on Completed
 *   Evaluator — sole authority to complete or reject after submission
 */
interface IERC8183 is IERC165 {
    // ── Status ──────────────────────────────────────────────────────

    enum Status {
        Open, // Created; budget may be set, then funded or rejected
        Funded, // Budget escrowed; provider may submit, evaluator may reject
        Submitted, // Provider has submitted work; only evaluator may complete/reject
        Completed, // Terminal; escrow released to provider (minus fees)
        Rejected, // Terminal; escrow refunded to client
        Expired // Terminal; same as Rejected, triggered by timeout
    }

    // ── Job Data ────────────────────────────────────────────────────

    struct Job {
        address client;
        address provider; // MAY be address(0) at creation
        address evaluator;
        string description;
        uint256 budget;
        uint256 expiredAt;
        Status status;
        address hook; // address(0) if no hook
    }

    // ── Events ──────────────────────────────────────────────────────

    event JobCreated(
        uint256 indexed jobId, address indexed client, address indexed provider, address evaluator, uint256 expiredAt
    );

    event ProviderSet(uint256 indexed jobId, address indexed provider);

    event BudgetSet(uint256 indexed jobId, uint256 amount);

    event JobFunded(uint256 indexed jobId, address indexed client, uint256 amount);

    event JobSubmitted(uint256 indexed jobId, address indexed provider, bytes32 deliverable);

    event JobCompleted(uint256 indexed jobId, address indexed evaluator, bytes32 reason);

    event JobRejected(uint256 indexed jobId, address indexed rejector, bytes32 reason);

    event JobExpired(uint256 indexed jobId);

    event PaymentReleased(uint256 indexed jobId, address indexed provider, uint256 amount);

    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);

    // ── Core Functions ──────────────────────────────────────────────

    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external returns (uint256 jobId);

    // setProvider: two overloads — without and with optParams (OPTIONAL)
    function setProvider(uint256 jobId, address provider) external;
    function setProvider(uint256 jobId, address provider, bytes calldata optParams) external;

    // setBudget: two overloads
    function setBudget(uint256 jobId, uint256 amount) external;
    function setBudget(uint256 jobId, uint256 amount, bytes calldata optParams) external;

    // fund: two overloads
    function fund(uint256 jobId, uint256 expectedBudget) external;
    function fund(uint256 jobId, uint256 expectedBudget, bytes calldata optParams) external;

    // submit: two overloads
    function submit(uint256 jobId, bytes32 deliverable) external;
    function submit(uint256 jobId, bytes32 deliverable, bytes calldata optParams) external;

    // complete: two overloads
    function complete(uint256 jobId, bytes32 reason) external;
    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external;

    // reject: two overloads
    function reject(uint256 jobId, bytes32 reason) external;
    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external;

    // claimRefund: NOT hookable — no optParams overload
    function claimRefund(uint256 jobId) external;

    // ── Getters ─────────────────────────────────────────────────────

    function getJob(uint256 jobId) external view returns (Job memory);

    function getStatus(uint256 jobId) external view returns (Status);

    function paymentToken() external view returns (address);
}
