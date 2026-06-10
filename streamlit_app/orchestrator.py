"""
orchestrator.py — Central coordinator that manages the end-to-end workflow.
Routes user intents to the correct agent, sequences steps,
tracks progress, and handles errors.
"""

import uuid
import json
from datetime import datetime
from typing import Optional

from config import (
    SKIP_CAW, CLIENT_TOTAL_OPS, PROVIDER_TOTAL_OPS, EVALUATOR_TOTAL_OPS,
)
from caw_types import (
    WorkflowStep, AgentRole, JobContext, ParsedIntent,
    WorkflowSession, TxRecord, CawPactStatus,
)
from error_handler import ErrorHandler


class AgentOrchestrator:
    """
    Central coordinator that manages the end-to-end workflow.
    Routes user intents to the correct agent, sequences steps,
    tracks progress, and handles errors.
    """

    def __init__(
        self,
        client_agent,
        provider_agent,
        evaluator_agent,
        llm_client,
        caw_interface,
        pact_generator,
        session,
        mock_handler=None
    ):
        self.client = client_agent
        self.provider = provider_agent
        self.evaluator = evaluator_agent
        self.llm = llm_client
        self.caw = caw_interface
        self.pact_gen = pact_generator
        self.session = session
        self.mock_handler = mock_handler
        self.error_handler = ErrorHandler()

        # Inject error_handler into agents for retry logic (W6 fix)
        self.client.error_handler = self.error_handler
        self.provider.error_handler = self.error_handler
        self.evaluator.error_handler = self.error_handler

        # Map role to agent
        self._agent_map = {
            AgentRole.CLIENT: self.client,
            AgentRole.PROVIDER: self.provider,
            AgentRole.EVALUATOR: self.evaluator,
        }

    # ------------------------------------------------------------------
    # Main entry point
    # ------------------------------------------------------------------

    def process_input(self, user_message: str) -> dict:
        """
        Main entry point called by app.py when user sends a message.

        1. Parse intent via LLM
        2. Determine which agent(s) to invoke
        3. Execute workflow steps sequentially
        4. Update session state after each step
        5. Return result summary for UI rendering

        Args:
            user_message: Raw natural language input.

        Returns:
            Dict with status, messages, and UI update instructions.
        """
        self.session.ensure_workflow()
        self.session.add_chat_message("user", user_message)

        # Log the input
        self.session.add_log_entry("LLM", f"User input: {user_message}")

        # Step 1: Parse intent
        try:
            intent = self._parse_intent(user_message)
            self.session.add_log_entry(
                "LLM",
                f"Parsed intent: role={intent.role}, action={intent.action}, "
                f"task={intent.task_type}, confidence={intent.confidence}"
            )
        except Exception as e:
            self.session.add_log_entry("ERROR", f"Intent parsing failed: {e}")
            return self._error_result("Failed to parse your request", str(e))

        if intent.human_description:
            self.session.add_log_entry("LLM", f"Human description: {intent.human_description}")

        # Build context from intent
        context = self._build_context(intent)
        self.session.advance_step(WorkflowStep.INTENT_PARSED.value, "Intent parsed ✓")

        # Step 2+: Execute agent-specific workflow
        try:
            result = self._execute_workflow(context, intent)
            return result
        except Exception as e:
            self.session.add_log_entry("ERROR", f"Workflow failed: {e}")
            return self._error_result("Workflow execution failed", str(e))

    def resume_workflow(self, pact_id: str) -> dict:
        """
        Resume a workflow after manual CAW approval.
        Called when user clicks "Approve" in CAW App and returns to UI.
        """
        wf = self.session.get_workflow()
        if wf is None:
            return self._error_result("No active workflow to resume", "")

        # Check pact status
        wallet = self._get_wallet_for_role(wf.current_role)
        result = self.caw.get_pact_status(wallet, pact_id)

        if result.get("status") == CawPactStatus.APPROVED or result.get("status") == "active":
            self.session.advance_step(
                WorkflowStep.CAW_APPROVED.value,
                f"Pact {pact_id} approved ✓"
            )
            return {"status": "approved", "pact_id": pact_id}
        elif result.get("status") == CawPactStatus.REJECTED:
            return {"status": "rejected", "pact_id": pact_id}
        else:
            return {"status": "pending", "pact_id": pact_id}

    # ------------------------------------------------------------------
    # Workflow state queries
    # ------------------------------------------------------------------

    def get_current_agent(self):
        """Return the agent currently executing (based on session state)."""
        wf = self.session.get_workflow()
        if wf is None:
            return None
        role = wf.current_role
        if role == "client":
            return self.client
        elif role == "provider":
            return self.provider
        elif role == "evaluator":
            return self.evaluator
        return None

    def get_workflow_summary(self) -> dict:
        """Return current workflow status for the right panel."""
        wf = self.session.get_workflow()
        if wf is None:
            return {
                "current_step": 0,
                "status_message": "Idle — awaiting input",
                "client_progress": 0.0,
                "provider_progress": 0.0,
                "evaluator_progress": 0.0,
                "tx_history": [],
            }

        return {
            "current_step": wf.current_step,
            "status_message": wf.status_message or "Processing...",
            "client_progress": wf.client_progress,
            "provider_progress": wf.provider_progress,
            "evaluator_progress": wf.evaluator_progress,
            "tx_history": wf.tx_history,
        }

    def reset(self) -> None:
        """Reset orchestrator and session state for a new job."""
        self.error_handler.reset_retries()
        self.session.reset_workflow()

    # ------------------------------------------------------------------
    # Internal: Intent parsing
    # ------------------------------------------------------------------

    def _parse_intent(self, user_message: str) -> ParsedIntent:
        """Parse user message into structured intent."""
        return self.llm.parse_intent(user_message)

    def _build_context(self, intent: ParsedIntent) -> JobContext:
        """Build a JobContext from a ParsedIntent."""
        from config import CLIENT_UUID, PROVIDER_UUID, EVALUATOR_UUID

        ctx = JobContext(
            job_id=intent.params.get("job_id", 0) or None,
            task_type=intent.task_type,
            input_token=intent.params.get("input_token", ""),
            input_amount=intent.params.get("input_amount", ""),
            output_token=intent.params.get("output_token", ""),
            output_amount=intent.params.get("output_amount", ""),
            reward_token=intent.params.get("reward_token", "TTK"),
            reward_amount=intent.params.get("reward_amount", "100"),
            client_uuid=CLIENT_UUID,
            provider_uuid=PROVIDER_UUID,
            evaluator_uuid=EVALUATOR_UUID,
            current_step=WorkflowStep.INTENT_PARSED,
        )
        return ctx

    # ------------------------------------------------------------------
    # Internal: Workflow execution
    # ------------------------------------------------------------------

    def _execute_workflow(self, context: JobContext, intent: ParsedIntent) -> dict:
        """Execute the appropriate workflow based on intent role/action."""
        role = intent.role
        action = intent.action

        self.session.update_workflow(
            current_role=role,
            task_type=context.task_type,
            reward_token=context.reward_token,
            reward_amount=context.reward_amount,
            input_token=context.input_token,
            input_amount=context.input_amount,
            output_token=context.output_token,
            output_amount=context.output_amount,
        )

        messages = []
        if intent.human_description:
            messages.append(f"📋 **Plan:** {intent.human_description}")
            messages.append("")
        status = "success"

        if role == "client":
            agent = self.client
            self.session.update_workflow(current_role="client")

            if action in ("create_job", "create_task"):
                # Run full client flow
                context = agent.run_full_client_flow(context)
                if context.current_step == WorkflowStep.FAILED:
                    status = "error"
                    messages.append(f"❌ Client workflow failed: {context.error_message}")
                else:
                    messages.append("✅ **Client workflow submitted to CAW!**")
                    messages.append("")
                    messages.append("📱 **Please check your CAW App and approve these Pacts:**")
                    messages.append("")

                    # Show generated Pact details
                    for step_name in ["approve_ttk", "create_job", "set_budget", "fund"]:
                        pj = context.pact_jsons.get(step_name)
                        if not pj:
                            continue
                        messages.append(f"---")
                        # Get policy name
                        policies = pj.get("policies", [])
                        if policies:
                            p = policies[0] if isinstance(policies, list) else policies
                            pname = p.get("name", step_name)
                            messages.append(f"**{pname}**")
                            rules = p.get("rules", {})
                            when = rules.get("when", {})
                            targets = when.get("target_in", [])
                            for t in targets:
                                addr = t.get("contract_addr", "?")[:10]
                                fid = t.get("function_id", "")
                                messages.append(f"   📝 Contract: {addr}...")
                                if fid:
                                    messages.append(f"   🔧 Function: {fid}")
                            deny = rules.get("deny_if", {})
                            if deny.get("amount_gt"):
                                messages.append(f"   💰 Max/tx: {deny['amount_gt']}")
                        else:
                            messages.append(f"**{step_name}**")
                    messages.append("")
                    messages.append("👉 Open CAW App → approve each Pact as it appears")
                    self.session.update_workflow(
                        client_progress=100.0,
                        current_step=WorkflowStep.COMPLETED.value,
                        status_message="Client workflow complete ✓"
                    )
                    # Record transactions
                    for step_name in ["approve_ttk", "create_job", "set_budget", "fund"]:
                        tx_hash = context.transactions.get(step_name, "")
                        if tx_hash:
                            self.session.record_transaction(
                                step_name, tx_hash, "confirmed",
                                f"https://sepolia.etherscan.io/tx/{tx_hash}"
                            )

            else:
                # Single client step
                context = agent.execute_step(context, action, error_handler=self.error_handler)
                if context.current_step == WorkflowStep.FAILED:
                    status = "error"
                    messages.append(f"❌ Client {action} failed: {context.error_message}")
                else:
                    messages.append(f"✅ Client {action} complete")

        elif role == "provider":
            self.session.update_workflow(current_role="provider")

            if action == "submit":
                context = self.provider.submit_delivery(context)
                if context.current_step == WorkflowStep.FAILED:
                    status = "error"
                    messages.append(f"❌ Provider submit failed: {context.error_message}")
                else:
                    messages.append(f"✅ Provider submitted delivery")
                    messages.append(f"   - submit: tx {context.transactions.get('submit', 'N/A')}")
                    self.session.update_workflow(
                        provider_progress=100.0,
                        status_message="Provider submitted ✓"
                    )
                    tx_hash = context.transactions.get("submit", "")
                    if tx_hash:
                        self.session.record_transaction(
                            "submit", tx_hash, "confirmed",
                            f"https://sepolia.etherscan.io/tx/{tx_hash}"
                        )

        elif role == "evaluator":
            self.session.update_workflow(current_role="evaluator")

            if action == "evaluate" or action == "complete":
                # First evaluate, then complete/reject
                judgment = self.evaluator.evaluate_job(context)
                eval_action = judgment.get("action", "complete")
                messages.append(f"🔍 Evaluator judgment: {eval_action}")
                messages.append(f"   Reasoning: {judgment.get('reasoning', 'N/A')}")

                if eval_action == "complete":
                    context = self.evaluator.complete_job(context)
                else:
                    context = self.evaluator.reject_job(context)

                if context.current_step == WorkflowStep.FAILED:
                    status = "error"
                    messages.append(f"❌ Evaluator {eval_action} failed: {context.error_message}")
                else:
                    messages.append(f"✅ Evaluator {eval_action} complete")
                    messages.append(f"   - {eval_action}: tx {context.transactions.get(eval_action, 'N/A')}")
                    self.session.update_workflow(
                        evaluator_progress=100.0,
                        status_message=f"Evaluator {eval_action} ✓"
                    )
                    tx_hash = context.transactions.get(eval_action, "")
                    if tx_hash:
                        self.session.record_transaction(
                            eval_action, tx_hash, "confirmed",
                            f"https://sepolia.etherscan.io/tx/{tx_hash}"
                        )

        # Add agent response to chat
        chat_msg = "\n".join(messages) if messages else f"Action '{action}' completed."
        self.session.add_chat_message("assistant", chat_msg)
        self.session.add_log_entry("CAW", f"Workflow result: {status}")

        return {
            "status": status,
            "messages": messages,
            "context": context,
            "summary": self.get_workflow_summary(),
        }

    def _error_result(self, title: str, detail: str) -> dict:
        """Build an error result dict."""
        msg = f"❌ {title}\n```\n{detail}\n```"
        self.session.add_chat_message("assistant", msg)
        self.session.add_log_entry("ERROR", f"{title}: {detail}")
        return {
            "status": "error",
            "messages": [msg],
            "context": None,
            "summary": self.get_workflow_summary(),
        }

    def _get_wallet_for_role(self, role: str):
        """Map role string to CawWallet enum."""
        from caw_types import CawWallet
        mapping = {
            "client": CawWallet.CLIENT,
            "provider": CawWallet.PROVIDER,
            "evaluator": CawWallet.EVALUATOR,
        }
        return mapping.get(role, CawWallet.CLIENT)
