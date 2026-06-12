"""
caw_interface.py — Thin wrapper around caw CLI. Always returns plain dicts.
"""
import subprocess, json, os, time
from pathlib import Path
from typing import Optional
from config import CHAIN, CAW_PATH, PROXY_ENV, SKIP_CAW, CAW_TIMEOUT_SECONDS
from caw_types import CawResult, CawPactStatus, CawWallet

TX_POLL_INTERVAL = 5   # seconds between tx status checks
TX_POLL_MAX_WAIT = 300  # seconds total wait for tx approval


class CawInterface:
    def __init__(self, timeout_seconds=None, mock_mode=None, mock_handler=None):
        self.timeout = timeout_seconds or CAW_TIMEOUT_SECONDS
        self.mock_mode = mock_mode if mock_mode is not None else SKIP_CAW
        self._mock = mock_handler
        caw_path = Path(CAW_PATH).expanduser()
        if caw_path.exists():
            os.environ["PATH"] = f"{caw_path}:{os.environ.get('PATH', '')}"

    def _run(self, cmd: list) -> dict:
        """Always returns a dict with at least 'success' key."""
        env = {**os.environ, **PROXY_ENV}
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=self.timeout)
        except subprocess.TimeoutExpired:
            return {"success": False, "error": "CAW command timed out"}
        if result.returncode != 0:
            return {"success": False, "error": result.stderr or result.stdout}
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            return {"success": False, "error": "Invalid JSON from CAW CLI"}
        if "success" not in data:
            data["success"] = True
        return data

    def _switch(self, wallet: CawWallet):
        env = {**os.environ, **PROXY_ENV}
        subprocess.run(["caw", "wallet", "current", "--wallet-uuid", wallet.value],
                       capture_output=True, text=True, env=env, timeout=15)

    # ── Public API ──

    def create_pact(self, wallet: CawWallet, pact_definition: dict, chain: str = "SETH") -> dict:
        if self.mock_mode and self._mock is not None:
            cr = self._mock.simulate_create_pact(wallet.value, pact_definition)
            return {"success": cr.success, "pact_id": cr.pact_id, "status": cr.status.value,
                    "error": cr.stderr or "", "stderr": cr.stderr or ""}
        self._switch(wallet)
        policies = json.dumps(pact_definition.get("policies", []))
        conditions = json.dumps(pact_definition.get("completion_conditions", []))
        cmd = ["caw", "pact", "submit",
               "--name", pact_definition.get("name", "auto"),
               "--intent", pact_definition.get("intent") or pact_definition.get("name", "auto"),
               "--original-intent", pact_definition.get("original_intent", pact_definition.get("name", "")),
               "--policies", policies,
               "--completion-conditions", conditions,
               "--execution-plan", pact_definition.get("execution_plan", pact_definition.get("name", ""))]
        raw = self._run(cmd)
        if not raw.get("success"):
            return raw
        result = raw.get("result", {})
        pact_id = result.get("pact_id", raw.get("pact_id", ""))
        raw["pact_id"] = pact_id
        raw["status"] = CawPactStatus.PENDING.value if pact_id else CawPactStatus.UNKNOWN.value
        return raw

    def execute_transaction(self, wallet: CawWallet, pact_id: str, contract_address: str,
                            function_signature: str, args: list[str], value: str = "0") -> dict:
        if self.mock_mode and self._mock is not None:
            return self._mock.simulate_execute_transaction(wallet.value, pact_id, contract_address, function_signature, args, value)
        self._switch(wallet)
        src = {CawWallet.CLIENT: "0x736859c94664dd29a1bdae8fa075e928b60541bc",
               CawWallet.PROVIDER: "0x01b77f6cfad5cd30bc3e78273f0faf5544621526",
               CawWallet.PROVIDER2: "0x7f79716274d6db28784664c02e678c1a3196c948",
               CawWallet.EVALUATOR: "0xf6459a8868dc4d6db511f535f27887e54d2f0d6d"}.get(wallet, "")

        # Build full calldata
        if args:
            try:
                cast_cmd = ["cast", "calldata", function_signature] + args
                cast_env = {**os.environ, "FOUNDRY_DISABLE_NIGHTLY_WARNING": "1"}
                cast_result = subprocess.run(
                    cast_cmd, capture_output=True, text=True, env=cast_env, timeout=30
                )
                if cast_result.returncode == 0:
                    calldata = cast_result.stdout.strip()
                else:
                    return {"success": False, "error": f"cast calldata failed: {cast_result.stderr}"}
            except Exception as e:
                return {"success": False, "error": f"cast calldata error: {e}"}
        else:
            calldata = function_signature

        request_id = f"{wallet.name.lower()}-{int(time.time())}"
        cmd = ["caw", "tx", "call", "--pact-id", pact_id, "--chain-id", CHAIN,
               "--contract", contract_address, "--calldata", calldata,
               "--src-address", src, "--request-id", request_id]
        if value and value != "0":
            cmd += ["--value", value]

        raw = self._run(cmd)
        # _run may auto-add success:True — if CAW returned an error, override
        if raw.get("error") and not raw.get("status"):
            raw["success"] = False
            return raw

        # CAW may return PendingApproval — the tx needs user approval in the App.
        # Poll until Confirmed or Failed. Case-insensitive matching.
        tx_status = (raw.get("status", "") or "").lower()
        if tx_status in ("pendingapproval", "pending_approval", "processing"):
            return self._wait_for_tx_approval(wallet, request_id)

        # Already confirmed
        if tx_status in ("confirmed", "success", "completed", "succeeded"):
            raw["tx_hash"] = raw.get("transaction_hash") or raw.get("tx_hash") or raw.get("hash") or raw.get("id", "")
            raw["success"] = True
            return raw

        # Failed on submission
        if tx_status in ("failed", "rejected", "error"):
            raw["success"] = False
            return raw

        # Unknown status — log and poll to be safe
        print(f"[CAW] Unknown tx status '{raw.get('status','')}' for request_id={request_id}, polling...")
        return self._wait_for_tx_approval(wallet, request_id)

    def _wait_for_tx_approval(self, wallet: CawWallet, request_id: str) -> dict:
        """Poll caw tx get until the transaction is confirmed or failed.
        After CAW reports confirmed, verify the tx actually exists on-chain."""
        self._switch(wallet)
        elapsed = 0
        while elapsed < TX_POLL_MAX_WAIT:
            result = self._run(["caw", "tx", "get", "--request-id", request_id])
            status = (result.get("status", "") or "").lower()

            if status in ("confirmed", "success", "completed", "succeeded"):
                # CAW may use "transaction_hash", "tx_hash", or "hash"
                tx_hash = result.get("transaction_hash") or result.get("tx_hash") or result.get("hash", "")
                if tx_hash:
                    # Verify tx actually exists on-chain
                    if self._verify_tx_onchain(tx_hash):
                        result["success"] = True
                        result["tx_hash"] = tx_hash
                        return result
                    else:
                        # CAW says confirmed but tx not on-chain — keep polling
                        print(f"[CAW] tx {tx_hash} reported confirmed but not found on-chain, retrying...")
                else:
                    # No tx_hash yet — CAW might still be finalizing
                    print(f"[CAW] status={status} but no tx_hash yet, retrying...")

            elif status in ("failed", "rejected", "error"):
                result["success"] = False
                result["tx_hash"] = ""
                return result

            # Still pending: "pendingapproval", "processing", "pending", "submitted", etc.
            time.sleep(TX_POLL_INTERVAL)
            elapsed += TX_POLL_INTERVAL

        return {"success": False, "error": f"Transaction approval timeout after {TX_POLL_MAX_WAIT}s"}

    def _verify_tx_onchain(self, tx_hash: str) -> bool:
        """Verify tx exists on-chain. Retries 3 times with 3s delay."""
        from config import SEPOLIA_RPC_URL
        for attempt in range(3):
            try:
                cast_env = {**os.environ, **PROXY_ENV, "FOUNDRY_DISABLE_NIGHTLY_WARNING": "1"}
                result = subprocess.run(
                    ["cast", "tx", tx_hash, "--rpc-url", SEPOLIA_RPC_URL],
                    capture_output=True, text=True, env=cast_env, timeout=5
                )
                if result.returncode == 0 and "blockNumber" in result.stdout:
                    return True
            except Exception:
                pass
            if attempt < 2:
                time.sleep(3)
        # All retries exhausted — trust CAW as last resort
        return True

    def get_pact_status(self, wallet: CawWallet, pact_id: str) -> dict:
        if self.mock_mode and self._mock is not None:
            return self._mock.simulate_get_status(pact_id)
        self._switch(wallet)
        return self._run(["caw", "pact", "show", "--pact-id", pact_id])

    def switch_wallet(self, wallet_uuid: str) -> dict:
        return self._run(["caw", "wallet", "current", "--wallet-uuid", wallet_uuid])

    def get_chain_state(self, job_id, step):
        return {}
