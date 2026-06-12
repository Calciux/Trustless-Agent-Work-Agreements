"""
bidding_agent.py — Bidding Agent for A2A signed-bid workflow.
Supports both local EIP-712 signing (mock mode) and CAW sign-message (real chain).
"""
import json
import subprocess
import os
from typing import Optional
from pathlib import Path

from config import BIDDING_HOOK_ADDR, PROXY_ENV, CAW_PATH


class BiddingAgent:
    """
    竞价 Agent — 非 ACP 角色(不继承 AgentBase)，是流程辅助类。

    职责:
      - sign_bid(job_id, price, private_key): 本地 EIP-712 签名（Mock 模式）
      - sign_bid_caw(job_id, price, pact_id): CAW sign-message 签名（真链模式）
      - select_winner(bids, llm): 让 LLM 选最低报价
      - build_set_provider_args(job_id, winner_addr, sig, price): 组装 setProvider 参数
    """

    def __init__(self, llm_client=None):
        self.llm = llm_client
        caw_path = Path(CAW_PATH).expanduser()
        if caw_path.exists():
            os.environ["PATH"] = f"{caw_path}:{os.environ.get('PATH', '')}"

    # ------------------------------------------------------------------
    # 本地 EIP-712 签名（Mock 模式）
    # ------------------------------------------------------------------

    def sign_bid(self, job_id: int, price: int, private_key: str) -> dict:
        """
        使用本地私钥生成 EIP-712 签名。

        EIP-712 结构:
          domain: {name:"BiddingHook", version:"1", chainId, verifyingContract}
          Bid: {jobId, price}
        """
        from eth_account import Account
        from eth_utils import keccak

        # Build domain separator
        DOMAIN_TYPEHASH = keccak(
            b"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        )
        BID_TYPEHASH = keccak(b"Bid(uint256 jobId,uint256 price)")
        NAME_HASH = keccak(b"BiddingHook")
        VERSION_HASH = keccak(b"1")

        domain_separator = keccak(
            DOMAIN_TYPEHASH +
            NAME_HASH +
            VERSION_HASH +
            int(11155111).to_bytes(32, 'big') +
            bytes.fromhex(BIDDING_HOOK_ADDR[2:].rjust(64, '0'))
        )

        # Build struct hash
        struct_hash = keccak(
            BID_TYPEHASH +
            int(job_id).to_bytes(32, 'big') +
            int(price).to_bytes(32, 'big')
        )

        # EIP-712 digest
        digest = keccak(b'\x19\x01' + domain_separator + struct_hash)

        # Sign using eth_account
        from eth_account.messages import encode_defunct
        signable = encode_defunct(primitive=digest)
        signed = Account.sign_message(signable, private_key)

        return {
            "signer": Account.from_key(private_key).address,
            "signature": "0x" + signed.signature.hex(),
            "price": price,
        }

    # ------------------------------------------------------------------
    # CAW sign-message 签名（真链模式）
    # ------------------------------------------------------------------

    def sign_bid_caw(self, job_id: int, price: int, pact_id: str,
                     chain_id: str = "SETH", src_address: str = "") -> dict:
        """
        使用 CAW CLI sign-message 生成 EIP-712 签名。

        前置条件：Provider 钱包已有 active 的 message_sign Pact。

        Args:
            job_id: 任务 ID
            price: 报价金额 (wei)
            pact_id: 签名 Pact UUID
            chain_id: 链 ID

        Returns:
            {"signer": "0x...", "signature": "0x...", "price": price}
        """
        eip712_data = {
            "types": {
                "EIP712Domain": [
                    {"name": "name", "type": "string"},
                    {"name": "version", "type": "string"},
                    {"name": "chainId", "type": "uint256"},
                    {"name": "verifyingContract", "type": "address"}
                ],
                "Bid": [
                    {"name": "jobId", "type": "uint256"},
                    {"name": "price", "type": "uint256"}
                ]
            },
            "domain": {
                "name": "BiddingHook",
                "version": "1",
                "chainId": 11155111,
                "verifyingContract": BIDDING_HOOK_ADDR
            },
            "primaryType": "Bid",
            "message": {
                "jobId": str(job_id),
                "price": str(price)
            }
        }

        import time as _time
        request_id = f"bid-{job_id}-{pact_id[:8]}-{int(_time.time())}"
        env = {**os.environ, **PROXY_ENV}

        cmd = [
            "caw", "tx", "sign-message",
            "--pact-id", pact_id,
            "--chain-id", chain_id,
            "--destination-type", "eip712",
            "--eip712-typed-data", json.dumps(eip712_data),
            "--request-id", request_id
        ]
        if src_address:
            cmd.extend(["--src-address", src_address])

        result = subprocess.run(cmd, capture_output=True, text=True,
                                env=env, timeout=60)

        if result.returncode != 0:
            raise RuntimeError(f"CAW sign-message failed: {result.stderr}")

        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            raise RuntimeError(f"Invalid JSON from CAW: {result.stdout[:200]}")

        sig_result = data.get("result", data)
        status = sig_result.get("status", "")

        # CAW sign-message is async — poll until completed
        if status == "Processing":
            import time as _time
            for _ in range(30):  # 30 * 2 = 60 seconds max
                _time.sleep(2)
                # Switch wallet for each poll (caw tx get uses active wallet)
                poll_env = {**os.environ, **PROXY_ENV}
                poll_cmd = ["caw", "tx", "get", "--request-id", request_id]
                poll_proc = subprocess.run(
                    poll_cmd,
                    capture_output=True, text=True, env=poll_env, timeout=30
                )
                if poll_proc.returncode == 0:
                    try:
                        poll_data = json.loads(poll_proc.stdout)
                        poll_result = poll_data.get("result", poll_data)
                        poll_status = poll_result.get("status", "")
                        if poll_status == "Success":
                            sig_result = poll_result
                            break
                        elif poll_status in ("Failed", "Rejected", "Cancelled"):
                            raise RuntimeError(f"CAW sign-message {poll_status}: {poll_result}")
                    except json.JSONDecodeError:
                        pass
            else:
                raise RuntimeError(f"CAW sign-message timed out: request_id={request_id}")

        # Signature is nested in data.signature, signer is src_address
        data_field = sig_result.get("data", {})
        signature = data_field.get("signature", sig_result.get("signature", ""))
        signer = sig_result.get("src_address", sig_result.get("signer", sig_result.get("address", "")))

        if not signature:
            raise RuntimeError(f"No signature in CAW response: {data}")

        return {
            "signer": signer,
            "signature": signature,
            "price": price,
        }

    # ------------------------------------------------------------------
    # LLM 选最低价
    # ------------------------------------------------------------------

    def select_winner(self, bids: list[dict], context=None) -> dict:
        """
        让 LLM 比较多个报价，返回最低价 Provider。

        Returns:
            {"winner_addr", "winner_sig", "winner_price", "name", "price_ttk", "reasoning"}
        """
        if len(bids) == 0:
            raise ValueError("No bids to select from")

        if len(bids) == 1:
            bid = bids[0]
            price_ttk = str(bid["price"] // 10**18)
            return {
                "winner_addr": bid["signer"],
                "winner_sig": bid["signature"],
                "winner_price": bid["price"],
                "name": "Provider A",
                "price_ttk": price_ttk,
                "reasoning": "Only one bid received.",
            }

        if self.llm is not None:
            try:
                return self._llm_select_winner(bids, context)
            except Exception:
                pass

        return self._programmatic_select_winner(bids)

    def _llm_select_winner(self, bids: list[dict], context=None) -> dict:
        from config import PROVIDER_ADDR, PROVIDER2_ADDR

        bid_comparisons = []
        for i, bid in enumerate(bids):
            signer = bid["signer"]
            price_ttk = bid["price"] // 10**18
            label = (
                "Provider A" if signer.lower() == PROVIDER_ADDR.lower()
                else "Provider B" if signer.lower() == PROVIDER2_ADDR.lower()
                else f"Provider {i+1}"
            )
            bid_comparisons.append(f"{label}: {price_ttk} TTK")

        prompt = (
            f"Select the lowest price bid. Bids:\n" +
            "\n".join(bid_comparisons) +
            "\n\nOutput JSON: {\"winner\": \"Provider A|Provider B\", \"reasoning\": \"...\"}"
        )

        response = self.llm.chat(
            "You are a bidding evaluator. Select the lowest price bid.",
            prompt
        )

        if response.parsed_json:
            selected = response.parsed_json.get("winner", "Provider A")
            reasoning = response.parsed_json.get("reasoning", "LLM selected lowest price")
        else:
            selected = "Provider A"
            reasoning = "LLM selected lowest price"

        for bid in bids:
            signer = bid["signer"]
            if selected == "Provider A" and signer.lower() == PROVIDER_ADDR.lower():
                return self._make_winner_result(bid, "Provider A", reasoning)
            elif selected == "Provider B" and signer.lower() == PROVIDER2_ADDR.lower():
                return self._make_winner_result(bid, "Provider B", reasoning)

        return self._programmatic_select_winner(bids)

    def _programmatic_select_winner(self, bids: list[dict]) -> dict:
        from config import PROVIDER_ADDR, PROVIDER2_ADDR

        sorted_bids = sorted(bids, key=lambda b: b["price"])
        winner = sorted_bids[0]
        price_ttk = str(winner["price"] // 10**18)
        signer = winner["signer"]

        if signer.lower() == PROVIDER_ADDR.lower():
            name = "Provider A"
        elif signer.lower() == PROVIDER2_ADDR.lower():
            name = "Provider B"
        else:
            name = f"Provider ({signer[:10]}...)"

        return self._make_winner_result(winner, name,
            f"Programmatic selection: {name} has lowest price at {price_ttk} TTK")

    def _make_winner_result(self, bid: dict, name: str, reasoning: str) -> dict:
        return {
            "winner_addr": bid["signer"],
            "winner_sig": bid["signature"],
            "winner_price": bid["price"],
            "name": name,
            "price_ttk": str(bid["price"] // 10**18),
            "reasoning": reasoning,
        }

    # ------------------------------------------------------------------
    # setProvider 参数组装
    # ------------------------------------------------------------------

    @staticmethod
    def build_set_provider_args(
        job_id: int,
        winner_addr: str,
        sig_hex: str,
        price: int,
    ) -> list:
        """
        组装 setProvider(jobId, winnerAddr, optParams) 参数。

        optParams = abi.encode(signature_bytes, price_uint256)
        """
        from eth_abi import encode

        sig_bytes = bytes.fromhex(sig_hex[2:] if sig_hex.startswith("0x") else sig_hex)
        opt_params_bytes = encode(['bytes', 'uint256'], [sig_bytes, price])
        opt_params_hex = "0x" + opt_params_bytes.hex()

        return [str(job_id), winner_addr, opt_params_hex]
