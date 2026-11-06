// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { TermToken } from "../src/TermToken.sol";
import { TermTokenOFT } from "./legacy/TermTokenOFT.sol";

/**
 * @dev Rehearses the OFT removal upgrade on a fork of the live Ethereum proxy. Skipped unless
 * MAINNET_RPC_URL is set; the RPC must serve state at FORK_BLOCK.
 */
contract TermTokenMainnetForkTest is Test {
    TermTokenOFT internal constant PROXY = TermTokenOFT(0xC3d21f79C3120A4fFda7A535f8005a7c297799bF);
    address internal constant DEPLOYED_IMPL = 0xeC222d8AfB8b4E78C418ebc1ab2cA181f19FbadC;
    uint256 internal constant FORK_BLOCK = 26_242_523;

    /// @dev Everything the upgrade must leave untouched.
    struct State {
        bytes32[5] slots;
        uint256 totalSupply;
        uint256 pastTotalSupply;
        uint256 safeBalance;
        bytes32 domainSeparator;
        bool paused;
        bool mintingNotPaused;
        bool burningNotPaused;
    }

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            // MAINNET_RPC_URL not set
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
    }

    function test_UpgradeLiveProxy() public {
        assertEq(_implementation(), DEPLOYED_IMPL);
        // the OFT owner and the upgrader are the same Safe
        address safe = PROXY.owner();
        assertTrue(PROXY.hasRole(PROXY.UPGRADER_ROLE(), safe));
        assertTrue(PROXY.hasRole(PROXY.DEFAULT_ADMIN_ROLE(), safe));
        State memory before = _state(safe);

        address impl = address(new TermToken());
        vm.prank(safe);
        PROXY.upgradeToAndCall(impl, "");
        TermToken t = TermToken(address(PROXY));

        assertEq(_implementation(), impl);
        assertEq(abi.encode(_state(safe)), abi.encode(before));
        assertEq(t.name(), "Term Finance");
        assertEq(t.symbol(), "TERM");
        assertTrue(t.hasRole(t.DEFAULT_ADMIN_ROLE(), safe));
        assertTrue(t.hasRole(t.UPGRADER_ROLE(), safe));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        t.initialize(safe, safe, safe, 0, safe);

        (bool ok, ) = address(t).call(abi.encodeWithSelector(PROXY.owner.selector));
        assertFalse(ok);

        // the Safe can still upgrade
        address next = address(new TermToken());
        vm.prank(safe);
        t.upgradeToAndCall(next, "");
        assertEq(_implementation(), next);
    }

    /// @dev Reads through TermToken's ABI, which both implementations share for these functions.
    function _state(address safe) internal view returns (State memory s) {
        TermToken t = TermToken(address(PROXY));
        for (uint256 i = 0; i < 5; i++) {
            s.slots[i] = vm.load(address(t), bytes32(i));
        }
        s.totalSupply = t.totalSupply();
        s.pastTotalSupply = t.getPastTotalSupply(block.timestamp - 1);
        s.safeBalance = t.balanceOf(safe);
        s.domainSeparator = t.DOMAIN_SEPARATOR();
        s.paused = t.paused();
        s.mintingNotPaused = t.mintingNotPaused();
        s.burningNotPaused = t.burningNotPaused();
    }

    function _implementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(PROXY), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }
}
