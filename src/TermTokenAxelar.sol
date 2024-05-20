// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { InterchainTokenStandard } from '@axelar-network/interchain-token-service/contracts/interchain-token/InterchainTokenStandard.sol';


/// @custom:security-contact devops@termfinance.io
contract TermToken is Initializable, InterchainTokenStandard, ERC20Upgradeable, ERC20PausableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant INTERCHAIN_TOKEN_SERVICE_ROLE = keccak256("INTERCHAIN_TOKEN_SERVICE_ROLE");
    address internal termInterchainTokenService;
    bytes32 internal tokenId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address pauser, address upgrader, address termInterchainTokenService_)
        initializer public
    {
        __ERC20_init("Term Finance", "TERM");
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("Term Finance");
        __ERC20Votes_init();
        __UUPSUpgradeable_init();

        termInterchainTokenService = termInterchainTokenService_;

        require(defaultAdmin != address(0), "TermTokenAxelar: defaultAdmin is the zero address");
        require(pauser != address(0), "TermTokenAxelar: pauser is the zero address");
        require(upgrader != address(0), "TermTokenAxelar: upgrader is the zero address");
        require(termInterchainTokenService_ != address(0), "TermTokenAxelar: termInterchainTokenService_ is the zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(INTERCHAIN_TOKEN_SERVICE_ROLE, termInterchainTokenService_);
    }

    function setTokenId(bytes32 tokenId_) external onlyRole(PAUSER_ROLE) {
        tokenId = tokenId_;
    }

    /**
     * @notice Function to mint new tokens.
     * @dev Can only be called by the minter address.
     * @param account The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address account, uint256 amount) external onlyRole(INTERCHAIN_TOKEN_SERVICE_ROLE) {
        _mint(account, amount);
    }

    /**
     * @notice Function to burn tokens.
     * @dev Can only be called by the minter address.
     * @param account The address that will have its tokens burnt.
     * @param amount The amount of tokens to burn.
     */
    function burn(address account, uint256 amount) external onlyRole(INTERCHAIN_TOKEN_SERVICE_ROLE) {
        _burn(account, amount);
    }

     /**
     * @notice Returns the interchain token service
     * @return address The interchain token service contract
     */
    function interchainTokenService() public view override returns (address) {
        return termInterchainTokenService;
    }

    /**
     * @notice Returns the tokenId for this token.
     * @return bytes32 The token manager contract.
     */
    function interchainTokenId() public view override returns (bytes32) {
        return tokenId;
    }

     /**
     * @notice A method to be overwritten that will decrease the allowance of the `spender` from `sender` by `amount`.
     * @dev Needs to be overwritten. This provides flexibility for the choice of ERC20 implementation used. Must revert if allowance is not sufficient.
     */
    function _spendAllowance(address sender, address spender, uint256 amount) internal override (ERC20Upgradeable, InterchainTokenStandard) {
        uint256 _allowance = allowance(sender, spender);

        if (_allowance != type(uint256).max) {
            _approve(sender, spender, _allowance - amount);
        }
    }



    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

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
