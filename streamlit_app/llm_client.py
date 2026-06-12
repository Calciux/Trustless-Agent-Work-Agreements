"""
llm_client.py — Wrapper around DeepSeek / OpenAI chat completions API.
Builds role-specific system prompts, sends messages,
and parses structured JSON responses. Delegates to MockHandler when SKIP_CAW=True.
"""

import json
import time
import re
from typing import Optional, Any

from config import (
    LLM_PROVIDER, LLM_MODEL, LLM_API_KEY, LLM_BASE_URL,
    LLM_TEMPERATURE, LLM_MAX_TOKENS, SKIP_CAW,
    ESCROW_ADDR, TTK_ADDR, ETH_MOCK_ADDR, USDT_MOCK_ADDR,
)
from caw_types import LLMResponse, ParsedIntent, LLMProvider


class LLMClient:
    """
    Wrapper around DeepSeek / OpenAI chat completions API.
    Builds role-specific system prompts, sends messages,
    and parses structured JSON responses.
    """

    # System prompt templates per role
    SYSTEM_PROMPTS = {
        "client": (
            "You are a Client Agent for the ERC-8183 Agentic Commerce Protocol. "
            "Your job is to parse user requirements and determine the correct "
            "on-chain operations. Output JSON with fields: role, action, task_type, "
            "params (including input_token, input_amount, output_token, output_amount, "
            "reward_token, reward_amount), reasoning, confidence, "
            "human_description (a short natural-language explanation in Chinese of "
            "what the workflow will do, written for a non-technical user).\n\n"
            "Available tokens on Sepolia:\n"
            f"- TTK ({TTK_ADDR}): reward token\n"
            f"- ETH mock ({ETH_MOCK_ADDR}): mock ETH\n"
            f"- USDT mock ({USDT_MOCK_ADDR}): mock USDT\n"
            f"Contract: ERC8183Escrow at {ESCROW_ADDR}\n\n"
            "IMPORTANT: ALWAYS set task_type='bidding'. Every task MUST go through the "
            "open-bidding workflow where multiple providers submit signed price quotes "
            "and the lowest bidder wins. There is no non-bidding mode.\n\n"
            "Always output valid JSON only, no markdown fences."
        ),
        "provider": (
            "You are a Provider Agent. You receive job details and must generate "
            "a deliverable hash and submit it on-chain. Output JSON with: role, "
            "action (submit), job_id, deliverable_description, deliverable_hash, "
            "reasoning.\n\n"
            "Always output valid JSON only, no markdown fences."
        ),
        "evaluator": (
            "You are an Evaluator Agent for a trustless escrow system (ERC-8183). "
            "Your job: review the Provider's submitted deliverable and decide whether to complete (release payment) or reject (refund client).\n\n"
            "RULES:\n"
            "- If the deliverable hash is NOT a dummy/placeholder (not all same bytes like 0xabab..., 0x0000..., 0xffff...), "
            "and the job has been funded (status shows Funded or Submitted), ACCEPT it (action: complete).\n"
            "- If the deliverable is clearly a dummy/placeholder, REJECT (action: reject).\n"
            "- For demo/hackathon submissions, be lenient: if any real work evidence exists, approve.\n"
            "- reason_hash: use the deliverable hash as-is.\n\n"
            "CRITICAL: You MUST provide a detailed 'reasoning' field (2-3 sentences in Chinese) explaining WHY you accepted or rejected. "
            "For rejects, explain specifically what was wrong (e.g. 'deliverable hash is all zeros, no real work submitted'). "
            "For accepts, explain what evidence convinced you (e.g. 'submitted a valid swap tx hash on Sepolia').\n\n"
            "Output JSON only, no markdown fences: "
            '{"role":"evaluator","action":"complete|reject","job_id":<int>,"reason_hash":"<bytes32>","reasoning":"<explanation>","confidence":<0.0-1.0>}'
        ),
    }

    def __init__(
        self,
        provider: LLMProvider = LLMProvider.DEEPSEEK,
        api_key: Optional[str] = None,
        model: str = "deepseek-chat",
        temperature: float = 0.1,
        max_tokens: int = 2000,
        base_url: Optional[str] = None,
        mock_handler=None
    ):
        self.provider = provider
        self.api_key = api_key or LLM_API_KEY
        self.model = model or LLM_MODEL
        self.temperature = temperature or LLM_TEMPERATURE
        self.max_tokens = max_tokens or LLM_MAX_TOKENS
        self.base_url = base_url or LLM_BASE_URL
        self._mock = mock_handler  # injected by orchestrator for mock mode
        self.mock_mode = SKIP_CAW  # can be toggled at runtime by app.py

        # Lazy client init
        self._client = None

    def _get_client(self):
        """Lazy-init the OpenAI-compatible client."""
        if self._client is None:
            try:
                from openai import OpenAI
                self._client = OpenAI(
                    api_key=self.api_key,
                    base_url=self.base_url
                )
            except ImportError:
                raise ImportError(
                    "openai package is required. Install with: pip install openai"
                )
        return self._client

    # ------------------------------------------------------------------
    # Core chat method
    # ------------------------------------------------------------------

    def chat(
        self,
        system_prompt: str,
        user_message: str,
        response_schema: Optional[dict] = None
    ) -> LLMResponse:
        """
        Send a chat completion request with optional structured output.

        Args:
            system_prompt: System-level instructions.
            user_message: User's natural language input.
            response_schema: Optional JSON schema for structured output mode.

        Returns:
            LLMResponse with raw_text and parsed_json.
        """
        # Mock mode delegation
        if self.mock_mode and self._mock is not None:
            return self._mock.simulate_llm_chat(system_prompt, user_message)

        start = time.time()

        try:
            client = self._get_client()
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ]

            kwargs = {
                "model": self.model,
                "messages": messages,
                "temperature": self.temperature,
                "max_tokens": self.max_tokens,
            }

            if response_schema:
                kwargs["response_format"] = {"type": "json_schema", "json_schema": response_schema}

            response = client.chat.completions.create(**kwargs)

            raw_text = response.choices[0].message.content or ""
            token_usage = response.usage.total_tokens if response.usage else 0
            latency_ms = (time.time() - start) * 1000

            # Try to parse JSON
            parsed = None
            try:
                parsed = json.loads(raw_text)
            except json.JSONDecodeError:
                # Try extracting JSON from markdown fences
                match = re.search(r'```(?:json)?\s*([\s\S]*?)```', raw_text)
                if match:
                    try:
                        parsed = json.loads(match.group(1))
                    except json.JSONDecodeError:
                        pass

            return LLMResponse(
                raw_text=raw_text,
                parsed_json=parsed,
                token_usage=token_usage,
                latency_ms=latency_ms
            )

        except Exception as e:
            from error_handler import LLMAPIError
            raise LLMAPIError(f"LLM API call failed: {e}")

    # ------------------------------------------------------------------
    # High-level methods
    # ------------------------------------------------------------------

    def parse_intent(self, user_message: str, role_hint: str = "client") -> ParsedIntent:
        """
        Parse a user's natural language message into a structured intent.
        """
        # Mock mode
        if self.mock_mode and self._mock is not None:
            return self._mock.simulate_parse_intent(user_message)

        system = self.SYSTEM_PROMPTS.get(role_hint, self.SYSTEM_PROMPTS["client"])
        response = self.chat(system, user_message)

        if response.parsed_json is None:
            from error_handler import LLMParseError
            raise LLMParseError(
                f"Failed to parse LLM response as JSON. Raw: {response.raw_text[:200]}"
            )

        data = response.parsed_json
        return ParsedIntent(
            role=data.get("role", "client"),
            action=data.get("action", "create_job"),
            task_type=data.get("task_type", ""),
            params=data.get("params", {}),
            reasoning=data.get("reasoning", ""),
            confidence=float(data.get("confidence", 0.0)),
            human_description=data.get("human_description", ""),
        )

    def generate_pact_params(
        self,
        intent: ParsedIntent,
        step: str
    ) -> dict:
        """Generate step-specific Pact parameters from a parsed intent."""
        # In mock mode, delegate
        if self.mock_mode and self._mock is not None:
            return self._extract_params_from_intent(intent, step)

        system = (
            f"You are a Pact parameter generator for ERC-8183. "
            f"Given the parsed intent and step '{step}', output the parameters "
            f"needed for the Pact template. Output JSON only."
        )
        user = json.dumps({
            "intent": {
                "role": intent.role,
                "action": intent.action,
                "task_type": intent.task_type,
                "params": intent.params
            },
            "step": step,
        })
        response = self.chat(system, user)
        if response.parsed_json:
            return response.parsed_json
        return self._extract_params_from_intent(intent, step)

    def judge_deliverable(
        self,
        job_details: dict,
        onchain_data: dict
    ) -> dict:
        """
        Evaluator: judge whether a submitted deliverable meets requirements.
        """
        if self.mock_mode and self._mock is not None:
            return self._mock.simulate_judge_deliverable(job_details, onchain_data)

        system = self.SYSTEM_PROMPTS["evaluator"]
        user = json.dumps({
            "job_details": job_details,
            "onchain_data": onchain_data,
        })
        response = self.chat(system, user)
        if response.parsed_json:
            return response.parsed_json
        return {"action": "complete", "reason_hash": "0x00", "reasoning": "Default accept"}

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _extract_params_from_intent(self, intent: ParsedIntent, step: str) -> dict:
        """Extract params from intent without LLM (used in mock mode)."""
        p = intent.params
        result = {}

        if step == "approve_ttk":
            from decimal import Decimal
            amount = p.get("reward_amount", "100")
            result["ttk_amount"] = str(int(Decimal(amount) * Decimal(10**18)))
            result["max_ttk"] = str(int(Decimal(amount) * Decimal(10**18) * 2))
        elif step in ("create_job", "set_budget", "fund"):
            result["max_eth"] = "1000000000000000000"  # 1 ETH
            result["max_tx"] = "5"
            result["step_count"] = "1"
            if step == "fund":
                from decimal import Decimal
                result["fund_amount"] = str(int(Decimal(p.get("reward_amount", "100")) * Decimal(10**18)))
        elif step == "submit":
            result["deliverable_hash"] = "0x" + "ab" * 32
        elif step in ("complete", "reject"):
            result["action"] = step
            result["selector"] = "0xcd56b1b6" if step == "complete" else "0x6be1320b"
            result["reason_hash"] = "0x" + "ff" * 32

        return result
