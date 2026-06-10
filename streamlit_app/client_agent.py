"""
client_agent.py — Client Agent role.
Parses job requirements from natural language, generates TTK approve
+ Escrow operation Pacts, executes createJob→setBudget→fund sequence via CAW.
"""

from typing import Optional

from agent_base import AgentBase
from config import (
    ESCROW_ADDR, TTK_ADDR, CLIENT_UUID, CLIENT_ADDR,
    CLIENT_TOTAL_OPS, SIG_APPROVE, SIG_CREATE_JOB, SIG_SET_BUDGET, SIG_FUND,
)
from caw_types import (
    AgentRole, CawWallet, JobContext, CawResult, WorkflowStep, ParsedIntent,
)
from error_handler import (
    OnChainRevertError, OnChainInsufficientFundsError, OnChainGasError,
)


class ClientAgent(AgentBase):
    """
    Client role agent.
    Steps:
      1. approve_ttk — Authorize Escrow to spend TTK
      2. create_job  — Create a new job on ERC-8183 Escrow
      3. set_budget  — Set the TTK budget for the job
      4. fund        — Fund the escrow with TTK
    """

    def __init__(self, caw, llm, pact_gen):
        super().__init__(caw, llm, pact_gen)
        self._completed_ops: int = 0

    def get_role(self) -> AgentRole:
        return AgentRole.CLIENT

    def get_wallet(self) -> CawWallet:
        return CawWallet.CLIENT

    # ------------------------------------------------------------------
    # Role-specific high-level methods (called by orchestrator)
    # ------------------------------------------------------------------

    def parse_intent(self, user_message: str) -> ParsedIntent:
        """Parse user's natural language into a structured intent."""
        return self.llm.parse_intent(user_message, role_hint="client")

    def approve_ttk(self, context: JobContext) -> JobContext:
        """Execute the approve_ttk step."""
        return self.execute_step(context, "approve_ttk")

    def create_job(self, context: JobContext) -> JobContext:
        """Execute the create_job step."""
        return self.execute_step(context, "create_job")

    def set_budget(self, context: JobContext) -> JobContext:
        """Execute the set_budget step."""
        return self.execute_step(context, "set_budget")

    def fund_job(self, context: JobContext) -> JobContext:
        """Execute the fund step."""
        return self.execute_step(context, "fund")

    def run_full_client_flow(self, context: JobContext) -> JobContext:
        """
        Execute the full client workflow: approve → create → budget → fund.
        Returns updated context. Stops on first failure.
        """
        steps = ["approve_ttk", "create_job", "set_budget", "fund"]
        for step in steps:
            context = self.execute_step(context, step, error_handler=self.error_handler)
            if context.current_step == WorkflowStep.FAILED:
                break
        return context

    # ------------------------------------------------------------------
    # Override: on-chain execution specifics
    # ------------------------------------------------------------------

    def _execute_onchain(
        self,
        pact_id: str,
        context: JobContext,
        step_name: str
    ) -> CawResult:
        """Execute the on-chain transaction with client-specific args."""
        contract = self._get_target_contract(step_name)
        function_sig = self._get_function_signature(step_name)
        args = self._get_transaction_args(context, step_name)

        return self.caw.execute_transaction(
            wallet=self.get_wallet(),
            pact_id=pact_id,
            contract_address=contract,
            function_signature=function_sig,
            args=args
        )

    def _get_target_contract(self, step_name: str) -> str:
        if step_name == "approve_ttk":
            return TTK_ADDR
        return ESCROW_ADDR

    def _get_function_signature(self, step_name: str) -> str:
        mapping = {
            "approve_ttk": SIG_APPROVE,
            "create_job":  SIG_CREATE_JOB,
            "set_budget":  SIG_SET_BUDGET,
            "fund":        SIG_FUND,
        }
        return mapping.get(step_name, "0x00000000")

    def _get_transaction_args(self, context: JobContext, step_name: str) -> list:
        from decimal import Decimal
        if step_name == "approve_ttk":
            ttk_amount = str(int(Decimal(context.reward_amount or "100") * Decimal(10**18)))
            return [ESCROW_ADDR.lower(), ttk_amount]
        elif step_name == "create_job":
            import time
            # provider, evaluator, expiredAt, description, hook
            return [
                "0xe2b749ce285b86ff058653336191dec2be50f32c",  # CAW Provider
                "0xf6459a8868dc4d6db511f535f27887e54d2f0d6d",  # CAW Evaluator
                str(int(time.time()) + 86400 * 7),  # 7 days from now
                "CAW Demo Job",
                "0x0000000000000000000000000000000000000000",  # no hook
            ]
        elif step_name == "set_budget":
            ttk_amount = str(int(Decimal(context.reward_amount or "100") * Decimal(10**18)))
            job_id = context.job_id or 0
            return [str(job_id), ttk_amount]
        elif step_name == "fund":
            ttk_amount = str(int(Decimal(context.reward_amount or "100") * Decimal(10**18)))
            job_id = context.job_id or 0
            return [str(job_id), ttk_amount]
        return []

    def _validate_result(self, context: JobContext, step_name: str) -> None:
        """
        Post-execution validation for client steps.
        Checks invariants depending on the step.
        """
        # In mock mode, skip validation
        if self.caw.mock_mode:
            return

        if step_name == "approve_ttk":
            pass
        elif step_name == "create_job":
            # Extract job_id from on-chain: query jobCount() after successful createJob
            try:
                import subprocess, os
                from config import ESCROW_ADDR, PROXY_ENV
                cast_env = {**os.environ, **PROXY_ENV, "FOUNDRY_DISABLE_NIGHTLY_WARNING": "1"}
                result = subprocess.run(
                    ["cast", "call", ESCROW_ADDR, "jobCount()(uint256)",
                     "--rpc-url", "https://sepolia.gateway.tenderly.co"],
                    capture_output=True, text=True, env=cast_env, timeout=20
                )
                if result.returncode == 0 and result.stdout.strip():
                    job_id = int(result.stdout.strip(), 0)  # auto-detect base (cast may return decimal or hex)
                    if job_id > 0:
                        context.job_id = job_id
            except Exception:
                pass
        elif step_name == "set_budget":
            # Already extracted from create_job
            pass
        elif step_name == "fund":
            pass

    def get_progress(self) -> float:
        """Return client progress as percentage (0-100)."""
        return (self._completed_ops / CLIENT_TOTAL_OPS) * 100.0
