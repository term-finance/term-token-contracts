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

/// @custom:security-contact devops@termfinance.io
/// @dev ERC20PausableUpgradeable must stay listed after ERC20VotesUpgradeable, see _update.
contract TermToken is Initializable, ContextUpgradeable, ERC20Upgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, ERC20PausableUpgradeable, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Slots 0-4 held the state of the LayerZero OFTCore parent (Ownable, OAppCore,
    // OAppPreCrimeSimulator, OAppOptionsType3, OFTCore) before OFT support was removed. They are kept
    // with the same order and types so that the live proxy's burningNotPaused and mintingNotPaused
    // stay packed into slot 4 after msgInspector. Do not remove, reorder, retype or reuse them: the
    // live proxy still holds its old owner address in slot 0.
    address private __deprecated_owner;
    mapping(uint32 => bytes32) private __deprecated_peers;
    address private __deprecated_preCrime;
    mapping(uint32 => mapping(uint16 => bytes)) private __deprecated_enforcedOptions;
    address private __deprecated_msgInspector;

    bool public burningNotPaused;
    bool public mintingNotPaused;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address pauser, address upgrader, uint256 tokenMintSupply, address mintAddress)
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

        _mint(mintAddress, tokenMintSupply);
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
     * @dev public mint function
     * @param amount amount of tokens to mint
     */
    function mint(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        require(mintingNotPaused, "Minting Paused");
        _mint(msg.sender , amount);
        return amount;
    }

    /**
     * @dev public burn function
     * @param amount amount of tokens to burn
     */
    function burn(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256)  {
        require(burningNotPaused, "Burning Paused");
        _burn(msg.sender , amount);
        return amount;
    }

    //@dev pauses all transfers
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    //@dev unpauses all transfers
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
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
        // OR if triggered by an account with DEFAULT_ADMIN_ROLE
        require(!paused() || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "TermToken: token transfer while paused");

        // @dev Calls ERC20VotesUpgradeable._update instead of super._update so that the
        // whenNotPaused check in ERC20PausableUpgradeable._update is skipped and the admin
        // exemption above takes effect. Because ERC20PausableUpgradeable is listed after
        // ERC20VotesUpgradeable, the super._update inside ERC20VotesUpgradeable resolves
        // directly to ERC20Upgradeable. Reordering the inheritance list re-enables whenNotPaused.
        ERC20VotesUpgradeable._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    function unpauseMinting() external onlyRole(PAUSER_ROLE) {
        mintingNotPaused = true;
    }

    function pauseMinting() external onlyRole(PAUSER_ROLE) {
        mintingNotPaused = false;
    }

    function unpauseBurning() external onlyRole(PAUSER_ROLE) {
        burningNotPaused = true;
    }

    function pauseBurning() external onlyRole(PAUSER_ROLE) {
        burningNotPaused = false;
    }
}
