// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TermToken.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CrossChainTransfer is Script {

    function run() external {
        uint256 deployerPK = vm.envUint("X_CHAIN_PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        uint32 endpointId = uint32(vm.envUint("DESTINATION_ENDPOINT"));
        address toAddress = vm.envAddress("DESTINATION_ADDRESS");
        uint256 amountInLocalDecimals = vm.envUint("AMOUNT_IN_LD");
        uint256 minAmountLocalDecimals = vm.envUint("MIN_AMOUNT_IN_LD");
        address termTokenAddress = vm.envAddress("TERM_TOKEN_ADDRESS");
        address refundAddress = vm.envAddress("REFUND_ADDRESS");


        bytes32 toAddressBytes = bytes32(uint(uint160(toAddress)));

        TermToken token = TermToken(termTokenAddress);

        //bytes memory options = OptionsBuilder.encodeLegacyOptionsType1(60000);

        SendParam memory sendParam = SendParam({
            dstEid: endpointId,
            to: toAddressBytes,
            amountLD: amountInLocalDecimals,
            minAmountLD: minAmountLocalDecimals,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });
        MessagingFee memory messageFee = token.quoteSend(sendParam, false);
        
        token.send{value: messageFee.nativeFee}(sendParam, messageFee, refundAddress);
        
        vm.stopBroadcast();
    }
}
