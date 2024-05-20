// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TermToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTermTokenImpl is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        address admin = vm.envAddress("ADMIN_WALLET");

        TermToken impl = new TermToken(lzEndpoint, admin);

        console.log("deployed impl contract to");
        console.log(address(impl));
        
        vm.stopBroadcast();
    }
}
