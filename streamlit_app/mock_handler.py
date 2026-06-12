"""
mock_handler.py — Simulates all external dependencies for UI testing.
Activated when SKIP_CAW=True (env var or UI toggle).
Returns deterministic fake responses for CAW, LLM, and on-chain operations.
"""

import uuid
import time
import hashlib
import random
import re
import json
from datetime import datetime
from typing import Optional

from config import (
    CLIENT_UUID, PROVIDER_UUID, EVALUATOR_UUID,
    ESCROW_ADDR, TTK_ADDR, ETH_MOCK_ADDR, USDT_MOCK_ADDR,
    CHAIN,
)
from caw_types import (
    CawResult, CawPactStatus, CawWallet,
    LLMResponse, ParsedIntent, LLMProvider,
)


class MockHandler:
    """
    Simulates all external dependencies for UI testing.
    Activated when SKIP_CAW=True or Mock Mode toggle is ON.
    """

    def __init__(self, approval_delay: float = 1.0):
        """
        Args:
            approval_delay: Simulated seconds to wait for "CAW approval"
                           (set to 0 for instant, higher for realistic feel).
        """
        self.approval_delay = approval_delay
        self._status_call_counts: dict[str, int] = {}  # pact_id -> call count
        self._pact_id_counter: int = 0

    # ==================================================================
    # CAW Simulation
    # ==================================================================

    def simulate_create_pact(
        self,
        wallet_uuid: str,
        pact_definition: dict
    ) -> CawResult:
        """
        Simulate `caw pact new`. Returns a fake pact_id.
        Also logs the pact JSON to the debug log for inspection.
        """
        self._pact_id_counter += 1
        short_id = f"pact-{self._pact_id_counter:04d}-{uuid.uuid4().hex[:8]}"
        time.sleep(self.approval_delay * 0.3)

        # Extract pact name for nicer logging
        pact_name = pact_definition.get("name", "unknown") if isinstance(pact_definition, dict) else "unknown"

        return CawResult(
            success=True,
            pact_id=short_id,
            status=CawPactStatus.PENDING,
            stdout=(
                f"[MOCK] Pact created: {short_id}\n"
                f"[MOCK] Name: {pact_name}\n"
                f"[MOCK] Wallet: {wallet_uuid}\n"
                f"[MOCK] Status: pending approval\n"
                f"[MOCK] Pact JSON:\n{json.dumps(pact_definition, indent=2)}"
            ),
            duration_ms=self.approval_delay * 300
        )

    def simulate_approval(self, pact_id: str) -> CawResult:
        """
        Simulate CAW App approval after a delay.
        In auto_approve mode (default for mock), instantly approves.
        """
        if self.approval_delay > 0:
            time.sleep(self.approval_delay)

        return CawResult(
            success=True,
            pact_id=pact_id,
            status=CawPactStatus.APPROVED,
            stdout=f"[MOCK] Pact {pact_id}: approved (mock auto-approval)"
        )

    def simulate_execute_transaction(
        self,
        wallet_uuid: str,
        pact_id: str,
        contract_address: str,
        function_name: str,
        args: list[str],
        value: str = "0"
    ) -> CawResult:
        """
        Simulate `caw tx call`. Returns a deterministic fake tx hash
        based on input parameters.
        """
        seed = f"{pact_id}:{contract_address}:{function_name}:{','.join(args)}:{value}"
        fake_tx_hash = "0x" + hashlib.sha256(seed.encode()).hexdigest()[:64]

        time.sleep(self.approval_delay * 0.5)

        return CawResult(
            success=True,
            pact_id=pact_id,
            tx_hash=fake_tx_hash,
            status=CawPactStatus.COMPLETED,
            stdout=(
                f"[MOCK] Transaction sent: {fake_tx_hash}\n"
                f"[MOCK] From wallet: {wallet_uuid}\n"
                f"[MOCK] To: {contract_address}\n"
                f"[MOCK] Function: {function_name}(${', '.join(args)})\n"
                f"[MOCK] Value: {value}\n"
                f"[MOCK] Status: confirmed (mock)"
            ),
            duration_ms=self.approval_delay * 500
        )

    def simulate_get_status(self, pact_id: str) -> CawResult:
        """
        Simulate `caw pact status`. Auto-advances through PENDING → APPROVED.
        First call = pending, second+ = approved.
        """
        call_count = self._status_call_counts.get(pact_id, 0) + 1
        self._status_call_counts[pact_id] = call_count

        if call_count >= 2:
            status = CawPactStatus.APPROVED
            msg = f"[MOCK] Pact {pact_id}: approved (call #{call_count})"
        else:
            status = CawPactStatus.PENDING
            msg = f"[MOCK] Pact {pact_id}: pending approval (call #{call_count})"

        return CawResult(
            success=True,
            pact_id=pact_id,
            status=status,
            stdout=msg
        )

    def simulate_get_transaction_status(self, tx_hash: str) -> CawResult:
        """Simulate transaction status check — always confirmed in mock."""
        return CawResult(
            success=True,
            tx_hash=tx_hash,
            status=CawPactStatus.COMPLETED,
            stdout=f"[MOCK] Transaction {tx_hash[:16]}... confirmed"
        )

    # ==================================================================
    # LLM Simulation
    # ==================================================================

    def simulate_parse_intent(self, user_message: str) -> ParsedIntent:
        """
        Simulate LLM intent parsing with keyword matching.
        Covers common Chinese and English patterns.
        """
        msg_lower = user_message.lower()

        # Default values
        task_type = "swap"
        action = "create_job"
        role = "client"
        reward_amount = "100"
        input_token = "ETH_mock"
        input_amount = "0.1"
        output_token = "USDT_mock"
        output_amount = ""

        # Detect role
        if any(w in msg_lower for w in ["provide", "provider", "供应", "执行者"]):
            role = "provider"
            action = "submit"
            task_type = "deliver"
        elif any(w in msg_lower for w in ["evaluat", "evaluator", "评估", "评判"]):
            role = "evaluator"
            action = "evaluate"
            task_type = "judge"

        # Detect task type
        if "swap" in msg_lower or "兑换" in user_message:
            task_type = "swap"
        elif "transfer" in msg_lower or "转账" in user_message:
            task_type = "transfer"
            output_token = ""
        elif "approve" in msg_lower or "授权" in user_message:
            task_type = "approve_only"
            output_token = ""

        # Always use bidding mode — every task goes through A2A open-bidding
        task_type = "bidding"

        # Detect action
        if "submit" in msg_lower or "提交" in user_message:
            action = "submit"
        elif "complete" in msg_lower or "完成" in user_message:
            action = "complete"
        elif "reject" in msg_lower or "拒绝" in user_message:
            action = "reject"
        elif "create" in msg_lower or ("发布" in user_message and "任务" in user_message):
            action = "create_job"

        # Extract amounts with regex
        eth_match = re.search(r'(\d+\.?\d*)\s*ETH', user_message, re.IGNORECASE)
        if eth_match:
            input_amount = eth_match.group(1)
            input_token = "ETH_mock"

        usdt_amount_match = re.search(r'(\d+\.?\d*)\s*USDT', user_message, re.IGNORECASE)
        if usdt_amount_match:
            output_amount = usdt_amount_match.group(1)
            output_token = "USDT_mock"

        ttk_match = re.search(r'(\d+)\s*TTK', user_message, re.IGNORECASE)
        if ttk_match:
            reward_amount = ttk_match.group(1)

        return ParsedIntent(
            role=role,
            action=action,
            task_type=task_type,
            params={
                "input_token": input_token,
                "input_amount": input_amount,
                "output_token": output_token,
                "output_amount": output_amount,
                "reward_token": "TTK",
                "reward_amount": reward_amount,
            },
            reasoning=f"[MOCK] Keyword-matched intent from: {user_message[:100]}...",
            confidence=0.85
        )

    def simulate_llm_chat(self, system_prompt: str, user_message: str) -> LLMResponse:
        """Simulate a general LLM chat response."""
        intent = self.simulate_parse_intent(user_message)

        # Build a chat-like response
        raw = (
            f"[MOCK LLM Response]\n"
            f"Role: {intent.role}\n"
            f"Action: {intent.action}\n"
            f"Task: {intent.task_type}\n"
            f"Params: {json.dumps(intent.params, indent=2)}"
        )

        return LLMResponse(
            raw_text=raw,
            parsed_json={
                "role": intent.role,
                "action": intent.action,
                "task_type": intent.task_type,
                "params": intent.params,
                "reasoning": intent.reasoning,
                "confidence": intent.confidence,
            },
            token_usage=len(user_message) // 4,
            latency_ms=random.uniform(100, 300)
        )

    def simulate_judge_deliverable(self, job_details: dict, onchain_data: dict) -> dict:
        """Simulate Evaluator LLM judging a deliverable. Always approves in mock."""
        return {
            "action": "complete",
            "reason_hash": "0x" + hashlib.sha256(b"mock-accept").hexdigest()[:64],
            "reasoning": "[MOCK] Deliverable meets requirements. Auto-accepting.",
            "confidence": 0.95
        }

    # ==================================================================
    # Chain Simulation
    # ==================================================================

    def simulate_chain_state(self, job_id: int, step: str) -> dict:
        """
        Return simulated on-chain state for a given job_id + step.
        Used by EvaluatorAgent to "read" chain state.
        """
        states = {
            "create_job": {"status": 0, "balance": "0", "desc": "Job created, awaiting budget"},
            "set_budget": {"status": 0, "budget": "100000000000000000000", "desc": "Budget set"},
            "fund": {"status": 1, "escrow_balance": "100000000000000000000", "desc": "Funded"},
            "submit": {"status": 2, "deliverable_hash": "0x" + "ab" * 32, "desc": "Submitted"},
            "complete": {"status": 3, "provider_balance": "100000000000000000000", "desc": "Completed"},
        }
        return states.get(step, {"status": 0, "desc": "Unknown"})

    # ==================================================================
    # Error simulation (for testing error paths)
    # ==================================================================

    def simulate_error(self, error_type: str) -> Exception:
        """Generate a simulated error for testing error handling."""
        from error_handler import (
            CAWTimeoutError, CAWRejectedError, LLMAPIError,
            OnChainRevertError, NetworkError
        )
        mapping = {
            "timeout": CAWTimeoutError("[MOCK] Simulated CAW timeout"),
            "rejected": CAWRejectedError("[MOCK] Simulated Pact rejection"),
            "llm": LLMAPIError("[MOCK] Simulated LLM API failure"),
            "revert": OnChainRevertError("[MOCK] Simulated on-chain revert"),
            "network": NetworkError("[MOCK] Simulated network failure"),
        }
        return mapping.get(error_type, Exception(f"[MOCK] Simulated error: {error_type}"))
