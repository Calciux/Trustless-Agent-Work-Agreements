"""
ui_components.py — Reusable Streamlit UI fragments.
Progress step indicator, role status cards, transaction history table,
expandable log section, mock mode banner. Keeps app.py clean.
"""

import streamlit as st
from typing import Optional

from caw_types import WorkflowStep
from config import PACT_OPTIMIZED  # for mode badge


# ---------------------------------------------------------------------------
# Step definitions for the progress indicator
# ---------------------------------------------------------------------------

STEPS = [
    (1, "Parse Intent", "🔍"),
    (2, "Generate Pact", "📄"),
    (3, "Submit to CAW", "📤"),
    (4, "CAW Approval", "✅"),
    (5, "On-chain Tx", "⛓️"),
    (6, "Complete", "🏁"),
]


def render_header():
    """Render the top header bar with title, mode badge, and mock mode toggle."""
    col1, col2, col3 = st.columns([3, 1, 1])
    with col1:
        st.title("🏦 Trustless Agent Work Agreements")
    with col2:
        if PACT_OPTIMIZED:
            st.markdown(
                '<div style="background:#e8f5e9;border:1px solid #4caf50;border-radius:8px;'
                'padding:8px 12px;text-align:center;margin-top:8px">'
                '<span style="color:#2e7d32;font-weight:600">🟢 自动审批模式</span><br>'
                '<span style="font-size:0.75em;color:#666">Pact策略自动放行</span></div>',
                unsafe_allow_html=True,
            )
        else:
            st.markdown(
                '<div style="background:#fff3e0;border:1px solid #ff9800;border-radius:8px;'
                'padding:8px 12px;text-align:center;margin-top:8px">'
                '<span style="color:#e65100;font-weight:600">🟠 手动审批模式</span><br>'
                '<span style="font-size:0.75em;color:#666">每步需在CAW App批准</span></div>',
                unsafe_allow_html=True,
            )
    with col3:
        mock_mode = st.toggle(
            "Mock Mode",
            value=st.session_state.get("mock_mode", True),
            help="Enable to test UI without real CAW/chain calls"
        )
        st.session_state["mock_mode"] = mock_mode

    if st.session_state.get("mock_mode", True):
        st.warning("⚠️ MOCK MODE ACTIVE — No real on-chain transactions", icon="⚠️")


def render_chat_panel(chat_history: list):
    """
    Render the chat history panel.
    Iterates through chat_history and renders user/assistant messages
    using st.chat_message().
    """
    for msg in chat_history:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        with st.chat_message(role):
            st.markdown(content)


def render_input_box(placeholder: str = "输入你的需求...") -> Optional[str]:
    """
    Render the chat input box pinned to the bottom of the left panel.
    Returns the user's input string, or None if empty.
    """
    return st.chat_input(placeholder)


def render_progress_steps(current_step: int = 0):
    """
    Render the 6-step workflow progress indicator.
    Each step shows: ○ (not started), ⟳ (in progress), ✓ (completed), ✗ (failed).
    """
    st.subheader("📋 Workflow Progress")

    for step_id, step_name, icon in STEPS:
        if current_step > step_id:
            symbol = "✓"
            color = "green"
        elif current_step == step_id:
            symbol = "⟳"
            color = "orange"
        elif current_step == 99:  # FAILED
            if step_id == 6:
                symbol = "✗"
                color = "red"
            elif current_step > step_id:
                symbol = "✓"
                color = "green"
            else:
                symbol = "○"
                color = "gray"
        else:
            symbol = "○"
            color = "gray"

        cols = st.columns([1, 10])
        with cols[0]:
            st.markdown(f"<span style='color:{color};font-size:20px'>{symbol}</span>",
                       unsafe_allow_html=True)
        with cols[1]:
            st.markdown(f"**STEP {step_id}**: {step_name}")

    # Show status message if available
    wf = st.session_state.get("workflow")
    if wf and wf.status_message:
        st.info(wf.status_message)


def render_role_status_cards(client_pct: float, provider_pct: float, evaluator_pct: float):
    """
    Render per-role progress cards with completion percentage and progress bars.
    """
    st.subheader("👤 Role Status")

    roles = [
        ("Client", "👤", client_pct, 4),
        ("Provider", "🔧", provider_pct, 1),
        ("Evaluator", "⚖️", evaluator_pct, 1),
    ]

    for role_name, emoji, pct, total_ops in roles:
        cols = st.columns([1, 8])
        with cols[0]:
            st.markdown(f"{emoji} **{role_name}**")
        with cols[1]:
            st.progress(pct / 100.0, text=f"{pct:.0f}%")
            completed = int(pct / 100 * total_ops)
            st.caption(f"{completed}/{total_ops} ops complete")


def render_tx_history(tx_list: list):
    """
    Render transaction history from timeline tx entries.
    Each entry: {kind:"tx", human:"...", technical:"...", tx_hash:"0x..."}
    Shows function name, contract, and clickable Etherscan link.
    """
    st.subheader("📜 Transaction History")

    if not tx_list:
        st.caption("No transactions yet")
        return

    import re

    for i, entry in enumerate(tx_list):
        human = entry.get("human", "")
        technical = entry.get("technical", "")
        tx_hash = entry.get("tx_hash", "")

        # Extract details from technical string
        contract_match = re.search(r'合约地址\*\*: `(0x[a-fA-F0-9]{40})`', technical)
        contract_name_match = re.search(r'\(([^)]+)\)', technical.split('\n')[0]) if contract_match else None
        func_match = re.search(r'函数签名\*\*: `([^`]+)`', technical)
        tx_hash_match = re.search(r'Tx Hash\*\*: `(0x[a-fA-F0-9]{64})`', technical)

        contract_name = contract_name_match.group(1) if contract_name_match else "合约"
        func_sig = func_match.group(1) if func_match else "?"
        tx_hash = tx_hash or (tx_hash_match.group(1) if tx_hash_match else "")

        # Human-readable function name
        func_name = func_sig
        if func_sig.startswith("0x"):
            from config import SEL_APPROVE, SEL_CREATE_JOB, SEL_SET_BUDGET, SEL_FUND, SEL_SUBMIT, SEL_COMPLETE, SEL_REJECT, SEL_SETPROVIDER_EXT
            sel_map = {
                SEL_APPROVE: "approve", SEL_CREATE_JOB: "createJob", SEL_SET_BUDGET: "setBudget",
                SEL_FUND: "fund", SEL_SUBMIT: "submit", SEL_COMPLETE: "complete", SEL_REJECT: "reject",
                SEL_SETPROVIDER_EXT: "setProvider",
            }
            func_name = sel_map.get(func_sig, func_sig[:10])
        else:
            func_name = func_sig.split("(")[0] if "(" in func_sig else func_sig

        # Step label from human
        step_label = human.split("\n")[0].replace("⛓️ 链上执行：", "").replace("**", "").strip()
        if not step_label:
            step_label = func_name

        # Etherscan link
        if tx_hash:
            etherscan_link = f"https://sepolia.etherscan.io/tx/{tx_hash}"
            link_html = f'<a href="{etherscan_link}" target="_blank" style="color:#4a90d9;text-decoration:none;">🔗 {tx_hash[:10]}...</a>'
        else:
            link_html = "⏳ 等待确认..."

        st.markdown(f"""
        <div style="border:1px solid #e0e0e0;border-radius:6px;padding:6px 10px;margin-bottom:4px;font-size:0.85em">
            <b>{step_label}</b><br>
            <span style="color:#888">{contract_name} · {func_name}</span><br>
            {link_html}
        </div>
        """, unsafe_allow_html=True)


def render_log_expander(log_entries: list):
    """
    Render an expandable debug log section.
    Shows raw LLM prompts, Pact JSON, CAW CLI output, and errors.
    """
    with st.expander("📋 Debug Log", expanded=st.session_state.get("show_debug_log", False)):
        if not log_entries:
            st.caption("No log entries yet")
            return

        # Filter controls
        sources = st.multiselect(
            "Filter by source",
            options=["LLM", "PACT", "CAW", "ERROR", "MOCK"],
            default=["LLM", "PACT", "CAW", "ERROR", "MOCK"],
            key="log_filter"
        )

        for entry in reversed(log_entries):
            source = entry.get("source", "UNKNOWN")
            if source not in sources:
                continue

            message = entry.get("message", "")
            timestamp = entry.get("timestamp", "")

            # Truncate long messages
            if len(message) > 500:
                display_msg = message[:500] + "\n... (truncated)"
            else:
                display_msg = message

            st.markdown(f"**[{source}]** `{timestamp}`")
            st.code(display_msg, language="text" if source != "PACT" else "json")
            st.divider()


def render_mock_banner():
    """Render a prominent mock mode banner if active."""
    if st.session_state.get("mock_mode", True):
        st.warning(
            "⚠️ **MOCK MODE ACTIVE** — All CAW calls are simulated. "
            "No real on-chain transactions will be executed.",
            icon="⚠️"
        )


def render_action_buttons():
    """
    Render quick-action buttons below the input for common operations.
    """
    cols = st.columns(4)
    with cols[0]:
        if st.button("🔄 Reset", use_container_width=True, help="Reset workflow"):
            from session_state import SessionStateManager
            ssm = SessionStateManager(st.session_state)
            ssm.reset_workflow()
            st.rerun()
    with cols[1]:
        if st.button("📋 Clear Chat", use_container_width=True, help="Clear chat history"):
            st.session_state["chat_history"] = []
            st.rerun()
    with cols[2]:
        if st.button("🛑 Abort", use_container_width=True, help="Abort current workflow"):
            wf = st.session_state.get("workflow")
            if wf:
                wf.current_step = 99  # FAILED
                wf.status_message = "Aborted by user"
            st.rerun()
    with cols[3]:
        help_expanded = st.button("❓ Help", use_container_width=True)
        if help_expanded:
            st.info(
                "**How to use:**\n\n"
                "1. Type a task description in natural language\n"
                "   e.g., 'Create a swap task: 0.1 ETH → USDT, reward 100 TTK(mock test token)'\n"
               "   💡 TTK 为 MockERC20 测试代币，仅限 Sepolia 测试网使用。\n"
                "2. The AI parses your intent and generates Pact policies\n"
                "3. Pact is submitted to CAW for approval\n"
                "4. Once approved, on-chain transactions execute\n\n"
                "**Mock Mode**: Toggle ON to test without real chain calls.\n"
                "**Reset**: Start a fresh workflow."
            )
