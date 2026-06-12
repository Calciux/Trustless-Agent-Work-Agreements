#!/usr/bin/env python3
"""Run the full A2A bidding flow 5 times and report results."""
import sys, os, time, json, subprocess

sys.path.insert(0, '/home/nytch/Trustless-Agent-Work-Agreements/streamlit_app')
os.chdir('/home/nytch/Trustless-Agent-Work-Agreements/streamlit_app')

from config import SKIP_CAW, PACT_OPTIMIZED
from caw_types import JobContext, WorkflowStep, CawWallet
from mock_handler import MockHandler
from llm_client import LLMClient
from pact_generator import PactGenerator
from caw_interface import CawInterface
from error_handler import ErrorHandler
from client_agent import ClientAgent
from provider_agent import ProviderAgent
from evaluator_agent import EvaluatorAgent
from orchestrator import AgentOrchestrator
from bidding_agent import BiddingAgent

def run_single_test(run_id, is_bidding=True):
    print(f"\n{'='*60}")
    print(f"RUN {run_id}: Starting full flow")
    print(f"{'='*60}")
    
    mock = MockHandler(approval_delay=0)
    llm = LLMClient(mock_handler=mock)
    pg = PactGenerator()
    caw = CawInterface(mock_handler=mock)
    err = ErrorHandler()
    bidding = BiddingAgent(llm_client=llm)
    
    orch = AgentOrchestrator(
        ClientAgent(llm=llm, caw=caw, pact_gen=pg),
        ProviderAgent(llm=llm, caw=caw, pact_gen=pg),
        EvaluatorAgent(llm=llm, caw=caw, pact_gen=pg),
        llm, caw, pg, None,
        bidding_agent=bidding
    )
    orch.error_handler = err
    
    # Parse intent
    print(f"  Parsing intent...")
    intent = orch._parse_intent("帮我发布一个 swap 任务，0.1 ETH 换成 USDT，报酬 100 TTK")
    print(f"  Intent: role={intent.role}, action={intent.action}, task_type={intent.task_type}")
    
    # Build context
    context = orch._build_context(intent)
    context.chain_data["bidding"] = {"is_bidding": is_bidding}
    
    # === Client steps ===
    client_steps = ["approve_ttk", "create_job"]
    if not is_bidding:
        client_steps += ["set_budget", "fund"]
    
    for step in client_steps:
        print(f"  Step: {step}...")
        try:
            context = orch.client.execute_step(context, step)
            if context.current_step == WorkflowStep.FAILED:
                print(f"    ❌ FAILED: {context.error_message}")
                return False
            tx = context.transactions.get(step, "")
            print(f"    ✅ tx={tx[:16] if tx else 'mock'}...")
        except Exception as e:
            print(f"    ❌ Exception: {e}")
            return False
    
    # === Bidding phase ===
    if is_bidding:
        job_id = context.job_id or 1
        
        # Sign bids
        print(f"  Bidding: signing for job {job_id}")
        try:
            bid_a = bidding.sign_bid(job_id, 80 * 10**18)
            print(f"    Provider A: signed by {bid_a['signer'][:12]}...")
            bid_b = bidding.sign_bid(job_id, 100 * 10**18)
            print(f"    Provider B: signed by {bid_b['signer'][:12]}...")
            
            # Select winner
            winner = bidding.select_winner([bid_a, bid_b], context)
            print(f"    Winner: {winner['winner_addr'][:12]}... @ {winner['price_ttk']} TTK")
            
            # Build optParams
            opt = bidding.build_set_provider_args(job_id, winner['winner_addr'], winner['winner_sig'], winner['winner_price'])
            
            # setProvider
            context = orch.client.execute_step(context, "set_provider", override_args=opt)
            if context.current_step == WorkflowStep.FAILED:
                print(f"    ❌ setProvider FAILED: {context.error_message}")
                return False
            print(f"    ✅ setProvider done")
            
            # setBudget + fund
            for step in ["set_budget", "fund"]:
                context = orch.client.execute_step(context, step)
                if context.current_step == WorkflowStep.FAILED:
                    print(f"    ❌ {step} FAILED: {context.error_message}")
                    return False
                print(f"    ✅ {step} done")
        except Exception as e:
            print(f"    ❌ Bidding exception: {e}")
            return False
    
    # === Provider submit ===
    print(f"  Provider submit...")
    try:
        context = orch.provider.execute_step(context, "submit")
        if context.current_step == WorkflowStep.FAILED:
            print(f"    ❌ submit FAILED")
            return False
        print(f"    ✅ submit done")
    except Exception as e:
        print(f"    ❌ submit exception: {e}")
        return False
    
    # === Evaluator ===
    print(f"  Evaluator judging...")
    try:
        judgment = orch.evaluator.evaluate_job(context)
        action = judgment.get("action", "complete")
        reasoning = judgment.get("reasoning", "")
        print(f"    Judgment: {action} — {reasoning[:80]}")
        
        context = orch.evaluator.execute_step(context, action)
        if context.current_step == WorkflowStep.FAILED:
            print(f"    ❌ evaluator {action} FAILED")
            return False
        print(f"    ✅ evaluator {action} done")
    except Exception as e:
        print(f"    ❌ evaluator exception: {e}")
        return False
    
    print(f"  ✅ RUN {run_id} COMPLETED SUCCESSFULLY")
    return True

if __name__ == "__main__":
    results = []
    for i in range(1, 6):
        ok = run_single_test(i, is_bidding=True)
        results.append(ok)
        if not ok:
            print(f"\n⚠️  Stopping after failure in run {i}")
            break
    
    passed = sum(results)
    print(f"\n{'='*60}")
    print(f"RESULTS: {passed}/{len(results)} passed")
    print(f"{'='*60}")
    
    sys.exit(0 if passed == len(results) else 1)
