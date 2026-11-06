// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @dev Minimal LayerZero endpoint stand-in. OAppCore's constructor only calls setDelegate, quote and
/// send let OFT.send() run end to end for free, and tests deliver bridge messages by calling lzReceive
/// on the token while pranking as this contract.
contract MockEndpoint {
    function setDelegate(address) external {}

    function quote(MessagingParams calldata, address) external pure returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }

    function send(MessagingParams calldata, address) external payable returns (MessagingReceipt memory receipt) {
        receipt.guid = bytes32(uint256(1));
        receipt.nonce = 1;
    }
}
