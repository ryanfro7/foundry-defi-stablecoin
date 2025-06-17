//SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author Ryan M. Froelich
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1 USD peg.
 *
 * This stablecoin has the properties of being:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governace, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should aways be "overcollateralized." At no point, should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stable Coin (DSC) system. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice The contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BadPriceFeedAddress();
    error DSCEngine__MustHaveAtLeastOneCollateralType();
    error DSCEngine__CannotMintWithZeroCollateral();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus for the liquidator

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc; // The DSC token that is minted and burned

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        if (tokenAddresses.length == 0) {
            revert DSCEngine__MustHaveAtLeastOneCollateralType();
        }
        // For example ETH/USD, BTC/USD, MKR/USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of callateral to deposit.
     * @param amountDscToMint The amount of Decentralized Stable Coin (DSC) to mint.
     * @notice This function will deposit your collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        if (amountCollateral == 0) {
            revert DSCEngine__CannotMintWithZeroCollateral();
        }
        if (amountDscToMint == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }

        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
    *@notice follows CEI pattern
    *@param tokenCollateralAddress The address of the collateral token to deposit as collateral.
    *@param amountCollateral The amount of collateral to deposit.
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem.
     * @param amountCollateral The amount of collateral to redeem.
     * @param amountDscToBurn The amount of DSC to burn.
     * This function burns DSC and redeems underlying collateral in one transaction.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral already checks health factor
    }

    // in order to redeem collateral:
    //1. health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @notice follows CEI pattern
    * @param amountDscToMint The amount of Decentralized Stable Coin (DSC) to mint.d
    * @notice They must have more collateral value than the minimum threshold to mint DSC.
    */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // If we do start nearing undercollateralization, we need someone to liquidate positions.abi

    // $100 ETH backing $50 DSC
    // $20 ETH backing $50 DSC <-- DSC isn't worth $1!!!

    // $75 backing $50 DSC
    // liquidator takes $75 backing and burns off the $50 DSC

    // If someone is almost undercollateralized, we will pay you to liquidate them.

    /**
     *
     * @param collateral The erc20 collateral address to liquidate from the user.
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR.
     * @param debtToCover The amount of DSC you want to burn to improve the user's health factor.
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidataion bonus for taking the user's funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be about to incenitvize the liquidators.
     * For example, if the price of the collateral plummeted before anyoung could be liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions pattern.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // 1. Need to check health factor of the user.
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // 2. We want to burn their DSC "debt" and take their collateral.
        // Bad User: $140 ETH, $100 DSC
        //debtToCover = $100
        // $100 of DSC == ??? ETH?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // 3. And give them a 10% bonus
        // So we are geting the liquidator $110 of WETH for $100 of DSC
        // We should implement a feature to liquitdate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury.
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        // 4. Burn the DSC from the user.
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                    PRIVATE & INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Low-level internal function, DO NOT call unless the function callingit is checking for health factors being broken.
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     * Returns how close to liquidation the user is.
     * If a user goes below a health factor of 1, then they can get liquidated.
     */

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        // Check how much has been minted FIRST, before any math
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        // Only do math if totalDscMinted > 0
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
    // 1. Check health factor of the user (Do they have enough collateral?)
    // 2. Revert if they don't have enough collateral

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    /*//////////////////////////////////////////////////////////////
                    PUBLIC & EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        // price of ETH (token)
        // $/ETH ETH ??
        // $200 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to the prive, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getTokenAddresses() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeedAddress(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDscAddress() external view returns (address) {
        return address(i_dsc);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
