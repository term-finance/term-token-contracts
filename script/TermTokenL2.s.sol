// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TermTokenL2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTermTokenL2 is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        address admin = vm.envAddress("ADMIN_WALLET");
        address pauser = vm.envAddress("PAUSE_WALLET");
        address upgrader = vm.envAddress("UPGRADE_WALLET");

        TermTokenL2 impl = new TermTokenL2(lzEndpoint, admin);

        console.log("deployed impl contract to");
        console.log(address(impl));

        // Deploy the Proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(TermTokenL2.initialize.selector, admin, pauser, upgrader)
        );

        TermTokenL2 token = TermTokenL2(address(proxy));
        console.log("deployed proxy to");
        console.log(address(proxy));
        
        vm.stopBroadcast();
    }
}
