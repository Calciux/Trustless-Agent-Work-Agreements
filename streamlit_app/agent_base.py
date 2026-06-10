"""
agent_base.py — Abstract base class for Client/Provider/Evaluator agents.
Defines common interface: execute_step(), get_pact_template(), validate_result().
"""

from abc import ABC, abstractmethod
from typing import Optional, TYPE_CHECKING
import time
import json

from config import (
    APPROVAL_POLL_INTERVAL, APPROVAL_MAX_WAIT,
    ESCROW_ADDR, TTK_ADDR, CHAIN,
)
from caw_types import (
    AgentRole, WorkflowStep, CawWallet, CawPactStatus,
    JobContext, CawResult,
)

if TYPE_CHECKING:
    from caw_interface import CawInterface
    from llm_client import LLMClient
    from pact_generator import PactGenerator


class AgentBase(ABC):
    """
    Abstract base for all three role-specific agents.
    Defines the common interface for executing a workflow step.
    Each concrete agent implements role-specific logic.
    """

    def __init__(
        self,
        caw: "CawInterface",
        llm: "LLMClient",
        pact_gen: "PactGenerator",
    ):
        self.caw = caw
        self.llm = llm
        self.pact_gen = pact_gen
        self.error_handler = None  # set by orchestrator for retry logic

    # ------------------------------------------------------------------
    # Abstract methods (subclasses must implement)
    # ------------------------------------------------------------------

    @abstractmethod
    def get_role(self) -> AgentRole:
        """Return the agent's role enum."""
        ...

    @abstractmethod
    def get_wallet(self) -> CawWallet:
        """Return the CAW wallet enum this agent controls."""
        ...

    @abstractmethod
    def _validate_result(self, context: JobContext, step_name: str) -> None:
        """
        Post-execution validation. Raise on failure.
        Subclasses check role-specific invariants
        (e.g., TTK balance, job status on-chain).
        """
        ...

    # ------------------------------------------------------------------
    # Template method: execute_step (orchestrator calls this)
    # ------------------------------------------------------------------

    def execute_step(
        self,
        context: JobContext,
        step_name: str,
        error_handler=None,
        on_pact_generated=None,
        on_tx_submitting=None
    ) -> JobContext:
        """
        Execute a single workflow step with optional error-handler retry logic.

        This is the main entry point called by the orchestrator.
        Subclasses should NOT override this — they override role-specific
        methods like create_job(), approve_ttk(), etc.

        Steps:
          1. Generate Pact JSON
          2. Submit Pact to CAW
          3. Wait for CAW approval (polling)
          4. Execute on-chain transaction
          5. Validate result

        If error_handler is provided, retryable failures will be retried
        up to the handler's max_retries limit before giving up.

        Args:
            context: Current job context (mutated in place).
            step_name: Identifier for the step to execute
                       (e.g., "approve_ttk", "create_job", "submit").
            error_handler: Optional ErrorHandler instance for retry decisions.

        Returns:
            Updated JobContext.
        """
        max_retries = 3
        for attempt in range(max_retries + 1):
            # 1. Generate Pact
            pact_json = self._generate_pact(context, step_name)
            context.pact_jsons[step_name] = pact_json  # save for display
            if on_pact_generated:
                on_pact_generated(step_name, pact_json)
            context.current_step = WorkflowStep.PACT_GENERATED

            # 2. Submit to CAW
            result = self._submit_pact(pact_json, step_name)
            if not result.get("success"):
                if self._should_retry_error(error_handler, result.get("stderr",""), attempt, max_retries):
                    continue
                context.error_message = f"Failed to submit pact: {result.get('stderr','')}"
                context.current_step = WorkflowStep.FAILED
                return context

            context.pacts[step_name] = result.get("pact_id","")
            context.current_step = WorkflowStep.CAW_SUBMITTED

            # 3. Wait for approval
            approved = self._wait_for_approval(result.get("pact_id",""), context)
            if not approved:
                if self._should_retry_error(error_handler, "approval timeout", attempt, max_retries):
                    continue
                context.error_message = f"Pact approval timeout or rejection: {result.get('pact_id','')}"
                context.current_step = WorkflowStep.FAILED
                return context

            context.current_step = WorkflowStep.CAW_APPROVED

            # 4. Execute on-chain
            if on_tx_submitting:
                on_tx_submitting(step_name, self._get_target_contract(step_name),
                                 self._get_function_signature(step_name),
                                 self._get_transaction_args(context, step_name))
            tx_result = self._execute_onchain(result.get("pact_id",""), context, step_name)
            if not tx_result.get("success"):
                if self._should_retry_error(error_handler, tx_result.get("stderr",""), attempt, max_retries):
                    continue
                context.error_message = f"On-chain tx failed: {tx_result.get('stderr','')}"
                context.current_step = WorkflowStep.FAILED
                return context

            context.transactions[step_name] = tx_result.get("tx_hash","")
            context.current_step = WorkflowStep.TX_EXECUTING

            # 5. Validate
            self._validate_result(context, step_name)
            context.current_step = WorkflowStep.COMPLETED

            return context

        # Exhausted retries
        context.error_message = f"Step '{step_name}' failed after {max_retries + 1} attempts"
        context.current_step = WorkflowStep.FAILED
        return context

    def _should_retry_error(
        self,
        error_handler,
        error_msg: str,
        attempt: int,
        max_retries: int
    ) -> bool:
        """Check whether a step failure should be retried via error_handler."""
        if error_handler is None or attempt >= max_retries:
            return False
        from error_handler import CAWTimeoutError, CAWUnavailableError, NetworkError
        # Build a synthetic exception for classification
        exc = Exception(error_msg)
        category = error_handler.classify(exc)
        if error_handler.should_retry(category):
            error_handler.record_retry(category)
            return True
        return False

    # ------------------------------------------------------------------
    # Template method hooks (subclasses can override)
    # ------------------------------------------------------------------

    def _generate_pact(self, context: JobContext, step_name: str) -> dict:
        """Generate the Pact JSON for this step."""
        return self.pact_gen.generate_for_step(
            role=self.get_role().value,
            step=step_name,
            context=context
        )

    def _submit_pact(self, pact_json: dict, step_name: str) -> CawResult:
        """Submit Pact to CAW. Default: calls caw.create_pact()."""
        return self.caw.create_pact(
            wallet=self.get_wallet(),
            pact_definition=pact_json
        )

    def _wait_for_approval(
        self,
        pact_id: str,
        context: JobContext,
        poll_interval: int = None,
        max_wait: int = None
    ) -> bool:
        """
        Poll CAW until pact is approved or timeout.
        Returns True if approved, False on timeout/rejection.
        """
        poll_interval = poll_interval or APPROVAL_POLL_INTERVAL
        max_wait = max_wait or APPROVAL_MAX_WAIT
        elapsed = 0

        while elapsed < max_wait:
            result = self.caw.get_pact_status(
                wallet=self.get_wallet(),
                pact_id=pact_id
            )

            if result.get("status") == CawPactStatus.APPROVED or result.get("status") == "active":
                return True
            elif result.get("status") in (CawPactStatus.REJECTED, CawPactStatus.FAILED):
                return False
            elif result.get("status") == CawPactStatus.COMPLETED or result.get("status") == "completed":
                return True

            time.sleep(poll_interval)
            elapsed += poll_interval

        return False

    def _execute_onchain(
        self,
        pact_id: str,
        context: JobContext,
        step_name: str
    ) -> CawResult:
        """
        Execute the on-chain transaction via CAW.
        Default implementation — subclasses should override with
        role-specific contract calls.
        """
        # Default: extract from context or use generic call
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

    # ------------------------------------------------------------------
    # Helpers (override per agent)
    # ------------------------------------------------------------------

    def _get_target_contract(self, step_name: str) -> str:
        """
        Return the target contract address for a step.
        Subclasses MUST override this with role-specific logic.
        """
        raise NotImplementedError(
            f"{self.__class__.__name__} must override _get_target_contract()"
        )

    def _get_function_signature(self, step_name: str) -> str:
        """
        Return the function selector for a step.
        Subclasses MUST override this with role-specific logic.
        """
        raise NotImplementedError(
            f"{self.__class__.__name__} must override _get_function_signature()"
        )

    def _get_transaction_args(self, context: JobContext, step_name: str) -> list:
        """
        Build the argument list for a transaction.
        Subclasses MUST override this with role-specific logic.
        """
        raise NotImplementedError(
            f"{self.__class__.__name__} must override _get_transaction_args()"
        )
