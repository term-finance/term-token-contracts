// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { MockEndpoint } from "../mocks/MockEndpoint.sol";

/// @dev Functions shared by TermToken, TermTokenL2 and their pre-fix snapshots.
interface ITermTokenLike {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
    function delegate(address delegatee) external;
    function getVotes(address account) external view returns (uint256);
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/**
 * @dev Tests for the DEFAULT_ADMIN_ROLE pause exemption in _update.
 *
 * Both tokens call ERC20VotesUpgradeable._update directly so that the whenNotPaused check in
 * ERC20PausableUpgradeable._update is skipped. That only works while ERC20PausableUpgradeable is
 * listed after ERC20VotesUpgradeable in the inheritance list, so the admin tests here fail if the
 * order changes or _update goes back to super._update.
 */
abstract contract PauseExemptionBase is Test {
    string internal constant PAUSED_ERROR = "TermToken: token transfer while paused";

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal upgrader = makeAddr("upgrader");
    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");

    MockEndpoint internal endpoint;
    ITermTokenLike internal token;

    /// @dev Deploys the current implementation behind an initialized proxy.
    function _deployFixed() internal virtual returns (ITermTokenLike);

    /// @dev Deploys the pre-fix snapshot behind an initialized proxy.
    function _deployPreFix() internal virtual returns (ITermTokenLike);

    /// @dev Deploys a bare current implementation to upgrade to.
    function _newFixedImpl() internal virtual returns (address);

    /// @dev Calls initialize on a proxy that is already initialized.
    function _callInitialize(ITermTokenLike t) internal virtual;

    /// @dev Leaves admin with 1,000 tokens and user with 100, out of a total supply of 1,100.
    function _fund(ITermTokenLike t) internal virtual;

    function setUp() public virtual {
        endpoint = new MockEndpoint();
        token = _deployFixed();
        _fundAndDelegate(token);
    }

    // ---------------------------------------------------------------
    // Current implementation
    // ---------------------------------------------------------------

    function test_AdminCanTransferWhilePaused() public {
        _pause(token);

        vm.prank(admin);
        token.transfer(recipient, 10e18);

        assertEq(token.balanceOf(admin), 990e18);
        assertEq(token.balanceOf(recipient), 10e18);
    }

    function test_NonAdminTransferWhilePausedReverts() public {
        _pause(token);

        vm.expectRevert(bytes(PAUSED_ERROR));
        vm.prank(user);
        token.transfer(recipient, 1e18);
    }

    function test_TransfersResumeAfterUnpause() public {
        _pause(token);
        vm.prank(pauser);
        token.unpause();

        vm.prank(user);
        token.transfer(recipient, 1e18);

        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_VotesFollowAdminTransferWhilePaused() public {
        _pause(token);

        vm.prank(admin);
        token.transfer(user, 200e18);

        assertEq(token.getVotes(admin), 800e18);
        assertEq(token.getVotes(user), 300e18);
    }

    // ---------------------------------------------------------------
    // Upgrading an existing proxy from the pre-fix implementation
    // ---------------------------------------------------------------

    function test_PreFixImplementationBlocksAdminWhilePaused() public {
        ITermTokenLike legacy = _deployPreFix();
        _fundAndDelegate(legacy);
        _pause(legacy);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(admin);
        legacy.transfer(recipient, 1e18);
    }

    function test_UpgradeFromPreFixWhilePaused() public {
        _checkUpgradeFromPreFix(true);
    }

    function test_UpgradeFromPreFixWhileUnpaused() public {
        _checkUpgradeFromPreFix(false);
    }

    function _checkUpgradeFromPreFix(bool pausedBeforeUpgrade) internal {
        ITermTokenLike t = _deployPreFix();
        _fundAndDelegate(t);
        vm.prank(admin);
        t.transfer(user, 100e18);
        if (pausedBeforeUpgrade) _pause(t);
        uint256 supplyBefore = t.totalSupply();

        address newImpl = _newFixedImpl();
        vm.prank(upgrader);
        t.upgradeToAndCall(newImpl, "");

        // state carries over and initialize cannot run again
        assertEq(t.paused(), pausedBeforeUpgrade);
        assertEq(t.totalSupply(), supplyBefore);
        assertEq(t.balanceOf(admin), 900e18);
        assertEq(t.balanceOf(user), 200e18);
        assertEq(t.getVotes(admin), 900e18);
        assertEq(t.getVotes(user), 200e18);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _callInitialize(t);

        // the admin exemption now works and everyone else is still blocked
        if (!pausedBeforeUpgrade) _pause(t);
        vm.prank(admin);
        t.transfer(recipient, 50e18);
        assertEq(t.balanceOf(recipient), 50e18);
        assertEq(t.getVotes(admin), 850e18);

        vm.expectRevert(bytes(PAUSED_ERROR));
        vm.prank(user);
        t.transfer(recipient, 1e18);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    /// @dev Funds admin with 1,000 tokens and user with 100, and self-delegates both.
    function _fundAndDelegate(ITermTokenLike t) internal {
        _fund(t);

        vm.prank(admin);
        t.delegate(admin);
        vm.prank(user);
        t.delegate(user);
    }

    function _pause(ITermTokenLike t) internal {
        vm.prank(pauser);
        t.pause();
    }
}
