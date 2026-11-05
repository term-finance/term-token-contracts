// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OFTMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { TermTokenL2 } from "../src/TermTokenL2.sol";
import { TermTokenL2PreFix } from "./legacy/TermTokenL2PreFix.sol";
import { PauseExemptionBase, ITermTokenLike } from "./utils/PauseExemptionBase.sol";

contract TermTokenL2PauseTest is PauseExemptionBase {
    uint32 internal constant SRC_EID = 30101;
    bytes32 internal constant PEER = bytes32(uint256(0xbeef));

    uint64 internal nonce;

    function _deployFixed() internal override returns (ITermTokenLike) {
        return _deployProxy(_newFixedImpl());
    }

    function _deployPreFix() internal override returns (ITermTokenLike) {
        return _deployProxy(address(new TermTokenL2PreFix(address(endpoint), admin)));
    }

    function _newFixedImpl() internal override returns (address) {
        return address(new TermTokenL2(address(endpoint), admin));
    }

    function _callInitialize(ITermTokenLike t) internal override {
        TermTokenL2(address(t)).initialize(admin, pauser, upgrader);
    }

    /// @dev TermTokenL2 has no initial supply, so the tokens arrive as bridge messages from the peer.
    function _fund(ITermTokenLike t) internal override {
        vm.prank(admin);
        TermTokenL2(address(t)).setPeer(SRC_EID, PEER);
        _bridgeIn(t, admin, 1_000e18);
        _bridgeIn(t, user, 100e18);
    }

    function _deployProxy(address impl) private returns (ITermTokenLike) {
        bytes memory init = abi.encodeCall(TermTokenL2.initialize, (admin, pauser, upgrader));
        return ITermTokenLike(address(new ERC1967Proxy(impl, init)));
    }

    function test_BridgeCreditWhilePausedReverts() public {
        _pause(token);

        // lzReceive is called by the endpoint, which does not hold DEFAULT_ADMIN_ROLE
        vm.expectRevert(bytes(PAUSED_ERROR));
        _bridgeIn(token, recipient, 1e18);
    }

    function test_BridgeCreditResumesAfterUnpause() public {
        _pause(token);
        vm.prank(pauser);
        token.unpause();

        _bridgeIn(token, recipient, 2e18);

        assertEq(token.balanceOf(recipient), 2e18);
    }

    /// @dev Delivers an OFT message from the peer, as the endpoint would. Works on the pre-fix snapshot too.
    function _bridgeIn(ITermTokenLike t, address to, uint256 amountLD) internal {
        // shared decimals are 6 and local decimals are 18
        (bytes memory message, ) = OFTMsgCodec.encode(OFTMsgCodec.addressToBytes32(to), uint64(amountLD / 1e12), "");
        nonce++;
        vm.prank(address(endpoint));
        TermTokenL2(address(t)).lzReceive(Origin(SRC_EID, PEER, nonce), bytes32(uint256(nonce)), message, address(0), "");
    }
}
