"""
app.py — Thread-safe: queue for thread→main communication, st.session_state only in main.
"""
import streamlit as st
import sys, os, threading, time, queue
from pathlib import Path
_THIS_DIR = Path(__file__).resolve().parent
if str(_THIS_DIR) not in sys.path:
    sys.path.insert(0, str(_THIS_DIR))

st.set_page_config(page_title="Trustless Agent", page_icon="🏦", layout="wide")

from config import SKIP_CAW, PACT_OPTIMIZED
from caw_types import WorkflowStep
from session_state import SessionStateManager
from mock_handler import MockHandler
from llm_client import LLMClient
from pact_generator import PactGenerator
from caw_interface import CawInterface
from error_handler import ErrorHandler
from client_agent import ClientAgent
from provider_agent import ProviderAgent
from evaluator_agent import EvaluatorAgent
from orchestrator import AgentOrchestrator
from ui_components import (render_header, render_chat_panel, render_input_box,
    render_progress_steps, render_role_status_cards, render_tx_history,
    render_log_expander, render_mock_banner, render_action_buttons)

st.markdown("""<style>.block-container{padding-top:1rem}</style>""", unsafe_allow_html=True)

# ── Thread-safe state: queue lives in session to survive reruns ──
if "t_queue" not in st.session_state:
    st.session_state["t_queue"] = queue.Queue()
_q = st.session_state["t_queue"]

def init_session():
    ssm = SessionStateManager(st.session_state)
    if st.session_state.get("workflow") is None: ssm.reset_workflow()
    if "mock_mode_initialized" not in st.session_state:
        st.session_state["mock_mode"] = SKIP_CAW
        st.session_state["mock_mode_initialized"] = True
    if "t_running" not in st.session_state: st.session_state["t_running"] = False
    if "t_done" not in st.session_state: st.session_state["t_done"] = False
    if "t_step" not in st.session_state: st.session_state["t_step"] = ""
    if "t_error" not in st.session_state: st.session_state["t_error"] = ""
    if "t_timeline" not in st.session_state: st.session_state["t_timeline"] = []
    return ssm

def make_orch(ssm):
    mock_h = MockHandler(approval_delay=1.0)
    llm = LLMClient(mock_handler=mock_h)
    pg = PactGenerator()
    caw = CawInterface(mock_handler=mock_h)
    err = ErrorHandler()
    orch = AgentOrchestrator(ClientAgent(llm=llm,caw=caw,pact_gen=pg),
        ProviderAgent(llm=llm,caw=caw,pact_gen=pg),
        EvaluatorAgent(llm=llm,caw=caw,pact_gen=pg),llm,caw,pg,ssm)
    orch.error_handler=err
    return orch

# ── Human-readable helpers ──

_CONTRACT_NAMES = {
    "0xccb19a9e5a4e7eb8ed779c45ff7a6641a4f06cb3": "TTK 代币合约",
    "0x5c46debd8a308e69e56955a8ee647bf75694dc59": "ERC-8183 托管合约",
    "0x8c7d953c2c897e471bf5a7be8532af79258e0beb": "USDT 测试币",
    "0x94022198f8497f98a47d24b754a602ad2a97fe99": "ETH 测试币",
}

_FUNC_NAMES = {
    "0x095ea7b3": "approve(授权代币)",
    "0x41528812": "createJob(创建任务)",
    "0x9675dc17": "setBudget(设置预算)",
    "0xa65e2cfd": "fund(锁定资金)",
    "0x2ecea788": "submit(提交成果)",
    "0xcd56b1b6": "complete(放款)",
    "0x6be1320b": "reject(退款)",
}

_STEP_HUMAN = {
    "approve_ttk": (
        "授权托管合约使用您的代币",
        "这步操作是告诉 TTK 代币合约：「我允许 ERC-8183 托管合约从我的钱包里转走 TTK」。"
        "。这一步完成后，托管合约才有权动用你的代币作为任务报酬。"
    ),
    "create_job": (
        "在链上创建托管任务",
        "在 ERC-8183 合约上正式登记一个任务：指定谁来做（服务商）、谁来验收（裁决者）、任务什么时候到期。"
    ),
    "set_budget": (
        "设置任务赏金预算",
        "为刚创建的任务设定报酬金额。「这个任务完成后，服务商能拿到 100 TTK」。"
    ),
    "fund": (
        "将赏金锁定到托管合约",
        "把 TTK 代币真正转入托管合约锁定起来。此时代币还在链上合约里，服务商还不能拿走——"
        "只有等你验收通过后，合约才会自动把钱转给服务商。如果服务商没按时交付，钱会退给你。"
    ),
    "submit": (
        "服务商提交工作成果",
        "服务商（Provider）完成工作后，在链上提交一个工作证明哈希。"
        "此时资金仍然锁定在托管合约中，要等裁决者验收通过才会放款。"
    ),
    "complete": (
        "裁决者验收通过，放款给服务商",
        "裁决者（Evaluator，由 LLM 自动评判）确认工作合格，批准将托管合约中的赏金转给服务商。"
    ),
    "reject": (
        "裁决者验收不通过，退款给客户",
        "裁决者（Evaluator）判定工作不合格或超时，将托管合约中的赏金退回给客户。"
    ),
}

def _cname(addr):
    return _CONTRACT_NAMES.get(addr.lower(), f"合约 {addr[:10]}...")

def _build_timeline_entry(kind, step_name, contract_addr, func_sig, args, pact_name=None, pact_json=None, is_reused=False):
    """Build a single timeline entry with human + technical layers.
    
    In optimized mode, pact entries show always_review status and all function whitelists.
    Reused Pacts are marked with a ♻️ indicator.
    """
    human_title, human_desc = _STEP_HUMAN.get(step_name, (step_name, ""))
    cname = _cname(contract_addr)

    # Build rich Pact detail text
    pact_detail = ""
    if pact_json:
        policies = pact_json.get("policies", [])
        for pi, pol in enumerate(policies):
            rules = pol.get("rules", {})
            ar = rules.get("always_review", None)
            deny_if = rules.get("deny_if", {})
            targets = rules.get("when", {}).get("target_in", [])
            
            ar_label = "🔴 需审批" if ar else ("🟢 自动放行" if ar is False else "❓")
            pact_detail += f"\n**策略 {pi+1}: {pol.get('name', '?')}** ({ar_label})"
            
            for ti, t in enumerate(targets):
                fid = t.get("function_id", "")
                caddr = t.get("contract_addr", "")[:10]
                fname = _FUNC_NAMES.get(fid, fid[:10] if fid else "(all)")
                pact_detail += f"\n  └─ {cname if ti==0 else cname}: `{fname}`"
            
            if deny_if:
                limits = []
                if "amount_gt" in deny_if:
                    limits.append(f"金额>{deny_if['amount_gt']} wei")
                usage = deny_if.get("usage_limits", {}).get("rolling_24h", {})
                if "tx_count_gt" in usage:
                    limits.append(f"24h内>{usage['tx_count_gt']}笔")
                if limits:
                    pact_detail += f"\n  └─ 拒绝条件: {', '.join(limits)}"
    
    # Human layer
    if kind == "pact":
        if is_reused:
            human = f"♻️ **复用已有策略：{human_title}**\n\n{human_desc}\n\n✅ 策略已批准，直接执行"
        else:
            mode_hint = ""
            if PACT_OPTIMIZED and pact_json:
                all_auto = all(p.get("rules", {}).get("always_review") is False for p in pact_json.get("policies", []))
                mode_hint = "\n\n🟢 **策略内交易将自动执行** (无需逐笔审批)" if all_auto else ""
            human = f"📜 **策略规则已生成：{human_title}**\n\n{human_desc}{mode_hint}\n\n📱 请在 CAW App 中批准此策略"
    else:
        human = f"⛓️ **链上执行：{human_title}**\n\n{human_desc}\n\n📱 请在 CAW App 中批准此合约调用"

    # Technical layer (collapsed by default)
    args_str = ", ".join(str(a) for a in args)
    technical = (
        f"**合约地址**: `{contract_addr}` ({cname})\n"
        f"**函数签名**: `{func_sig}`\n"
        f"**参数**: `({args_str})`\n"
        f"**Pact 名称**: `{pact_name or '—'}`"
    )
    if pact_detail:
        technical += f"\n\n---\n**策略详情**:{pact_detail}"

    return {"kind": kind, "human": human, "technical": technical}


def _run_workflow(orch, text, ssm):
    """Thread body: puts progress events into queue."""
    try:
        _q.put({"type":"step","val":"🧠 LLM 正在理解您的需求..."})
        intent = orch._parse_intent(text)
        _q.put({"type":"step","val":f"✅ 已理解：{intent.action}，角色={intent.role}"})

        context = orch._build_context(intent)
        role = intent.role.value if hasattr(intent.role,'value') else intent.role
        action = intent.action

        if role == "client" and action in ("create_job","create_task"):
            timeline = []  # single chronological timeline

            def on_pact(step_name_from_exec, pj):
                policies = pj.get("policies",[])
                if not policies: return
                p = policies[0] if isinstance(policies,list) else policies
                pname = p.get("name", step_name_from_exec)
                rules = p.get("rules",{})
                when = rules.get("when",{})
                targets = when.get("target_in",[])
                contract = targets[0].get("contract_addr","") if targets else ""
                fid = targets[0].get("function_id","") if targets else ""

                step = step_name_from_exec
                role = orch.client.get_role().value
                # In optimized mode, check if Pact is being reused
                is_reused = PACT_OPTIMIZED and role in context.role_pact_id
                entry = _build_timeline_entry("pact", step, contract, fid, [], pname,
                                              pact_json=pj, is_reused=is_reused)
                timeline.append(entry)
                _q.put({"type":"timeline","val":list(timeline)})
                # Push a clear instruction for the user
                role_hint = {"approve_ttk":"Client","create_job":"Client","set_budget":"Client","fund":"Client",
                             "submit":"Provider","complete":"Evaluator","reject":"Evaluator"}.get(step, "")
                if is_reused:
                    _q.put({"type":"step","val":f"♻️ {step}: 复用已有策略，直接执行"})
                else:
                    _q.put({"type":"step","val":f"📱 请在 {role_hint} 钱包的 CAW App 中批准策略「{pname}」"})

            def on_tx(step, contract, func_sig, args):
                entry = _build_timeline_entry("tx", step, contract, func_sig, args)
                timeline.append(entry)
                _q.put({"type":"timeline","val":list(timeline)})

            for step in ["approve_ttk", "create_job", "set_budget", "fund"]:
                _q.put({"type":"step","val":f"🔄 {step}: 正在生成安全策略..."})
                context = orch.client.execute_step(context, step, on_pact_generated=on_pact, on_tx_submitting=on_tx)
                if context.current_step == WorkflowStep.FAILED:
                    err_msg = context.error_message or f"{step} 失败"
                    # Build a clear stop reason for the user
                    step_names_cn = {
                        "approve_ttk": "授权代币", "create_job": "创建任务",
                        "set_budget": "设置预算", "fund": "锁定资金"
                    }
                    cn = step_names_cn.get(step, step)
                    _q.put({"type":"error","val":f"❌ 流程在「{cn}」步骤停止\n\n{err_msg}\n\n💡 可能原因：链上条件不满足、CAW 策略拒绝、或 gas 不足。请检查 CAW App 中的错误详情。"})
                    _q.put({"type":"done","val":None})
                    return
                _q.put({"type":"step","val":f"📱 {step} 已提交 — 请在 CAW App 中批准"})

            ssm.update_workflow(client_progress=100.0)
            _q.put({"type":"step","val":"✅ 客户流程完成！"})

            # ── Provider: submit delivery ──
            _q.put({"type":"step","val":"🤖 切换到 Provider（服务商）角色..."})
            _q.put({"type":"step","val":"📱 请切换到 Provider 钱包的 CAW App 进行批准"})

            context = orch.provider.execute_step(context, "submit", on_pact_generated=on_pact, on_tx_submitting=on_tx)
            if context.current_step == WorkflowStep.FAILED:
                _q.put({"type":"error","val":f"❌ 流程在「服务商提交」步骤停止\n\n{context.error_message or 'submit 失败'}\n\n💡 请检查 CAW App 中 Provider 钱包的错误详情。"})
                _q.put({"type":"done","val":None})
                return
            ssm.update_workflow(provider_progress=100.0)
            _q.put({"type":"step","val":"✅ 服务商已提交工作成果！"})

            # ── Evaluator: LLM judge → complete or reject ──
            _q.put({"type":"step","val":"🔍 切换到 Evaluator（裁决者）角色..."})
            _q.put({"type":"step","val":"🧠 LLM 正在评判工作成果..."})

            judgment = orch.evaluator.evaluate_job(context)
            eval_action = judgment.get("action", "complete")
            reasoning = judgment.get("reasoning", "")
            _q.put({"type":"step","val":f"📋 裁决结果：{'✅ 验收通过，放款给服务商' if eval_action == 'complete' else '❌ 验收不通过，退款给客户'}"})
            if reasoning:
                _q.put({"type":"step","val":f"💬 理由：{reasoning[:200]}"})

            _q.put({"type":"step","val":"📱 请切换到 Evaluator 钱包的 CAW App 进行批准"})
            context = orch.evaluator.execute_step(context, eval_action, on_pact_generated=on_pact, on_tx_submitting=on_tx)
            if context.current_step == WorkflowStep.FAILED:
                _q.put({"type":"error","val":f"❌ 流程在「裁决者{eval_action}」步骤停止\n\n{context.error_message or 'evaluator 失败'}"})
                _q.put({"type":"done","val":None})
                return
            ssm.update_workflow(evaluator_progress=100.0)
            _q.put({"type":"step","val":"✅ 裁决完成！全流程结束。"})
        else:
            _q.put({"type":"error","val":f"不支持: {role}/{action}"})
        _q.put({"type":"done","val":None})
    except Exception as e:
        _q.put({"type":"error","val":str(e)})
        _q.put({"type":"done","val":None})


def main():
    ssm = init_session()
    orch = make_orch(ssm)
    render_header()

    left, right = st.columns([0.7,0.3])
    with left:
        chat = ssm.get_chat_history()
        if not chat:
            with st.chat_message("assistant"):
                st.markdown('👋 试试：\"帮我发布一个 swap 任务，0.1 ETH 换成 USDT，报酬 100 TTK\"')
        else:
            render_chat_panel(chat)

        # ── Drain queue and update st.session_state ──
        updated = False
        while not _q.empty():
            try:
                evt = _q.get_nowait()
                t = evt["type"]
                if t == "step": st.session_state["t_step"] = evt["val"]
                elif t == "timeline": st.session_state["t_timeline"] = list(evt["val"])
                elif t == "error": st.session_state["t_error"] = evt["val"]
                elif t == "done": st.session_state["t_done"] = True
                updated = True
            except queue.Empty:
                break

        # ── Display progress ──
        running = st.session_state.get("t_running", False)
        done = st.session_state.get("t_done", False)
        step = st.session_state.get("t_step", "")
        error = st.session_state.get("t_error", "")
        timeline = st.session_state.get("t_timeline", [])

        if running and not done:
            st.info(f"⏳ {step}")
            for i, entry in enumerate(timeline):
                if entry["kind"] == "pact":
                    with st.expander(entry["human"], expanded=(i == len(timeline) - 1)):
                        st.caption("🔧 技术参数 (Technical Details)")
                        st.code(entry["technical"], language=None)
                else:
                    with st.expander(entry["human"], expanded=(i == len(timeline) - 1)):
                        st.caption("🔧 技术参数 (Technical Details)")
                        st.code(entry["technical"], language=None)
            if error:
                st.error(error)
            time.sleep(1)
            st.rerun()
        elif done and running:
            if error:
                st.error(f"❌ {error}")
                ssm.add_chat_message("assistant", f"❌ {error}")
            else:
                st.success("✅ 所有流程完成！可在 CAW App 中查看详情。")
            st.session_state["t_running"] = False
            st.session_state["t_done"] = False
            st.session_state["t_step"] = ""
            # Keep timeline and error visible so user can review what happened
            st.rerun()
        elif timeline and not running and not done:
            # Show completed timeline (workflow finished, user can review)
            if error:
                st.error(f"❌ {error}")
            for i, entry in enumerate(timeline):
                with st.expander(entry["human"], expanded=False):
                    st.caption("🔧 技术参数 (Technical Details)")
                    st.code(entry["technical"], language=None)

        user_input = render_input_box()
        render_action_buttons()
        wf = ssm.get_workflow()
        render_log_expander(wf.log_entries if wf else [])

    with right:
        summary = orch.get_workflow_summary()
        render_progress_steps(summary.get("current_step",0))
        render_role_status_cards(0,0,0)
        render_tx_history(summary.get("tx_history",[]))

    # ── Handle new input ──
    if user_input and user_input.strip() and not st.session_state.get("t_running"):
        m = user_input.strip().lower()
        if m in ("reset","/reset"): orch.reset(); st.rerun()
        elif m in ("clear","/clear"): st.session_state["chat_history"]=[]; st.rerun()
        else:
            ssm.add_chat_message("user", user_input)
            ssm.add_chat_message("assistant", "⏳ Processing...")
            st.session_state["t_running"] = True
            st.session_state["t_done"] = False
            st.session_state["t_step"] = "Starting..."
            st.session_state["t_error"] = ""
            st.session_state["t_timeline"] = []
            # Clear queue
            while not _q.empty():
                try: _q.get_nowait()
                except queue.Empty: break
            thr = threading.Thread(target=_run_workflow, args=(orch, user_input, ssm), daemon=True)
            thr.start()
            time.sleep(0.5)
            st.rerun()

if __name__ == "__main__":
    main()
