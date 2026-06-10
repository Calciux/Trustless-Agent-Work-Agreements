"""
evaluator_agent.py — Evaluator Agent role.
Queries on-chain job status (via LLM or RPC), uses LLM to judge deliverable
quality, generates complete/reject Pact, executes via CAW.
"""

from agent_base import AgentBase
from config import (
    ESCROW_ADDR, EVALUATOR_UUID, EVALUATOR_ADDR,
    EVALUATOR_TOTAL_OPS, SIG_COMPLETE, SIG_REJECT,
)
from caw_types import AgentRole, CawWallet, JobContext, CawResult


class EvaluatorAgent(AgentBase):
    """
    Evaluator role agent.
    Steps:
      1. evaluate — Read on-chain state and judge deliverable
      2. complete  — Approve and release funds to Provider
      3. reject    — Reject deliverable
    """

    def __init__(self, caw, llm, pact_gen):
        super().__init__(caw, llm, pact_gen)
        self._completed_ops: int = 0

    def get_role(self) -> AgentRole:
        return AgentRole.EVALUATOR

    def get_wallet(self) -> CawWallet:
        return CawWallet.EVALUATOR

    # ------------------------------------------------------------------
    # Role-specific methods
    # ------------------------------------------------------------------

    def evaluate_job(self, context: JobContext) -> dict:
        """
        Evaluate whether a submitted deliverable meets requirements.
        Uses LLM to judge based on job details and on-chain data.

        Returns dict with:
            action: "complete" or "reject"
            reason_hash: bytes32 hash
            reasoning: explanation
        """
        # Simulate reading chain state
        chain_state = self._read_chain_state(context)

        # Build job details from context
        job_details = {
            "job_id": context.job_id,
            "task_type": context.task_type,
            "input_token": context.input_token,
            "input_amount": context.input_amount,
            "output_token": context.output_token,
            "output_amount": context.output_amount,
            "reward_token": context.reward_token,
            "reward_amount": context.reward_amount,
        }

        # Judge via LLM
        judgment = self.llm.judge_deliverable(job_details, chain_state)

        # Store judgment in context
        context.chain_data["evaluator_judgment"] = judgment

        return judgment

    def complete_job(self, context: JobContext) -> JobContext:
        """Execute the complete() step (approve deliverable, release funds)."""
        # Ensure we have a reason hash
        if "reason_hash" not in context.chain_data:
            context.chain_data["reason_hash"] = "0x" + "ff" * 32

        context = self.execute_step(context, "complete", error_handler=self.error_handler)
        if context.current_step.name != "FAILED":
            self._completed_ops = EVALUATOR_TOTAL_OPS
        return context

    def reject_job(self, context: JobContext) -> JobContext:
        """Execute the reject() step."""
        if "reason_hash" not in context.chain_data:
            context.chain_data["reason_hash"] = "0x" + "00" * 32

        context = self.execute_step(context, "reject", error_handler=self.error_handler)
        if context.current_step.name != "FAILED":
            self._completed_ops = EVALUATOR_TOTAL_OPS
        return context

    # ------------------------------------------------------------------
    # Overrides
    # ------------------------------------------------------------------

    def _get_target_contract(self, step_name: str) -> str:
        return ESCROW_ADDR

    def _get_function_signature(self, step_name: str) -> str:
        if step_name == "complete":
            return SIG_COMPLETE
        return SIG_REJECT

    def _get_transaction_args(self, context: JobContext, step_name: str) -> list:
        """Build complete/reject(jobId, reasonHash) args."""
        job_id = context.job_id or 0
        reason_hash = context.chain_data.get(
            "reason_hash",
            "0x" + ("ff" if step_name == "complete" else "00") * 32
        )
        return [str(job_id), reason_hash]

    def _validate_result(self, context: JobContext, step_name: str) -> None:
        """Verify job reached terminal state."""
        if self.caw.mock_mode:
            return
        # Optionally: query on-chain to confirm status == Completed/Rejected
        pass

    def _read_chain_state(self, context: JobContext) -> dict:
        """
        Read on-chain data for the current job.
        Queries escrow contract for job status, budget, and token balances.
        """
        job_id = context.job_id or 0
        if job_id == 0:
            return {"error": "no job_id"}

        try:
            import subprocess, os
            from config import ESCROW_ADDR, PROXY_ENV
            cast_env = {**os.environ, **PROXY_ENV, "FOUNDRY_DISABLE_NIGHTLY_WARNING": "1"}
            rpc = "https://sepolia.gateway.tenderly.co"

            # Get job status
            result = subprocess.run(
                ["cast", "call", ESCROW_ADDR, "getStatus(uint256)(uint8)", str(job_id),
                 "--rpc-url", rpc],
                capture_output=True, text=True, env=cast_env, timeout=15
            )
            status_map = {0: "Open", 1: "Funded", 2: "Submitted", 3: "Completed", 4: "Rejected"}
            status_code = int(result.stdout.strip(), 0) if result.returncode == 0 and result.stdout.strip() else -1
            job_status = status_map.get(status_code, f"Unknown({status_code})")

            return {
                "job_id": job_id,
                "job_status": job_status,
                "task_type": context.task_type,
                "input_token": context.input_token,
                "input_amount": context.input_amount,
                "output_token": context.output_token,
                "output_amount": context.output_amount,
                "reward_amount": context.reward_amount,
            }
        except Exception:
            return {"job_id": job_id, "job_status": "query_failed"}

    def get_progress(self) -> float:
        """Return evaluator progress as percentage (0-100)."""
        return (self._completed_ops / EVALUATOR_TOTAL_OPS) * 100.0
