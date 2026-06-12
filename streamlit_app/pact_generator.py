"""
pact_generator.py — Loads Pact JSON templates from templates/,
fills {{placeholders}} with actual values, and validates the resulting JSON.
"""

import json
import os
from pathlib import Path
from typing import Optional

from config import (
    ESCROW_ADDR, TTK_ADDR, ETH_MOCK_ADDR, USDT_MOCK_ADDR,
    CHAIN, CLIENT_UUID, PROVIDER_UUID, EVALUATOR_UUID,
    SEL_APPROVE, SEL_CREATE_JOB, SEL_SET_BUDGET, SEL_FUND,
    SEL_SUBMIT, SEL_COMPLETE, SEL_REJECT,
    SEL_SETPROVIDER_EXT,
    PACT_OPTIMIZED, CLIENT_TOTAL_OPS, CLIENT_TOTAL_OPS_BIDDING,
    BIDDING_HOOK_ADDR,
)
from caw_types import PactTemplate, JobContext


class PactGenerator:
    """
    Loads Pact JSON templates from the templates/ directory,
    fills {{placeholders}} with actual values from the JobContext,
    and validates the resulting JSON structure.
    """

    # Mapping of (role, step) -> template filename
    TEMPLATE_MAP = {
        ("client", "approve_ttk"): "pact_client_approve.json",
        ("client", "create_task"): "pact_client_escrow.json",
        ("client", "create_job"):  "pact_client_escrow.json",
        ("client", "set_budget"):  "pact_client_escrow.json",
        ("client", "fund"):        "pact_client_escrow.json",
        ("provider", "submit"):    "pact_provider_submit.json",
        ("evaluator", "complete"): "pact_evaluator_resolve.json",
        ("evaluator", "reject"):   "pact_evaluator_resolve.json",
    }

    # Optimized mapping: all client steps -> merged Pact, other roles unchanged
    TEMPLATE_MAP_OPTIMIZED = {
        ("client", "approve_ttk"): "optimized/pact_client_merged.json",
        ("client", "create_task"): "optimized/pact_client_merged.json",
        ("client", "create_job"):  "optimized/pact_client_merged.json",
        ("client", "set_budget"):  "optimized/pact_client_merged.json",
        ("client", "fund"):        "optimized/pact_client_merged.json",
        ("provider", "submit"):    "optimized/pact_provider_submit.json",
        ("evaluator", "complete"): "optimized/pact_evaluator_resolve.json",
        ("evaluator", "reject"):   "optimized/pact_evaluator_resolve.json",
    }

    # Bidding mapping: all client steps -> bidding merged Pact (includes setProvider)
    TEMPLATE_MAP_BIDDING = {
        ("client", "approve_ttk"):  "optimized/pact_client_bidding.json",
        ("client", "create_task"):  "optimized/pact_client_bidding.json",
        ("client", "create_job"):   "optimized/pact_client_bidding.json",
        ("client", "set_provider"): "optimized/pact_client_bidding.json",
        ("client", "set_budget"):   "optimized/pact_client_bidding.json",
        ("client", "fund"):         "optimized/pact_client_bidding.json",
        ("provider", "submit"):     "optimized/pact_provider_submit.json",
        ("evaluator", "complete"):  "optimized/pact_evaluator_resolve.json",
        ("evaluator", "reject"):    "optimized/pact_evaluator_resolve.json",
    }

    def __init__(self, templates_dir: str = None):
        """
        Args:
            templates_dir: Path to the Pact template JSON files.
                           Defaults to templates/ relative to this file.
        """
        if templates_dir is None:
            templates_dir = Path(__file__).resolve().parent / "templates"
        self.templates_dir = Path(templates_dir)
        self._template_cache: dict[str, PactTemplate] = {}

    # ------------------------------------------------------------------
    # Template loading
    # ------------------------------------------------------------------

    def load_template(self, role: str, step: str, context: JobContext = None) -> PactTemplate:
        """
        Load a template JSON file from disk.

        Args:
            role: Agent role (client/provider/evaluator).
            step: Workflow step name.
            context: Optional JobContext -- used to detect bidding flow.

        Returns:
            PactTemplate with policies and conditions loaded.

        Raises:
            FileNotFoundError: If template file doesn't exist.
            json.JSONDecodeError: If template file is malformed.
        """
        cache_key = f"{role}:{step}"
        if cache_key in self._template_cache:
            return self._template_cache[cache_key]

        # Select template map based on mode:
        #   - bidding context + PACT_OPTIMIZED -> TEMPLATE_MAP_BIDDING
        #   - PACT_OPTIMIZED                   -> TEMPLATE_MAP_OPTIMIZED
        #   - else                             -> TEMPLATE_MAP (original)
        is_bidding = (
            PACT_OPTIMIZED
            and context is not None
            and hasattr(context, 'chain_data')
            and context.chain_data.get("bidding", {}).get("is_bidding", False)
        )

        if is_bidding:
            template_map = self.TEMPLATE_MAP_BIDDING
        elif PACT_OPTIMIZED:
            template_map = self.TEMPLATE_MAP_OPTIMIZED
        else:
            template_map = self.TEMPLATE_MAP
        filename = template_map.get((role, step))
        if filename is None:
            raise ValueError(f"No template for role={role}, step={step}")

        filepath = self.templates_dir / filename
        if not filepath.exists():
            raise FileNotFoundError(f"Template not found: {filepath}")

        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)

        template = PactTemplate(
            name=data.get("name", filename),
            role=role,
            step=step,
            policies_json=data.get("policies", data.get("rules", {})),
            completion_conditions=data.get("completion_conditions", []),
            raw_data=data,
        )

        self._template_cache[cache_key] = template
        return template

    # ------------------------------------------------------------------
    # Placeholder filling
    # ------------------------------------------------------------------

    def fill_template(
        self,
        template: PactTemplate,
        job_id,
        chain: str = "SETH",
        **overrides
    ) -> dict:
        """
        Fill {{placeholders}} in the template with actual values.

        Standard placeholders filled automatically:
            {{chain}}          -> chain (default "SETH")
            {{ttk_addr}}       -> TTK_ADDR
            {{escrow_addr}}    -> ESCROW_ADDR
            {{job_id}}         -> job_id
            {{max_ttk}}        -> from overrides
            {{max_eth}}        -> from overrides
            {{max_tx}}         -> from overrides
            {{step_count}}     -> from overrides
            {{action}}         -> "complete" or "reject"
            {{selector}}       -> function selector from config
            {{ttk_amount}}     -> from overrides
            {{deliverable_hash}} -> from overrides
            {{reason_hash}}    -> from overrides
        """
        # Use full raw_data to preserve name, type, and other top-level fields
        full_str = json.dumps(template.raw_data, indent=2)

        # Standard replacements
        replacements = {
            "{{chain}}":          chain,
            "{{ttk_addr}}":       TTK_ADDR,
            "{{escrow_addr}}":    ESCROW_ADDR,
            "{{bidding_hook_addr}}": BIDDING_HOOK_ADDR,
            "{{job_id}}":         str(job_id),
            "{{original_intent}}": overrides.get("original_intent", ""),
            "{{max_ttk}}":        overrides.get("max_ttk", "200000000000000000000"),
            "{{max_eth}}":        overrides.get("max_eth", "1000000000000000000"),
            "{{max_tx}}":         overrides.get("max_tx", "5"),
            "{{step_count}}":     overrides.get("step_count", "1"),
            "{{action}}":         overrides.get("action", "complete"),
            "{{selector}}":       overrides.get("selector", SEL_COMPLETE),
            "{{ttk_amount}}":     overrides.get("ttk_amount", "100000000000000000000"),
            "{{deliverable_hash}}": overrides.get("deliverable_hash", "0x" + "00" * 32),
            "{{reason_hash}}":    overrides.get("reason_hash", "0x" + "00" * 32),
            "{{fund_amount}}":    overrides.get("fund_amount", "0"),
        }

        # Apply all replacements
        for placeholder, value in replacements.items():
            full_str = full_str.replace(placeholder, str(value))

        # Parse back to dict
        pact = json.loads(full_str)
        return pact

    # ------------------------------------------------------------------
    # High-level convenience
    # ------------------------------------------------------------------

    def generate_for_step(
        self,
        role: str,
        step: str,
        context: JobContext
    ) -> dict:
        """
        High-level convenience: load -> fill -> validate -> return.

        Args:
            role: Agent role.
            step: Step name.
            context: Current JobContext with all parameters.

        Returns:
            Validated Pact JSON dict.
        """
        template = self.load_template(role, step, context)
        overrides = self._extract_overrides(context, step)
        job_id = context.job_id if context.job_id is not None else "auto"
        pact = self.fill_template(template, job_id, **overrides)
        self.validate_pact(pact)
        return pact

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def validate_pact(self, pact: dict) -> None:
        """
        Validate Pact JSON structure.

        Checks:
            - Required top-level keys: name, type
            - No unresolved {{placeholders}} remain
            - Rules/policies have effect 'allow'

        Raises:
            ValueError: If validation fails, with descriptive message.
        """
        if not isinstance(pact, dict):
            raise ValueError("Pact must be a JSON object (dict)")

        # Check for unresolved placeholders
        pact_str = json.dumps(pact)
        if "{{" in pact_str and "}}" in pact_str:
            # Find which ones remain
            import re
            unresolved = set(re.findall(r'\{\{(\w+)\}\}', pact_str))
            if unresolved:
                raise ValueError(
                    f"Unresolved placeholders remain in Pact: {', '.join(unresolved)}"
                )

        # Check required keys -- templates use "policies" (also support "rules" as alias)
        policy_block = pact.get("policies") or pact.get("rules") or {}
        if isinstance(policy_block, dict):
            effect = policy_block.get("effect", "")
            if effect and effect != "allow":
                raise ValueError(f"Pact policies.effect must be 'allow', got '{effect}'")

        # Check name and type are present
        if "name" not in pact:
            raise ValueError("Pact missing required 'name' field")

    # ------------------------------------------------------------------
    # Override extraction
    # ------------------------------------------------------------------

    def _extract_overrides(
        self,
        context: JobContext,
        step: str
    ) -> dict:
        """
        Extract step-specific override values from JobContext.

        In optimized mode (PACT_OPTIMIZED=true):
          - max_eth derives from context.input_amount (user's stated budget)
          - step_count reflects all operations in the merged Pact
          - original_intent is passed through for the Pact metadata

        In original mode (PACT_OPTIMIZED=false):
          - Uses hardcoded safe defaults (1 ETH cap, etc.)
        """
        from decimal import Decimal, InvalidOperation
        overrides = {}

        # Common: chain is always available
        overrides["chain"] = "SETH"

        # Derive budget from user intent (optimized mode) or use defaults
        if PACT_OPTIMIZED:
            # TTK budget from reward_amount
            reward_str = context.reward_amount or "100"
            try:
                reward_wei = str(int(Decimal(reward_str) * Decimal(10**18)))
            except (InvalidOperation, ValueError):
                reward_wei = "100000000000000000000"
            max_ttk = str(int(Decimal(reward_wei)) * 2)  # 2x buffer

            # ETH budget from input_amount (e.g., "0.1" ETH -> 0.1 * 10^18 with 10x buffer)
            input_str = context.input_amount or "0.1"
            try:
                input_wei = str(int(Decimal(input_str) * Decimal(10**18) * 10))  # 10x safety
            except (InvalidOperation, ValueError):
                input_wei = "1000000000000000000"  # fallback: 1 ETH
        else:
            # Original mode: hardcoded safe defaults
            reward_str = context.reward_amount or "100"
            try:
                reward_wei = str(int(Decimal(reward_str) * Decimal(10**18)))
            except (InvalidOperation, ValueError):
                reward_wei = "100000000000000000000"
            max_ttk = str(int(Decimal(reward_wei)) * 2)
            input_wei = "1000000000000000000"  # 1 ETH

        # Pass through original intent for Pact metadata
        overrides["original_intent"] = getattr(context, "original_intent", "") or ""

        if step == "approve_ttk":
            overrides["ttk_amount"] = reward_wei
            overrides["max_ttk"] = max_ttk
            # In optimized mode, the merged Pact also needs escrow policy values
            if PACT_OPTIMIZED:
                overrides["max_eth"] = input_wei
                overrides["max_tx"] = str(CLIENT_TOTAL_OPS + 2)
                overrides["step_count"] = str(CLIENT_TOTAL_OPS)

        elif step in ("create_job", "set_budget", "fund", "set_provider"):
            overrides["max_eth"] = input_wei
            is_bidding = (
                hasattr(context, 'chain_data')
                and context.chain_data.get("bidding", {}).get("is_bidding", False)
            )
            if is_bidding:
                overrides["max_tx"] = str(CLIENT_TOTAL_OPS_BIDDING + 2)  # 5 ops + 2 buffer = 7
            else:
                overrides["max_tx"] = str(CLIENT_TOTAL_OPS + 2)  # 4 ops + 2 buffer = 6
            if PACT_OPTIMIZED:
                if is_bidding:
                    overrides["step_count"] = str(CLIENT_TOTAL_OPS_BIDDING)
                else:
                    # Merged Pact covers all 4 client steps
                    overrides["step_count"] = str(CLIENT_TOTAL_OPS)
            else:
                if step == "create_job":
                    overrides["step_count"] = "3"  # createJob + setBudget + fund
                elif step == "set_budget":
                    overrides["step_count"] = "3"
                elif step == "fund":
                    overrides["step_count"] = "3"
                    from decimal import Decimal
                    ttk_amount = str(int(Decimal(context.reward_amount or "100") * Decimal(10**18)))
                    overrides["fund_amount"] = ttk_amount
                elif step == "set_provider":
                    overrides["step_count"] = "1"

        elif step == "submit":
            # Generate a deterministic deliverable hash from job context
            import hashlib
            seed = f"{context.job_id}:{context.task_type}:{context.input_token}:{context.input_amount}"
            overrides["deliverable_hash"] = "0x" + hashlib.sha256(seed.encode()).hexdigest()[:64]

        elif step == "complete":
            overrides["action"] = "complete"
            overrides["selector"] = SEL_COMPLETE
            overrides["reason_hash"] = "0x" + "ff" * 32  # hash representing "approved"

        elif step == "reject":
            overrides["action"] = "reject"
            overrides["selector"] = SEL_REJECT
            overrides["reason_hash"] = "0x" + "00" * 32  # hash representing "rejected"

        return overrides

    # ------------------------------------------------------------------
    # Utility
    # ------------------------------------------------------------------

    def list_templates(self) -> list:
        """List all available templates (for debugging / UI display)."""
        templates = []
        for (role, step), filename in self.TEMPLATE_MAP.items():
            filepath = self.templates_dir / filename
            exists = filepath.exists()
            templates.append({
                "role": role,
                "step": step,
                "filename": filename,
                "exists": exists
            })
        return templates
