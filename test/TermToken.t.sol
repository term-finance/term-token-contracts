// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import { TermToken } from "../src/TermToken.sol";
import { TermTokenPreFix } from "./legacy/TermTokenPreFix.sol";
import { PauseExemptionBase, ITermTokenLike } from "./utils/PauseExemptionBase.sol";

contract TermTokenPauseTest is PauseExemptionBase {
    function _deployFixed() internal override returns (ITermTokenLike) {
        return _deployProxy(_newFixedImpl());
    }

    function _deployPreFix() internal override returns (ITermTokenLike) {
        return _deployProxy(address(new TermTokenPreFix(address(endpoint), admin)));
    }

    function _newFixedImpl() internal override returns (address) {
        return address(new TermToken());
    }

    function _callInitialize(ITermTokenLike t) internal override {
        TermToken(address(t)).initialize(admin, pauser, upgrader, 0, admin);
    }

    /// @dev TermToken cannot bridge, so admin starts with the whole supply and hands 100 tokens to user.
    function _fund(ITermTokenLike t) internal override {
        vm.prank(admin);
        t.transfer(user, 100e18);
    }

    function _deployProxy(address impl) private returns (ITermTokenLike) {
        bytes memory init = abi.encodeCall(TermToken.initialize, (admin, pauser, upgrader, 1_100e18, admin));
        return ITermTokenLike(address(new ERC1967Proxy(impl, init)));
    }

    function test_AdminCanMintWhilePaused() public {
        vm.prank(pauser);
        TermToken(address(token)).unpauseMinting();
        _pause(token);

        vm.prank(admin);
        TermToken(address(token)).mint(5e18);

        assertEq(token.balanceOf(admin), 1_005e18);
        assertEq(token.getVotes(admin), 1_005e18);
    }

    function test_VotesSupplyCapStillEnforced() public {
        // _update still runs ERC20VotesUpgradeable's checks, including the uint208 supply cap
        vm.prank(pauser);
        TermToken(address(token)).unpauseMinting();
        uint256 cap = type(uint208).max;
        uint256 amount = cap - token.totalSupply() + 1;

        vm.expectRevert(abi.encodeWithSelector(ERC20VotesUpgradeable.ERC20ExceededSafeSupply.selector, cap + 1, cap));
        vm.prank(admin);
        TermToken(address(token)).mint(amount);
    }
}
