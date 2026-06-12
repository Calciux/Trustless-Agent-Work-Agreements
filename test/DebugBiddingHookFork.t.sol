// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../contracts/ERC8183Escrow.sol";
import "../contracts/hooks/BiddingHook.sol";

contract DebugBiddingHookFork is Test {
    ERC8183Escrow escrow = ERC8183Escrow(0x5C46deBd8A308e69e56955A8eE647Bf75694dc59);
    BiddingHook hook; // Will deploy new

    address client = 0x736859c94664Dd29A1bdae8FA075e928b60541Bc;
    address provider = 0x01b77F6cFad5cd30BC3E78273F0Faf5544621526;

    bytes4 constant SEL_EXT = 0xc9a84bb9;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        hook = new BiddingHook();
    }

    function testDirectHookCall() public {
        uint256 jobId = 34;
        bytes memory sig = hex"3fe813b094723d407703878949cd50dcc409e63ff747565f36e4021444713f6b5935da2e4e3ad57cade21ce7e1df30efa688519ec8e7ba43866b53b66401251f1b";
        uint256 price = 80 * 1e18;

        // Unwrapped format (what Escrow actually sends)
        bytes memory hookData = abi.encode(sig, price);
        hook.beforeAction(jobId, SEL_EXT, hookData);
    }

    function testUnwrappedFormat() public {
        // Test that unwrapped format works with new BiddingHook
        uint256 jobId = 34;
        bytes memory sig = hex"3fe813b094723d407703878949cd50dcc409e63ff747565f36e4021444713f6b5935da2e4e3ad57cade21ce7e1df30efa688519ec8e7ba43866b53b66401251f1b";
        uint256 price = 80 * 1e18;
        
        bytes memory hookData = abi.encode(sig, price);
        
        // Should recover the signer from the signature
        hook.beforeAction(jobId, SEL_EXT, hookData);
        
        // Verify bid was stored
        (address storedProvider, uint256 storedPrice) = hook.bids(jobId);
        assertEq(storedPrice, price);
        // The recovered signer should be provider A
        assertEq(storedProvider, provider);
    }
}
