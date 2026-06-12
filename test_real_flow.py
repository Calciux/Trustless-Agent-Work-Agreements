#!/usr/bin/env python3
"""Use EXACT same Pact as Streamlit to test."""
import sys, os, time, json, subprocess

sys.path.insert(0, '/home/nytch/Trustless-Agent-Work-Agreements/streamlit_app')
os.environ['SKIP_CAW'] = 'false'

from caw_interface import CawInterface
from caw_types import CawWallet

caw = CawInterface()
caw._switch(CawWallet.CLIENT)

# Match Streamlit template EXACTLY: two policies, amount_gt on both
pact = {
    "name": f"test-streamlit-{int(time.time())}",
    "intent": "ERC-8183 bidding workflow: approve TTK, create job with BiddingHook, set provider via signed bid, set budget, fund escrow",
    "original_intent": "swap 0.1 ETH to USDT, reward 100 TTK",
    "execution_plan": "Approve TTK, create open job (provider=0x0, hook=BiddingHook), set provider, set budget, fund escrow",
    "policies": [
        {
            "name": "ttk-approve",
            "type": "contract_call",
            "rules": {
                "effect": "allow",
                "when": {
                    "chain_in": ["SETH"],
                    "target_in": [{"chain_id": "SETH", "contract_addr": "0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3", "function_id": "0x095ea7b3"}]
                },
                "deny_if": {"amount_gt": "200000000000000000000"},
                "always_review": False
            }
        },
        {
            "name": "erc8183-bidding-ops",
            "type": "contract_call",
            "rules": {
                "effect": "allow",
                "when": {
                    "chain_in": ["SETH"],
                    "target_in": [
                        {"chain_id": "SETH", "contract_addr": "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59", "function_id": "0x41528812"},
                        {"chain_id": "SETH", "contract_addr": "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59", "function_id": "0xd0fae591"},
                        {"chain_id": "SETH", "contract_addr": "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59", "function_id": "0xc9a84bb9"},
                        {"chain_id": "SETH", "contract_addr": "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59", "function_id": "0x9675dc17"},
                        {"chain_id": "SETH", "contract_addr": "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59", "function_id": "0xa65e2cfd"},
                        {"chain_id": "SETH", "contract_addr": "0x80aB74aAdf32355A3784F5383e61d59671B0809d", "function_id": "0xdc08fb1d"}
                    ]
                },
                "deny_if": {"amount_gt": "1000000000000000000", "usage_limits": {"rolling_24h": {"tx_count_gt": "6"}}},
                "always_review": False
            }
        }
    ],
    "completion_conditions": [{"type": "tx_count", "threshold": "5"}]
}

print("Creating Pact (Streamlit template)...")
r = caw.create_pact(CawWallet.CLIENT, pact)
pid = r.get("pact_id", "")
print(f"Pact: {pid}")

if not pid:
    print(f"FAIL: {r}")
    sys.exit(1)

print("⚠️  Approve in CAW App...")
for i in range(60):
    time.sleep(3)
    s = caw.get_pact_status(CawWallet.CLIENT, pid)
    st = s.get("status", "") or s.get("result", {}).get("status", "")
    if st in ("active", "approved"):
        print("✓ Pact active!")
        break
    print(f"  [{i+1}] {st}")

# approve_ttk
print("\n--- approve_ttk ---")
r1 = caw.execute_transaction(CawWallet.CLIENT, pid,
    "0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3",
    "approve(address,uint256)",
    ["0x5C46deBd8A308e69e56955A8eE647Bf75694dc59", "100000000000000000000"])
print(f"ok={r1.get('success')} tx={r1.get('tx_hash','')[:20]}...")

if not r1.get('success'):
    print(f"FAIL approve: {r1.get('error','')[:200]}")
    sys.exit(1)

time.sleep(15)

# createJob
print("\n--- createJob ---")
r2 = caw.execute_transaction(CawWallet.CLIENT, pid,
    "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59",
    "createJob(address,address,uint256,string,address)",
    ["0x0000000000000000000000000000000000000000",
     "0xf6459A8868dc4d6dB511F535f27887E54d2f0D6D",
     str(int(time.time()) + 86400 * 7),
     "CAW Bidding Job",
     "0x80aB74aAdf32355A3784F5383e61d59671B0809d"])
print(f"ok={r2.get('success')} tx={r2.get('tx_hash','')[:20]}...")

if r2.get('success'):
    print("\n✅✅✅ BOTH PASSED! Pact reuse confirmed!")
else:
    print(f"\n❌ FAIL: {r2.get('error','')[:300]}")
