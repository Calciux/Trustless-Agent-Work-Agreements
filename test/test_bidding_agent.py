"""Unit tests for bidding_agent.py"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'streamlit_app'))
os.environ['SKIP_CAW'] = 'true'
os.environ['PACT_OPTIMIZED'] = 'true'

from bidding_agent import BiddingAgent
from mock_handler import MockHandler
from llm_client import LLMClient
from caw_types import JobContext

PRIV_A = '0x1111111111111111111111111111111111111111111111111111111111111111'
PRIV_B = '0x2222222222222222222222222222222222222222222222222222222222222222'


def test_sign_bid():
    ba = BiddingAgent()
    bid = ba.sign_bid(42, 80 * 10**18, PRIV_A)
    assert bid['signer'].startswith('0x')
    assert len(bid['signature']) == 132  # 0x + 65 bytes hex (130 chars)
    assert bid['price'] == 80 * 10**18
    # Deterministic
    bid2 = ba.sign_bid(42, 80 * 10**18, PRIV_A)
    assert bid['signature'] == bid2['signature']
    assert bid['signer'] == bid2['signer']
    # Different price = different sig
    bid3 = ba.sign_bid(42, 100 * 10**18, PRIV_A)
    assert bid3['signature'] != bid['signature']
    print("  ✅ test_sign_bid")


def test_select_winner_lowest():
    mh = MockHandler()
    llm = LLMClient(mock_handler=mh)
    ba = BiddingAgent(llm_client=llm)
    bid_a = ba.sign_bid(42, 80 * 10**18, PRIV_A)
    bid_b = ba.sign_bid(42, 100 * 10**18, PRIV_B)
    ctx = JobContext(job_id=42, task_type='bidding')
    ctx.chain_data = {'bidding': {'is_bidding': True}}
    winner = ba.select_winner([bid_a, bid_b], ctx)
    assert winner['winner_price'] == 80 * 10**18
    assert winner['winner_sig'] == bid_a['signature']
    print("  ✅ test_select_winner_lowest")


def test_select_winner_single():
    ba = BiddingAgent()
    bid = ba.sign_bid(42, 50 * 10**18, PRIV_A)
    ctx = JobContext(job_id=42, task_type='bidding')
    ctx.chain_data = {'bidding': {'is_bidding': True}}
    winner = ba.select_winner([bid], ctx)
    assert winner['winner_addr'] == bid['signer']
    print("  ✅ test_select_winner_single")


def test_select_winner_empty():
    ba = BiddingAgent()
    ctx = JobContext(job_id=42)
    ctx.chain_data = {}
    try:
        ba.select_winner([], ctx)
        assert False, "Should raise ValueError"
    except ValueError:
        pass
    print("  ✅ test_select_winner_empty")


def test_build_set_provider_args():
    from eth_abi import decode
    ba = BiddingAgent()
    sig = '0x' + 'ab' * 65
    price = 80 * 10**18
    addr = '0x19E7E376E7C213B7E7e827B46aA4Dc6f5D8E7a5C'
    args = ba.build_set_provider_args(42, addr, sig, price)
    assert len(args) == 3
    assert args[0] == '42'
    assert args[1] == addr
    # Decode optParams
    opt_hex = args[2]
    opt_bytes = bytes.fromhex(opt_hex[2:])
    decoded = decode(['bytes', 'uint256'], opt_bytes)
    assert decoded[1] == price
    print("  ✅ test_build_set_provider_args")


if __name__ == '__main__':
    test_sign_bid()
    test_select_winner_lowest()
    test_select_winner_single()
    test_select_winner_empty()
    test_build_set_provider_args()
    print("\n✅ ALL 5 UNIT TESTS PASSED")
