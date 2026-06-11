"""
types.py — Shared type definitions used across all modules.
Dataclasses and enums only — no implementation logic.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Any


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class AgentRole(Enum):
    CLIENT = "client"
    PROVIDER = "provider"
    EVALUATOR = "evaluator"


class WorkflowStep(Enum):
    IDLE = 0
    INTENT_PARSED = 1
    PACT_GENERATED = 2
    CAW_SUBMITTED = 3
    CAW_APPROVED = 4
    TX_EXECUTING = 5
    COMPLETED = 6
    FAILED = 99


class CawWallet(Enum):
    CLIENT = "5a8eeb0c-f528-495f-97ab-223f5ce12741"
    PROVIDER = "7b30435c-127f-4f30-9b77-99d0411a9e7f"
    EVALUATOR = "4cbd29cc-4cde-47b0-8b89-cf9c89daae72"


class CawPactStatus(Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXECUTING = "executing"
    COMPLETED = "completed"
    FAILED = "failed"
    UNKNOWN = "unknown"


class ErrorCategory(Enum):
    CAW_TIMEOUT = "caw_timeout"
    CAW_REJECTED = "caw_rejected"
    CAW_UNAVAILABLE = "caw_unavailable"
    LLM_API_ERROR = "llm_api_error"
    LLM_PARSE_ERROR = "llm_parse_error"
    ONCHAIN_REVERT = "onchain_revert"
    ONCHAIN_GAS = "onchain_gas"
    ONCHAIN_INSUFFICIENT_FUNDS = "onchain_insufficient_funds"
    CONFIG_ERROR = "config_error"
    USER_ABORT = "user_abort"
    NETWORK_ERROR = "network_error"
    UNKNOWN = "unknown_error"


class RecoveryAction(Enum):
    RETRY = "retry"
    SKIP = "skip"
    ABORT = "abort"
    FALLBACK = "fallback"
    PROMPT_USER = "prompt_user"


class LLMProvider(Enum):
    DEEPSEEK = "deepseek"
    OPENAI = "openai"


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------

@dataclass
class CawResult:
    """Structured result from a CAW CLI operation."""
    success: bool
    pact_id: Optional[str] = None
    tx_hash: Optional[str] = None
    status: CawPactStatus = CawPactStatus.PENDING
    stdout: str = ""
    stderr: str = ""
    exit_code: int = 0
    duration_ms: float = 0.0


@dataclass
class LLMResponse:
    """Structured response from an LLM API call."""
    raw_text: str
    parsed_json: Optional[dict] = None
    token_usage: int = 0
    latency_ms: float = 0.0


@dataclass
class ParsedIntent:
    """Parsed user intent from natural language."""
    role: str = "client"            # "client", "provider", "evaluator"
    action: str = "create_job"     # "create_job", "submit", "evaluate", "complete", "reject"
    task_type: str = ""            # "swap", "transfer", "simple_payment"
    params: dict = field(default_factory=dict)
    reasoning: str = ""
    confidence: float = 0.0
    human_description: str = ""    # LLM-generated plain-language explanation


@dataclass
class JobContext:
    """Mutable context object passed through the workflow pipeline."""
    job_id: Optional[int] = None
    task_type: str = ""
    input_token: str = ""
    input_amount: str = ""
    output_token: str = ""
    output_amount: str = ""
    reward_token: str = "TTK"
    reward_amount: str = ""
    client_uuid: str = ""
    provider_uuid: str = ""
    evaluator_uuid: str = ""
    # Accumulated results
    pacts: dict[str, str] = field(default_factory=dict)          # step_name -> pact_id
    pact_jsons: dict[str, dict] = field(default_factory=dict)    # step_name -> pact_json
    # Optimized mode: role-level Pact reuse cache
    role_pact_id: dict[str, str] = field(default_factory=dict)          # role -> pact_id
    role_pact_json: dict[str, dict] = field(default_factory=dict)       # role -> pact_json
    transactions: dict[str, str] = field(default_factory=dict)    # step_name -> tx_hash
    current_step: WorkflowStep = WorkflowStep.IDLE
    error_message: str = ""
    # On-chain derived data
    chain_data: dict[str, Any] = field(default_factory=dict)     # step -> on-chain state


@dataclass
class PactTemplate:
    """Descriptor for a Pact template loaded from disk."""
    name: str                       # Template identifier
    role: str                       # "client", "provider", "evaluator"
    step: str                       # "approve_ttk", "create_job", etc.
    policies_json: dict             # The policies section
    completion_conditions: list[dict]  # Completion conditions
    raw_data: dict = field(default_factory=dict)  # Full original JSON for reconstruction


@dataclass
class TxRecord:
    """Record of a single on-chain transaction for the tx history panel."""
    step: str
    tx_hash: str
    status: str = "pending"         # pending, confirmed, failed
    contract: str = ""
    function: str = ""
    etherscan_link: str = ""


@dataclass
class WorkflowSession:
    """Complete session state snapshot for a single workflow."""
    session_id: str = ""
    created_at: str = ""

    # Current state
    current_step: int = 0
    current_role: str = ""
    status_message: str = ""

    # Job context
    job_id: Optional[int] = None
    task_type: str = ""
    reward_token: str = "TTK"
    reward_amount: str = ""
    input_token: str = ""
    input_amount: str = ""
    output_token: str = ""
    output_amount: str = ""

    # Execution tracking
    pacts: dict[str, str] = field(default_factory=dict)
    transactions: dict[str, str] = field(default_factory=dict)
    tx_history: list[dict] = field(default_factory=list)

    # Role progress (0-100)
    client_progress: float = 0.0
    provider_progress: float = 0.0
    evaluator_progress: float = 0.0

    # Debug log
    log_entries: list[dict] = field(default_factory=list)

    # Error state
    error: Optional[str] = None
    error_step: Optional[str] = None
    retry_count: int = 0

    # Mock mode
    mock_mode: bool = True
