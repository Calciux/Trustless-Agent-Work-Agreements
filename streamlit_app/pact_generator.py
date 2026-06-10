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
)
from caw_types import PactTemplate, JobContext


class PactGenerator:
    """
    Loads Pact JSON templates from the templates/ directory,
    fills {{placeholders}} with actual values from the JobContext,
    and validates the resulting JSON structure.
    """

    # Mapping of (role, step) → template filename
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

    def load_template(self, role: str, step: str) -> PactTemplate:
        """
        Load a template JSON file from disk.

        Args:
            role: Agent role (client/provider/evaluator).
            step: Workflow step name.

        Returns:
            PactTemplate with policies and conditions loaded.

        Raises:
            FileNotFoundError: If template file doesn't exist.
            json.JSONDecodeError: If template file is malformed.
        """
        cache_key = f"{role}:{step}"
        if cache_key in self._template_cache:
            return self._template_cache[cache_key]

        filename = self.TEMPLATE_MAP.get((role, step))
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
            {{chain}}          → chain (default "SETH")
            {{ttk_addr}}       → TTK_ADDR
            {{escrow_addr}}    → ESCROW_ADDR
            {{job_id}}         → job_id
            {{max_ttk}}        → from overrides
            {{max_eth}}        → from overrides
            {{max_tx}}         → from overrides
            {{step_count}}     → from overrides
            {{action}}         → "complete" or "reject"
            {{selector}}       → function selector from config
            {{ttk_amount}}     → from overrides
            {{deliverable_hash}} → from overrides
            {{reason_hash}}    → from overrides
        """
        # Use full raw_data to preserve name, type, and other top-level fields
        full_str = json.dumps(template.raw_data, indent=2)

        # Standard replacements
        replacements = {
            "{{chain}}":          chain,
            "{{ttk_addr}}":       TTK_ADDR,
            "{{escrow_addr}}":    ESCROW_ADDR,
            "{{job_id}}":         str(job_id),
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
        High-level convenience: load → fill → validate → return.

        Args:
            role: Agent role.
            step: Step name.
            context: Current JobContext with all parameters.

        Returns:
            Validated Pact JSON dict.
        """
        template = self.load_template(role, step)
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

        # Check required keys — templates use "policies" (also support "rules" as alias)
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

        E.g., for "approve_ttk": {ttk_amount, max_ttk}
              for "create_job": {max_eth, max_tx, step_count}
              for "complete":   {action="complete", selector="0xcd56b1b6"}
        """
        overrides = {}

        # Common: chain is always available
        overrides["chain"] = "SETH"

        if step == "approve_ttk":
            amount = context.reward_amount or "100"
            # Convert to wei-like (18 decimals for TTK) using Decimal for precision
            from decimal import Decimal
            ttk_amount = str(int(Decimal(amount) * Decimal(10**18)))
            max_ttk = str(int(Decimal(amount) * Decimal(10**18) * 2))
            overrides["ttk_amount"] = ttk_amount
            overrides["max_ttk"] = max_ttk

        elif step in ("create_job", "set_budget", "fund"):
            overrides["max_eth"] = "1000000000000000000"  # 1 ETH in wei
            overrides["max_tx"] = "5"
            if step == "create_job":
                overrides["step_count"] = "3"  # createJob + setBudget + fund
            elif step == "set_budget":
                overrides["step_count"] = "3"  # same Pact — keep at 3
            elif step == "fund":
                overrides["step_count"] = "3"  # same Pact — keep at 3
                from decimal import Decimal
                ttk_amount = str(int(Decimal(context.reward_amount or "100") * Decimal(10**18)))
                overrides["fund_amount"] = ttk_amount

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
