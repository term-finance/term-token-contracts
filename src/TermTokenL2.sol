// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";


/// @custom:security-contact devops@termfinance.io
contract TermTokenL2 is Initializable, ContextUpgradeable, OFTCore, ERC20Upgradeable, ERC20PausableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint, address _delegate) OFTCore(18, _lzEndpoint, _delegate) Ownable(msg.sender) {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address pauser, address upgrader)
        initializer public
    {
        __ERC20_init("Term Finance", "TERM");
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("Term Finance");
        __ERC20Votes_init();
        __UUPSUpgradeable_init();
        __Context_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UPGRADER_ROLE, upgrader);

        _transferOwnership(defaultAdmin);
    }

    /**
     * @notice Retrieves interfaceID and the version of the OFT.
     * @return interfaceId The interface ID.
     * @return version The version.
     *
     * @dev interfaceId: This specific interface ID is '0x02e49c2c'.
     * @dev version: Indicates a cross-chain compatible msg encoding with other OFTs.
     * @dev If a new feature is added to the OFT cross-chain msg encoding, the version will be incremented.
     * ie. localOFT version(x,1) CAN send messages to remoteOFT version(x,1)
     */
    function oftVersion() external pure virtual returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the OFT token.
     *
     * @dev In the case of OFT, address(this) and erc20 are the same contract.
     */
    function token() external view returns (address) {
        return address(this);
    }

    /**
     * @dev Returns the current block timestamp.
     * This function is used to get the current time in seconds since the Unix epoch.
     * 
     * @return uint256 The current block timestamp.
     */
    function clock() public view override (VotesUpgradeable) returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Returns the current mode of the clock.
     * The mode can be one of the predefined constants representing different clock states.
     * 
     * @return uint256 representing the current clock mode.
     */
    function CLOCK_MODE() public pure override (VotesUpgradeable) returns (string memory) {
        return "mode=timestamp&from=default";
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Needs approval of the underlying token implementation.
     *
     * @dev In the case of OFT where the contract IS the token, approval is NOT required.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev Burns tokens from the sender's specified balance.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev In NON-default OFT, amountSentLD could be 100, with a 10% fee, the amountReceivedLD amount is 90,
        // therefore amountSentLD CAN differ from amountReceivedLD.

        // @dev Default OFT burns on src.
        _burn(msg.sender, amountSentLD);
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        // @dev Default OFT mints on dst.
        _mint(_to, _amountLD);
        // @dev In the case of NON-default OFT, the _amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }

    //@dev pauses all transfers
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    //@dev unpauses all transfers
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // @dev solidity requires this override
     function _msgSender() internal view override(ContextUpgradeable, Context) returns (address) {
        return super._msgSender();
    }

    // @dev solidity requires this override
    function _msgData() internal view override(ContextUpgradeable, Context) returns (bytes calldata) {
        return super._msgData();
    }

    // @dev solidity requires this override
    function _contextSuffixLength() internal view 
    override(ContextUpgradeable, Context) returns (uint256) {
        return super._contextSuffixLength();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20VotesUpgradeable)
    {
        require(to != address(this), "TermToken: cannot transfer tokens to token contract");
        // Token transfers are only possible if the contract is not paused
        // OR if triggered by the owner of the contract
        require(!paused() || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "TermToken: token transfer while paused");
        
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
