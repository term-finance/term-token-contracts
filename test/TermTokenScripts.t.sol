// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { TermToken } from "../src/TermToken.sol";
import { DeployTermToken } from "../script/TermToken.s.sol";
import { DeployTermTokenImpl } from "../script/TermTokenImplOnly.s.sol";

/// @dev Runs the deploy scripts, which no longer read LZ_ENDPOINT, with the environment the workflows provide.
contract TermTokenScriptsTest is Test {
    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");
    address internal minter = makeAddr("minter");
    address internal deployer;
    uint256 internal deployerKey;

    function setUp() public {
        (deployer, deployerKey) = makeAddrAndKey("deployer");
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerKey));
        vm.setEnv("RPC_URL", "http://127.0.0.1:8545");
    }

    function test_DeployImplOnly() public {
        TermToken impl = TermToken(vm.computeCreateAddress(deployer, vm.getNonce(deployer)));

        new DeployTermTokenImpl().run();

        assertEq(impl.proxiableUUID(), ERC1967Utils.IMPLEMENTATION_SLOT);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(admin, pauser, upgrader, 0, admin);
    }

    function test_DeployProxy() public {
        vm.setEnv("ADMIN_WALLET", vm.toString(admin));
        vm.setEnv("PAUSE_WALLET", vm.toString(pauser));
        vm.setEnv("UPGRADE_WALLET", vm.toString(upgrader));
        vm.setEnv("TOKEN_MINT_SUPPLY", vm.toString(uint256(1_000e18)));
        vm.setEnv("MINT_ADDRESS", vm.toString(minter));
        uint64 nonce = vm.getNonce(deployer);
        address impl = vm.computeCreateAddress(deployer, nonce);
        TermToken t = TermToken(vm.computeCreateAddress(deployer, nonce + 1));

        new DeployTermToken().run();

        assertEq(address(uint160(uint256(vm.load(address(t), ERC1967Utils.IMPLEMENTATION_SLOT)))), impl);
        assertEq(t.totalSupply(), 1_000e18);
        assertEq(t.balanceOf(minter), 1_000e18);
        assertTrue(t.hasRole(t.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(t.hasRole(t.PAUSER_ROLE(), pauser));
        assertTrue(t.hasRole(t.UPGRADER_ROLE(), upgrader));
        assertFalse(t.hasRole(t.DEFAULT_ADMIN_ROLE(), deployer));
        for (uint256 i = 0; i < 5; i++) {
            assertEq(vm.load(address(t), bytes32(i)), bytes32(0));
        }
    }
}
