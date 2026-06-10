"""
session_state.py — Typed wrapper around st.session_state.
Provides safe get/set with defaults, type checking, and bulk reset.
"""

from typing import Optional, Any
from datetime import datetime
import uuid

# Lazy import to avoid circular deps at module level
# Streamlit must be imported inside methods that touch st.session_state


class SessionStateManager:
    """
    Typed wrapper around st.session_state.
    Provides safe get/set with defaults, type checking, and bulk reset.
    """

    # Default values for all keys
    DEFAULTS = {
        "workflow": None,           # WorkflowSession or None
        "chat_history": [],         # list of {"role": "user"|"assistant", "content": str}
        "mock_mode": True,          # SKIP_CAW flag
        "show_debug_log": False,    # Expand debug log by default?
        "auto_approve": False,      # Skip CAW approval polling in mock mode
        "rpc_url": "",
        "api_key": "",
    }

    def __init__(self, st_session_state: Any):
        """
        Args:
            st_session_state: The st.session_state dict-like object.
        """
        self._ss = st_session_state
        self._init_defaults()

    def _init_defaults(self) -> None:
        """Initialize all session state keys with defaults if not already set."""
        for key, default in self.DEFAULTS.items():
            if key not in self._ss:
                if key == "workflow":
                    self._ss[key] = None
                elif key == "chat_history":
                    self._ss[key] = []
                else:
                    self._ss[key] = default

    # --- Typed accessors ---

    def get_workflow(self):
        """Get current workflow session, or None if idle."""
        return self._ss.get("workflow")

    def set_workflow(self, wf) -> None:
        """Store workflow session."""
        self._ss["workflow"] = wf

    def update_workflow(self, **kwargs) -> None:
        """Partial update to workflow fields (merges into existing)."""
        wf = self._ss.get("workflow")
        if wf is not None:
            for k, v in kwargs.items():
                setattr(wf, k, v)

    def get_chat_history(self) -> list:
        """Get chat message history."""
        return self._ss.get("chat_history", [])

    def add_chat_message(self, role: str, content: str) -> None:
        """Append a message to chat history."""
        history = self._ss.get("chat_history", [])
        history.append({
            "role": role,
            "content": content,
            "timestamp": datetime.now().isoformat()
        })
        self._ss["chat_history"] = history

    def add_log_entry(self, source: str, message: str) -> None:
        """
        Append a debug log entry.
        source: 'LLM', 'PACT', 'CAW', 'ERROR', 'MOCK'
        """
        wf = self._ss.get("workflow")
        if wf is not None:
            wf.log_entries.append({
                "source": source,
                "message": message,
                "timestamp": datetime.now().isoformat()
            })

    def is_mock_mode(self) -> bool:
        """Check if SKIP_CAW flag is enabled."""
        return self._ss.get("mock_mode", True)

    def toggle_mock_mode(self) -> bool:
        """Toggle mock mode and return new value."""
        current = self._ss.get("mock_mode", True)
        self._ss["mock_mode"] = not current
        return self._ss["mock_mode"]

    def reset_workflow(self) -> None:
        """Clear workflow state, keep chat history and settings."""
        from caw_types import WorkflowSession
        self._ss["workflow"] = WorkflowSession(
            session_id=str(uuid.uuid4()),
            created_at=datetime.now().isoformat(),
            mock_mode=self._ss.get("mock_mode", True)
        )

    def reset_all(self) -> None:
        """Full reset: clear everything including chat history."""
        for key, default in self.DEFAULTS.items():
            if key == "chat_history":
                self._ss[key] = []
            elif key == "workflow":
                self._ss[key] = None
            else:
                self._ss[key] = default

    # --- Progress helpers ---

    def update_role_progress(self, role: str, progress: float) -> None:
        """
        Update progress percentage for a role.
        Validates 0.0 <= progress <= 100.0.
        """
        progress = max(0.0, min(100.0, progress))
        wf = self._ss.get("workflow")
        if wf is not None:
            if role == "client":
                wf.client_progress = progress
            elif role == "provider":
                wf.provider_progress = progress
            elif role == "evaluator":
                wf.evaluator_progress = progress

    def advance_step(self, new_step: int, message: str = "") -> None:
        """
        Advance current_step and update status_message.
        """
        wf = self._ss.get("workflow")
        if wf is not None:
            wf.current_step = new_step
            if message:
                wf.status_message = message

    def record_transaction(
        self,
        step_name: str,
        tx_hash: str,
        status: str = "pending",
        etherscan_link: str = ""
    ) -> None:
        """Record a completed (or pending) transaction."""
        wf = self._ss.get("workflow")
        if wf is not None:
            wf.tx_history.append({
                "step": step_name,
                "tx_hash": tx_hash,
                "status": status,
                "etherscan_link": etherscan_link,
                "timestamp": datetime.now().isoformat()
            })

    # --- Convenience ---

    def ensure_workflow(self) -> None:
        """Ensure a workflow session exists, creating one if needed."""
        if self._ss.get("workflow") is None:
            self.reset_workflow()
