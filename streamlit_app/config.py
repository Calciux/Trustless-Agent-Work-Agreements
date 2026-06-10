"""
config.py — Single source of truth for all constants.
Contract addresses, CAW wallet UUIDs, chain config, function selectors,
and environment-driven settings (SKIP_CAW, API keys).
"""

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Environment / dotenv loading
# ---------------------------------------------------------------------------
try:
    from dotenv import load_dotenv
    _env_path = Path(__file__).resolve().parent.parent / ".env"
    if _env_path.exists():
        load_dotenv(_env_path)
except ImportError:
    pass

# ---------------------------------------------------------------------------
# Deployed contract addresses (Sepolia)
# ---------------------------------------------------------------------------
ESCROW_ADDR    = "0x5C46deBd8A308e69e56955A8eE647Bf75694dc59"
TTK_ADDR       = "0xCcb19a9e5a4e7eb8eD779c45FF7A6641a4f06cb3"
USDT_MOCK_ADDR = "0x8c7D953c2c897E471Bf5A7BE8532AF79258e0BEb"
ETH_MOCK_ADDR  = "0x94022198f8497F98a47d24B754a602AD2A97FE99"
HOOK_ADDR      = "0xc93d06Dc7018f7F83D3D9140bc00C2C2b92Fb457"
SWAP_HOOK_ADDR = "0x3e60B331BC98133B81174D906d7E86a07C7aecA4"

# ---------------------------------------------------------------------------
# CAW wallet UUIDs (single source of truth: caw_types.CawWallet enum)
# ---------------------------------------------------------------------------
# NOTE: Wallet UUIDs are defined in caw_types.CawWallet enum.
# Use CawWallet.CLIENT.value, CawWallet.PROVIDER.value, etc.
# These re-exports are kept for backward compatibility.
from caw_types import CawWallet as _CawWallet
CLIENT_UUID    = _CawWallet.CLIENT.value
PROVIDER_UUID  = _CawWallet.PROVIDER.value
EVALUATOR_UUID = _CawWallet.EVALUATOR.value

# ---------------------------------------------------------------------------
# CAW on-chain addresses (derived from wallets)
# ---------------------------------------------------------------------------
CLIENT_ADDR    = "0x736859c94664dd29a1bdae8fa075e928b60541bc"
PROVIDER_ADDR  = "0xe2b749ce285b86ff058653336191dec2be50f32c"
EVALUATOR_ADDR = "0xf6459a8868dc4d6db511f535f27887e54d2f0d6d"

# ---------------------------------------------------------------------------
# Chain
# ---------------------------------------------------------------------------
CHAIN = "SETH"
CHAIN_ID = 11155111  # Sepolia

# ---------------------------------------------------------------------------
# Function selectors
# Function signatures (Solidity canonical form, used with `cast calldata`)
SIG_APPROVE    = "approve(address,uint256)"
SIG_CREATE_JOB = "createJob(address,address,uint256,string,address)"
SIG_SET_BUDGET = "setBudget(uint256,uint256)"
SIG_FUND       = "fund(uint256,uint256)"
SIG_SUBMIT     = "submit(uint256,bytes32)"
SIG_COMPLETE   = "complete(uint256,bytes32)"
SIG_REJECT     = "reject(uint256,bytes32)"

# Legacy selectors (kept for reference)
SEL_APPROVE    = "0x095ea7b3"
SEL_CREATE_JOB = "0x41528812"
SEL_SET_BUDGET = "0x9675dc17"
SEL_FUND       = "0xa65e2cfd"
SEL_SUBMIT     = "0x2ecea788"
SEL_COMPLETE   = "0xcd56b1b6"
SEL_REJECT     = "0x6be1320b"

# ---------------------------------------------------------------------------
# Token decimals
# ---------------------------------------------------------------------------
TTK_DECIMALS    = 18
USDT_DECIMALS   = 6
ETH_MOCK_DECIMALS = 18

# ---------------------------------------------------------------------------
# Environment-driven settings
# ---------------------------------------------------------------------------
SKIP_CAW = os.getenv("SKIP_CAW", "true").lower() in ("true", "1", "yes")

# LLM configuration
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "deepseek")  # deepseek | openai
LLM_MODEL = os.getenv("LLM_MODEL", "deepseek-chat")
LLM_API_KEY = os.getenv("DEEPSEEK_API_KEY", os.getenv("OPENAI_API_KEY", ""))
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.deepseek.com")
LLM_TEMPERATURE = float(os.getenv("LLM_TEMPERATURE", "0.1"))
LLM_MAX_TOKENS = int(os.getenv("LLM_MAX_TOKENS", "2000"))

# RPC
RPC_URL = os.getenv("RPC_URL", "https://sepolia.gateway.tenderly.co")

# CAW CLI
CAW_PATH = os.path.expanduser(
    os.getenv("CAW_PATH", "~/.cobo-agentic-wallet/bin")
)

# Proxy (WSL2 gateway)
def _detect_proxy():
    try:
        with open("/etc/resolv.conf") as f:
            for line in f:
                if line.startswith("nameserver "):
                    gw = line.split("nameserver ")[1].strip()
                    return {"HTTPS_PROXY": f"http://{gw}:7890"}
    except Exception:
        pass
    return {}

PROXY_ENV = _detect_proxy()

# ---------------------------------------------------------------------------
# Workflow constants
# ---------------------------------------------------------------------------
CLIENT_TOTAL_OPS = 4    # approve_ttk, create_job, set_budget, fund
PROVIDER_TOTAL_OPS = 1  # submit
EVALUATOR_TOTAL_OPS = 1 # complete (or reject)

MAX_RETRIES = 3
CAW_TIMEOUT_SECONDS = 120
APPROVAL_POLL_INTERVAL = 5  # seconds
APPROVAL_MAX_WAIT = 300     # seconds

# ---------------------------------------------------------------------------
# Token address → symbol mapping
# ---------------------------------------------------------------------------
TOKEN_SYMBOLS = {
    TTK_ADDR:       "TTK",
    USDT_MOCK_ADDR: "USDT_mock",
    ETH_MOCK_ADDR:  "ETH_mock",
}
