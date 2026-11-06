// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

import { TermToken } from "../src/TermToken.sol";
import { TermTokenOFT } from "./legacy/TermTokenOFT.sol";
import { MockEndpoint } from "./mocks/MockEndpoint.sol";

/**
 * @dev Upgrades a proxy running the OFT implementation that is live on Ethereum to the current
 * TermToken, which no longer inherits OFTCore, and checks that no state moves or is lost.
 *
 * The OFT parents own slots 0-4 (owner, peers, preCrime, enforcedOptions, msgInspector), and
 * burningNotPaused and mintingNotPaused are packed into slot 4 after msgInspector. Everything else
 * lives in OpenZeppelin's ERC-7201 namespaces.
 */
contract TermTokenOFTRemovalTest is Test {
    uint32 internal constant EID = 30110;
    uint16 internal constant MSG_TYPE = 1;
    bytes32 internal constant PEER = bytes32(uint256(0xbeef));
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 internal constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");
    address internal recipient = makeAddr("recipient");
    address internal preCrime = makeAddr("preCrime");
    address internal user;
    uint256 internal userKey;

    function setUp() public {
        (user, userKey) = makeAddrAndKey("user");
    }

    // ---------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------

    function testFuzz_UpgradeKeepsPackedMintBurnFlags(bool mintingOn, bool burningOn, address inspector) public {
        TermTokenOFT legacy = _deployLegacy();
        _fillOFTState(legacy, inspector);
        _setFlags(address(legacy), mintingOn, burningOn);
        bytes32[] memory before = _oftSlots(address(legacy));

        // the slot model above matches the legacy layout
        assertEq(before[0], bytes32(uint256(uint160(admin))));
        assertEq(before[2], bytes32(uint256(uint160(preCrime))));
        assertEq(address(uint160(uint256(before[4]))), inspector);
        assertEq(before[5], PEER);
        // byte offsets 20 and 21 of slot 4, counted from the low-order end
        assertEq(before[4][31 - 20], burningOn ? bytes1(0x01) : bytes1(0x00));
        assertEq(before[4][31 - 21], mintingOn ? bytes1(0x01) : bytes1(0x00));

        TermToken t = _upgrade(address(legacy));

        assertEq(abi.encode(_oftSlots(address(t))), abi.encode(before));
        assertEq(t.mintingNotPaused(), mintingOn);
        assertEq(t.burningNotPaused(), burningOn);

        // the flags still gate mint and burn, which only admin may call
        if (!mintingOn) vm.expectRevert(bytes("Minting Paused"));
        vm.prank(admin);
        t.mint(1e18);
        if (!burningOn) vm.expectRevert(bytes("Burning Paused"));
        vm.prank(admin);
        t.burn(1e18);

        // writing the flags through the new implementation leaves the msgInspector bytes alone
        _setFlags(address(t), !mintingOn, !burningOn);
        assertEq(t.mintingNotPaused(), !mintingOn);
        assertEq(t.burningNotPaused(), !burningOn);
        assertEq(address(uint160(uint256(vm.load(address(t), bytes32(uint256(4)))))), inspector);
    }

    function test_UpgradeKeepsTokenState() public {
        TermTokenOFT legacy = _deployLegacy();
        _fillOFTState(legacy, makeAddr("inspector"));
        vm.prank(admin);
        legacy.delegate(admin);
        vm.prank(user);
        legacy.delegate(user);
        _permit(address(legacy), 0);
        uint256 delegatedAt = block.timestamp;
        vm.warp(block.timestamp + 1 days);
        vm.prank(pauser);
        legacy.pause();
        bytes32 domainSeparator = legacy.DOMAIN_SEPARATOR();

        TermToken t = _upgrade(address(legacy));

        assertEq(t.name(), "Term Finance");
        assertEq(t.symbol(), "TERM");
        assertEq(t.decimals(), 18);
        assertEq(t.totalSupply(), 1_000e18);
        assertEq(t.balanceOf(admin), 900e18);
        assertEq(t.balanceOf(user), 100e18);
        assertEq(t.allowance(user, recipient), 5e18);
        assertEq(t.nonces(user), 1);
        assertEq(t.DOMAIN_SEPARATOR(), domainSeparator);
        assertEq(t.delegates(user), user);
        assertEq(t.getVotes(admin), 900e18);
        assertEq(t.getVotes(user), 100e18);
        assertEq(t.getPastVotes(user, delegatedAt), 100e18);
        assertEq(t.getPastTotalSupply(delegatedAt), 1_000e18);
        assertTrue(t.paused());
        assertTrue(t.hasRole(t.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(t.hasRole(t.PAUSER_ROLE(), pauser));
        assertTrue(t.hasRole(t.UPGRADER_ROLE(), upgrader));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        t.initialize(admin, pauser, upgrader, 0, admin);

        // permit picks up the stored nonce, and transfers resume after unpause
        _permit(address(t), 1);
        vm.prank(pauser);
        t.unpause();
        vm.prank(user);
        t.transfer(recipient, 10e18);
        assertEq(t.balanceOf(recipient), 10e18);
        assertEq(t.getVotes(user), 90e18);
    }

    // ---------------------------------------------------------------
    // Interface
    // ---------------------------------------------------------------

    function test_OFTFunctionsRemoved() public {
        TermTokenOFT legacy = _deployLegacy();
        _fillOFTState(legacy, makeAddr("inspector"));
        address endpoint = address(legacy.endpoint());
        TermToken t = _upgrade(address(legacy));

        // every external function that came from OFTCore and its parents, including Ownable
        bytes4[33] memory removed = [
            legacy.SEND.selector,
            legacy.SEND_AND_CALL.selector,
            legacy.allowInitializePath.selector,
            legacy.approvalRequired.selector,
            legacy.combineOptions.selector,
            legacy.composeMsgSender.selector,
            legacy.decimalConversionRate.selector,
            legacy.endpoint.selector,
            legacy.enforcedOptions.selector,
            legacy.isPeer.selector,
            legacy.lzReceive.selector,
            legacy.lzReceiveAndRevert.selector,
            legacy.lzReceiveSimulate.selector,
            legacy.msgInspector.selector,
            legacy.nextNonce.selector,
            legacy.oApp.selector,
            legacy.oAppVersion.selector,
            legacy.oftVersion.selector,
            legacy.owner.selector,
            legacy.peers.selector,
            legacy.preCrime.selector,
            legacy.quoteOFT.selector,
            legacy.quoteSend.selector,
            legacy.renounceOwnership.selector,
            legacy.send.selector,
            legacy.setDelegate.selector,
            legacy.setEnforcedOptions.selector,
            legacy.setMsgInspector.selector,
            legacy.setPeer.selector,
            legacy.setPreCrime.selector,
            legacy.sharedDecimals.selector,
            legacy.token.selector,
            legacy.transferOwnership.selector
        ];

        // neither the old owner nor the endpoint can reach them, and nothing falls through to a fallback.
        // A missing function reverts with no data, unlike an access control or argument check.
        address[2] memory callers = [admin, endpoint];
        for (uint256 c = 0; c < callers.length; c++) {
            for (uint256 i = 0; i < removed.length; i++) {
                string memory selector = vm.toString(abi.encodePacked(removed[i]));
                vm.prank(callers[c]);
                (bool ok, bytes memory returnData) = address(t).call(abi.encodePacked(removed[i], new bytes(256)));
                assertFalse(ok, selector);
                assertEq(returnData.length, 0, selector);
            }
        }
    }

    // ---------------------------------------------------------------
    // Fresh deployment
    // ---------------------------------------------------------------

    function test_FlagsPackedIntoSlot4() public {
        TermToken t = _deployFresh();
        bytes32 burningBit = bytes32(uint256(1) << 160);
        bytes32 mintingBit = bytes32(uint256(1) << 168);

        vm.startPrank(pauser);
        t.unpauseBurning();
        assertEq(_slot4(t), burningBit);
        t.unpauseMinting();
        assertEq(_slot4(t), burningBit | mintingBit);
        t.pauseBurning();
        assertEq(_slot4(t), mintingBit);
        t.pauseMinting();
        assertEq(_slot4(t), bytes32(0));
        vm.stopPrank();
    }

    /// @dev Calls every state-changing function and checks that none of them writes the reserved slots.
    function test_NoFunctionWritesReservedSlots() public {
        TermToken t = _deployFresh();

        vm.startPrank(pauser);
        t.unpauseMinting();
        t.unpauseBurning();
        vm.stopPrank();
        _assertReservedSlotsEmpty(t);

        vm.startPrank(admin);
        t.mint(10e18);
        t.burn(1e18);
        vm.stopPrank();
        vm.startPrank(user);
        t.approve(recipient, 5e18);
        t.transfer(recipient, 1e18);
        t.delegate(user);
        vm.stopPrank();
        vm.prank(recipient);
        t.transferFrom(user, recipient, 2e18);
        _assertReservedSlotsEmpty(t);

        // permit and delegateBySig share the user's nonce
        _permit(address(t), 0);
        _delegateBySig(t, recipient, 1);
        _assertReservedSlotsEmpty(t);

        bytes32 pauserRole = t.PAUSER_ROLE();
        vm.startPrank(admin);
        t.grantRole(pauserRole, recipient);
        t.revokeRole(pauserRole, recipient);
        vm.stopPrank();
        vm.startPrank(pauser);
        t.pause();
        t.unpause();
        t.pauseMinting();
        t.pauseBurning();
        t.renounceRole(pauserRole, pauser);
        vm.stopPrank();
        address next = address(new TermToken());
        vm.prank(upgrader);
        t.upgradeToAndCall(next, "");
        _assertReservedSlotsEmpty(t);
        assertEq(_slot4(t), bytes32(0));
    }

    function test_FreshDeployment() public {
        TermToken impl = new TermToken();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(admin, pauser, upgrader, 0, admin);

        TermToken t = _deployFresh();

        assertEq(t.totalSupply(), 1_000e18);
        assertEq(t.balanceOf(user), 1_000e18);
        assertTrue(t.hasRole(t.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(t.hasRole(t.PAUSER_ROLE(), pauser));
        assertTrue(t.hasRole(t.UPGRADER_ROLE(), upgrader));
        assertFalse(t.mintingNotPaused());
        assertFalse(t.burningNotPaused());
        // initialize no longer sets an owner, so the reserved slots stay empty
        for (uint256 i = 0; i < 5; i++) {
            assertEq(vm.load(address(t), bytes32(i)), bytes32(0));
        }
    }

    // ---------------------------------------------------------------
    // Upgradeability
    // ---------------------------------------------------------------

    function test_StillUpgradeableByUpgraderOnly() public {
        TermToken t = _upgrade(address(_deployLegacy()));
        address next = address(new TermToken());
        bytes32 upgraderRole = t.UPGRADER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, upgraderRole)
        );
        vm.prank(admin);
        t.upgradeToAndCall(next, "");

        vm.prank(upgrader);
        t.upgradeToAndCall(next, "");
        assertEq(_implementation(address(t)), next);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    /// @dev Deploys the current implementation behind an initialized proxy that mints 1,000 tokens to user.
    function _deployFresh() internal returns (TermToken) {
        bytes memory init = abi.encodeCall(TermToken.initialize, (admin, pauser, upgrader, 1_000e18, user));
        return TermToken(address(new ERC1967Proxy(address(new TermToken()), init)));
    }

    function _slot4(TermToken t) internal view returns (bytes32) {
        return vm.load(address(t), bytes32(uint256(4)));
    }

    /// @dev Slots 0-3 are empty and slot 4 holds nothing but the flag bytes at offsets 20 and 21.
    function _assertReservedSlotsEmpty(TermToken t) internal view {
        for (uint256 i = 0; i < 4; i++) {
            assertEq(vm.load(address(t), bytes32(i)), bytes32(0));
        }
        assertEq(uint256(_slot4(t)) & ~(uint256(0xffff) << 160), 0);
    }

    /// @dev Deploys the OFT implementation behind an initialized proxy and moves 100 of admin's 1,000 tokens to user.
    function _deployLegacy() internal returns (TermTokenOFT legacy) {
        address impl = address(new TermTokenOFT(address(new MockEndpoint()), admin));
        bytes memory init = abi.encodeCall(TermTokenOFT.initialize, (admin, pauser, upgrader, 1_000e18, admin));
        legacy = TermTokenOFT(address(new ERC1967Proxy(impl, init)));
        vm.prank(admin);
        legacy.transfer(user, 100e18);
    }

    /// @dev Writes every OFT-owned slot so the upgrade has data to preserve. Slot 0 already holds the owner.
    function _fillOFTState(TermTokenOFT legacy, address inspector) internal {
        EnforcedOptionParam[] memory options = new EnforcedOptionParam[](1);
        options[0] = EnforcedOptionParam(EID, MSG_TYPE, hex"0003");

        vm.startPrank(admin);
        legacy.setPeer(EID, PEER);
        legacy.setPreCrime(preCrime);
        legacy.setEnforcedOptions(options);
        legacy.setMsgInspector(inspector);
        vm.stopPrank();
    }

    /// @dev Raw values of slots 0-4 and of the mapping entries written by _fillOFTState.
    function _oftSlots(address proxy) internal view returns (bytes32[] memory values) {
        values = new bytes32[](7);
        for (uint256 i = 0; i < 5; i++) {
            values[i] = vm.load(proxy, bytes32(i));
        }
        values[5] = vm.load(proxy, keccak256(abi.encode(EID, uint256(1))));
        values[6] = vm.load(proxy, keccak256(abi.encode(MSG_TYPE, keccak256(abi.encode(EID, uint256(3))))));
    }

    /// @dev Works on both implementations, which share the flag setters.
    function _setFlags(address t, bool mintingOn, bool burningOn) internal {
        vm.startPrank(pauser);
        if (mintingOn) TermToken(t).unpauseMinting();
        else TermToken(t).pauseMinting();
        if (burningOn) TermToken(t).unpauseBurning();
        else TermToken(t).pauseBurning();
        vm.stopPrank();
    }

    function _upgrade(address proxy) internal returns (TermToken) {
        address impl = address(new TermToken());
        vm.prank(upgrader);
        TermTokenOFT(proxy).upgradeToAndCall(impl, "");
        assertEq(_implementation(proxy), impl);
        return TermToken(proxy);
    }

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    /// @dev Signs and submits a permit from user to recipient for 5 tokens.
    function _permit(address t, uint256 nonce) internal {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, user, recipient, 5e18, nonce, block.timestamp));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, _digest(t, structHash));
        TermToken(t).permit(user, recipient, 5e18, block.timestamp, v, r, s);
    }

    /// @dev Signs and submits a delegation from user to delegatee.
    function _delegateBySig(TermToken t, address delegatee, uint256 nonce) internal {
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, block.timestamp));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, _digest(address(t), structHash));
        t.delegateBySig(delegatee, nonce, block.timestamp, v, r, s);
    }

    function _digest(address t, bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", TermToken(t).DOMAIN_SEPARATOR(), structHash));
    }
}
