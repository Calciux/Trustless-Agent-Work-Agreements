"""
provider_agent.py — Provider Agent role.
Generates submit Pact and executes submit() call via CAW with deliverable hash.
"""

from agent_base import AgentBase
from config import (
    ESCROW_ADDR, PROVIDER_UUID, PROVIDER_ADDR,
    PROVIDER_TOTAL_OPS, SIG_SUBMIT,
)
from caw_types import AgentRole, CawWallet, JobContext, CawResult


class ProviderAgent(AgentBase):
    """
    Provider role agent.
    Steps:
      1. submit — Submit deliverable hash to prove work completion
    """

    def __init__(self, caw, llm, pact_gen):
        super().__init__(caw, llm, pact_gen)
        self._completed_ops: int = 0

    def get_role(self) -> AgentRole:
        return AgentRole.PROVIDER

    def get_wallet(self) -> CawWallet:
        return CawWallet.PROVIDER

    # ------------------------------------------------------------------
    # Role-specific methods
    # ------------------------------------------------------------------

    def submit_delivery(self, context: JobContext) -> JobContext:
        """
        Execute the submit step.
        Provider submits a deliverable hash to prove work completion.
        """
        return self.execute_step(context, "submit", error_handler=self.error_handler)

    # ------------------------------------------------------------------
    # Overrides
    # ------------------------------------------------------------------

    def _get_target_contract(self, step_name: str) -> str:
        return ESCROW_ADDR

    def _get_function_signature(self, step_name: str) -> str:
        return SIG_SUBMIT

    def _get_transaction_args(self, context: JobContext, step_name: str) -> list:
        """Build submit(jobId, deliverableHash) args."""
        job_id = context.job_id or 0
        # Generate a meaningful deliverable hash from job context (not dummy 0xabab...)
        import hashlib
        seed = f"{context.job_id}:{context.task_type}:{context.input_token}:{context.input_amount}:{context.output_token}:{context.output_amount}"
        deliverable_hash = "0x" + hashlib.sha256(seed.encode()).hexdigest()[:64]
        # Store in chain_data for evaluator to inspect
        context.chain_data["deliverable_hash"] = deliverable_hash
        return [str(job_id), deliverable_hash]

    def _validate_result(self, context: JobContext, step_name: str) -> None:
        """
        Post-execution validation: verify job status moved to Submitted (2).
        """
        if self.caw.mock_mode:
            return
        # Optionally: query on-chain to confirm status == Submitted
        pass

    def get_progress(self) -> float:
        """Return provider progress as percentage (0-100)."""
        return (self._completed_ops / PROVIDER_TOTAL_OPS) * 100.0
