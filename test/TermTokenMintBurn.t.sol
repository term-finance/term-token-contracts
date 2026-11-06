// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { TermToken } from "../src/TermToken.sol";

/**
 * @dev Tests for mint() and burn(). Both are restricted to DEFAULT_ADMIN_ROLE and only work while the
 * matching flag is unpaused by PAUSER_ROLE. Before this change any account could call them once the
 * flag was unpaused, and DEFAULT_ADMIN_ROLE could call them even while it was paused.
 */
contract TermTokenMintBurnTest is Test {
    uint256 internal constant INITIAL_SUPPLY = 1_000e18;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");
    address internal user = makeAddr("user");

    TermToken internal token;
    bytes32 internal adminRole;
    bytes32 internal pauserRole;

    function setUp() public {
        address impl = address(new TermToken());
        bytes memory init = abi.encodeCall(TermToken.initialize, (admin, pauser, upgrader, INITIAL_SUPPLY, admin));
        token = TermToken(address(new ERC1967Proxy(impl, init)));

        adminRole = token.DEFAULT_ADMIN_ROLE();
        pauserRole = token.PAUSER_ROLE();

        vm.prank(admin);
        token.transfer(user, 100e18);
    }

    function test_FlagsStartPaused() public view {
        assertFalse(token.mintingNotPaused());
        assertFalse(token.burningNotPaused());
    }

    // ---------------------------------------------------------------
    // mint
    // ---------------------------------------------------------------

    function test_AdminMintsToSelfWhenMintingUnpaused() public {
        _unpauseMinting();

        vm.prank(admin);
        uint256 minted = token.mint(5e18);

        assertEq(minted, 5e18);
        assertEq(token.balanceOf(admin), 905e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + 5e18);
    }

    function test_AdminMintRevertsWhileMintingPaused() public {
        vm.expectRevert(bytes("Minting Paused"));
        vm.prank(admin);
        token.mint(5e18);
    }

    function test_AdminMintRevertsAfterMintingPausedAgain() public {
        _unpauseMinting();
        vm.prank(pauser);
        token.pauseMinting();

        vm.expectRevert(bytes("Minting Paused"));
        vm.prank(admin);
        token.mint(5e18);
    }

    function test_NonAdminMintRevertsWhenMintingUnpaused() public {
        _unpauseMinting();

        vm.expectRevert(_unauthorized(user, adminRole));
        vm.prank(user);
        token.mint(5e18);

        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_NonAdminMintRevertsWhileMintingPaused() public {
        vm.expectRevert(_unauthorized(user, adminRole));
        vm.prank(user);
        token.mint(5e18);
    }

    function test_PauserCannotMint() public {
        _unpauseMinting();

        vm.expectRevert(_unauthorized(pauser, adminRole));
        vm.prank(pauser);
        token.mint(5e18);
    }

    function testFuzz_OnlyAdminCanMint(address caller, uint256 amount) public {
        vm.assume(caller != admin);
        amount = bound(amount, 1, 1_000_000e18);
        _unpauseMinting();

        vm.expectRevert(_unauthorized(caller, adminRole));
        vm.prank(caller);
        token.mint(amount);
    }

    function test_NewlyGrantedAdminCanMint() public {
        _unpauseMinting();
        vm.prank(admin);
        token.grantRole(adminRole, user);

        vm.prank(user);
        token.mint(5e18);

        assertEq(token.balanceOf(user), 105e18);
    }

    // ---------------------------------------------------------------
    // burn
    // ---------------------------------------------------------------

    function test_AdminBurnsOwnBalanceWhenBurningUnpaused() public {
        _unpauseBurning();

        vm.prank(admin);
        uint256 burned = token.burn(5e18);

        assertEq(burned, 5e18);
        assertEq(token.balanceOf(admin), 895e18);
        assertEq(token.balanceOf(user), 100e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - 5e18);
    }

    function test_AdminBurnRevertsWhileBurningPaused() public {
        vm.expectRevert(bytes("Burning Paused"));
        vm.prank(admin);
        token.burn(5e18);
    }

    function test_AdminBurnRevertsAfterBurningPausedAgain() public {
        _unpauseBurning();
        vm.prank(pauser);
        token.pauseBurning();

        vm.expectRevert(bytes("Burning Paused"));
        vm.prank(admin);
        token.burn(5e18);
    }

    function test_AdminBurnMoreThanBalanceReverts() public {
        _unpauseBurning();

        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", admin, 900e18, 901e18));
        vm.prank(admin);
        token.burn(901e18);
    }

    function test_NonAdminBurnRevertsWhenBurningUnpaused() public {
        _unpauseBurning();

        vm.expectRevert(_unauthorized(user, adminRole));
        vm.prank(user);
        token.burn(5e18);

        assertEq(token.balanceOf(user), 100e18);
    }

    function test_NonAdminBurnRevertsWhileBurningPaused() public {
        vm.expectRevert(_unauthorized(user, adminRole));
        vm.prank(user);
        token.burn(5e18);
    }

    function testFuzz_OnlyAdminCanBurn(address caller, uint256 amount) public {
        vm.assume(caller != admin);
        amount = bound(amount, 1, 100e18);
        _unpauseBurning();

        vm.expectRevert(_unauthorized(caller, adminRole));
        vm.prank(caller);
        token.burn(amount);
    }

    // ---------------------------------------------------------------
    // flag toggles
    // ---------------------------------------------------------------

    function test_OnlyPauserCanToggleMintingAndBurning() public {
        vm.startPrank(admin);
        vm.expectRevert(_unauthorized(admin, pauserRole));
        token.unpauseMinting();
        vm.expectRevert(_unauthorized(admin, pauserRole));
        token.unpauseBurning();
        vm.stopPrank();

        assertFalse(token.mintingNotPaused());
        assertFalse(token.burningNotPaused());
    }

    function test_MintingAndBurningFlagsAreIndependent() public {
        _unpauseMinting();

        assertTrue(token.mintingNotPaused());
        assertFalse(token.burningNotPaused());
        vm.expectRevert(bytes("Burning Paused"));
        vm.prank(admin);
        token.burn(1e18);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    function _unpauseMinting() internal {
        vm.prank(pauser);
        token.unpauseMinting();
    }

    function _unpauseBurning() internal {
        vm.prank(pauser);
        token.unpauseBurning();
    }

    function _unauthorized(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", account, role);
    }
}
