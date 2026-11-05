// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TermToken.sol";

contract DeployTermTokenImpl is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        TermToken impl = new TermToken();

        console.log("deployed impl contract to");
        console.log(address(impl));
        
        vm.stopBroadcast();
    }
}
