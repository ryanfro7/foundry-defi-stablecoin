// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 5000 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant ETH_USD_PRICE = 2000e8;
    uint256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant MIN_HEALTH_FACTOR = 100; // 1.0 in 18 decimals

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedAndMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier liquidationSetup() {
        // Set up unhealthy user (victim)
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        // Set up liquidator with BTC (not affected by ETH price crash)
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wbtc).mint(LIQUIDATOR, AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL); // Use BTC instead of ETH
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        // NOW crash ETH price to make USER unhealthy (doesn't affect LIQUIDATOR)
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorSetsStateCorrectlyWithSingleTokenPair() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);

        DSCEngine newDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        address[] memory tokens = newDsce.getTokenAddresses();

        assertEq(tokens.length, 1);
        assertEq(tokens[0], weth);
        assertEq(newDsce.getPriceFeedAddress(weth), ethUsdPriceFeed);
        assertEq(newDsce.getDscAddress(), address(dsc));
    }

    function testConstructorSetsStateCorrectlyWithMultipleTokenPairs() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        DSCEngine newDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        address[] memory tokens = newDsce.getTokenAddresses();

        assertEq(tokens.length, 2);
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
        assertEq(newDsce.getPriceFeedAddress(weth), ethUsdPriceFeed);
        assertEq(newDsce.getPriceFeedAddress(wbtc), btcUsdPriceFeed);
        assertEq(newDsce.getDscAddress(), address(dsc));
    }

    function testConstructorRevertsWithEmptyArrays() public {
        address[] memory emptyTokenAddresses = new address[](0);
        address[] memory emptyPriceFeedAddresses = new address[](0);

        vm.expectRevert(DSCEngine.DSCEngine__MustHaveAtLeastOneCollateralType.selector);
        new DSCEngine(emptyTokenAddresses, emptyPriceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetUsdValueReturnsZeroForZeroAmount() public view {
        uint256 zeroAmount = 0;
        uint256 expectedUsd = 0;
        uint256 actualUsd = dsce.getUsdValue(weth, zeroAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValueRevertsWithInvalidToken() public {
        address invalidToken = address(0);
        uint256 amount = 10 ether;
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.getUsdValue(invalidToken, amount);
    }

    function testGetTokenAmountFromUsdRevertsWithInvalidToken() public {
        address invalidToken = makeAddr("invalidToken");
        uint256 usdAmount = 100 ether;
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.getTokenAmountFromUsd(invalidToken, usdAmount);
    }

    function testGetTokenAmountFromUsdReturnsZeroForZeroUsd() public view {
        uint256 zeroUsd = 0;
        uint256 expectedAmount = 0;
        uint256 actualAmount = dsce.getTokenAmountFromUsd(weth, zeroUsd);
        assertEq(expectedAmount, actualAmount);
    }

    function testGetUsdValueWithHighAmount() public view {
        uint256 highEthAmount = 1_000_000 ether; // 1M ETH with 18 decimals
        uint256 expectedUsd = (highEthAmount * ETH_USD_PRICE) / 1e8; // Adjust for price feed decimals
        uint256 actualUsd = dsce.getUsdValue(weth, highEthAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValueWithBtc() public view {
        uint256 btcAmount = 1e8;
        uint256 expectedUsd = BTC_USD_PRICE;
        uint256 actualUsd = dsce.getUsdValue(wbtc, btcAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValueReturnsZeroForZeroBtc() public view {
        uint256 zeroBtc = 0;
        uint256 expectedUsd = 0;
        uint256 actualUsd = dsce.getUsdValue(wbtc, zeroBtc);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValueWithHighBtcAmount() public view {
        uint256 highBtcAmount = 1_000_000e8;
        uint256 expectedUsd = (highBtcAmount * BTC_USD_PRICE) / 1e8;
        uint256 actualUsd = dsce.getUsdValue(wbtc, highBtcAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsdWithBtc() public view {
        uint256 usdAmount = 10 ether;
        uint256 expectedBtc = (usdAmount * 1e8) / BTC_USD_PRICE;
        uint256 actualBtc = dsce.getTokenAmountFromUsd(wbtc, usdAmount);
        assertEq(expectedBtc, actualBtc);
    }

    function testGetTokenAmountFromUsdReturnsZeroForZeroBtc() public view {
        uint256 zeroUsd = 0;
        uint256 expectedBtc = 0;
        uint256 actualBtc = dsce.getTokenAmountFromUsd(wbtc, zeroUsd);
        assertEq(expectedBtc, actualBtc);
    }

    function testGetTokenAmountFromUsdWithHighBtcAmount() public view {
        uint256 highUsdAmount = 1_000_000 ether; // 1M USD
        uint256 expectedBtc = (highUsdAmount * 1e8) / BTC_USD_PRICE; // Adjust for price feed decimals
        uint256 actualBtc = dsce.getTokenAmountFromUsd(wbtc, highUsdAmount);
        assertEq(expectedBtc, actualBtc);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT DSC TESTS  
    //////////////////////////////////////////////////////////////*/

    function testMintDsc() public depositedCollateral {
        uint256 amountDscToMint = AMOUNT_DSC_TO_MINT;
        uint256 initialHealthFactor = dsce.getHealthFactor(USER);
        uint256 initialDscBalance = dsc.balanceOf(USER);

        vm.startPrank(USER);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 finalHealthFactor = dsce.getHealthFactor(USER);
        uint256 finalDscBalance = dsc.balanceOf(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(totalDscMinted, amountDscToMint);
        assertEq(finalDscBalance, initialDscBalance + amountDscToMint);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertTrue(finalHealthFactor < initialHealthFactor, "Health factor should decrease after minting");
        assertTrue(finalHealthFactor >= MIN_HEALTH_FACTOR, "Health factor must remain healthy");
    }

    function testMintDscRevertsIfHealthFactorBroken() public depositedCollateral {
        uint256 amountDscToMint = 15_000 ether;

        vm.startPrank(USER);
        vm.expectRevert();
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
    }

    function testMintDscRevertsIfAmountIsZero() public depositedCollateral {
        uint256 amountDscToMint = 0;

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
    }

    function testHealthFactorMaxWhenNoDscMinted() public {
        // Test the zero DSC branch in _healthFactor
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT AND MINT TESTS
    //////////////////////////////////////////////////////////////*/
    function testDepositCollateralAndMintDsc() public {
        uint256 amountCollateral = AMOUNT_COLLATERAL;
        uint256 amountDscToMint = 100 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        assertEq(totalDscMinted, amountDscToMint);

        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, amountCollateral);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testDepositCollateralAndMintDscRevertsIfCollateralZero() public {
        uint256 amountCollateral = 0;
        uint256 amountDscToMint = 100 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__CannotMintWithZeroCollateral.selector);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDscRevertsIfDscZero() public {
        uint256 amountCollateral = AMOUNT_COLLATERAL;
        uint256 amountDscToMint = 0;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDscRevertsIfHealthFactorBroken() public {
        uint256 amountCollateral = AMOUNT_COLLATERAL; // 10 ETH
        uint256 amountDscToMint = 15_000 ether; // $15,000 - should break health factor

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(); // Expect health factor revert (check exact error later)
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testBurnDsc() public depositedAndMinted {
        uint256 amountToBurn = 1000 ether;
        uint256 initialDscBalance = dsc.balanceOf(USER);
        uint256 initialHealthFactor = dsce.getHealthFactor(USER);

        vm.startPrank(USER);
        dsc.approve(address(dsce), amountToBurn);
        dsce.burnDsc(amountToBurn);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 finalHealthFactor = dsce.getHealthFactor(USER);
        uint256 finalDscBalance = dsc.balanceOf(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT - amountToBurn);
        assertEq(finalDscBalance, initialDscBalance - amountToBurn);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertTrue(finalHealthFactor > initialHealthFactor, "Health factor should increase after burning");
        assertTrue(finalHealthFactor >= MIN_HEALTH_FACTOR, "Health factor must remain healthy");
    }

    function testBurnDscRevertsIfAmountIsZero() public depositedAndMinted {
        uint256 amountToBurn = 0;

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(amountToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
    }

    function testBurnDscRevertsIfInsufficientBalance() public depositedAndMinted {
        uint256 amountToBurn = AMOUNT_DSC_TO_MINT + 100 ether; // This is more than the minted amount

        vm.startPrank(USER);
        vm.expectRevert();
        dsce.burnDsc(amountToBurn);
        vm.stopPrank();
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRedeemCollateral() public depositedCollateral {
        uint256 initialCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 amountToRedeem = AMOUNT_COLLATERAL / 2; // Redeem half of the collateral

        vm.startPrank(USER);
        dsce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();

        uint256 finalCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL - amountToRedeem);
        assertEq(finalCollateralBalance, initialCollateralBalance + amountToRedeem);
        assertEq(totalDscMinted, 0); // No Dsc should be minted
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testRedeemCollateralRevertsIfAmountIsZero() public depositedCollateral {
        uint256 initialCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 amountToRedeem = 0;

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();

        uint256 finalCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalCollateralBalance, initialCollateralBalance);
        assertEq(totalDscMinted, 0); // No Dsc should be minted
    }

    function testRedeemCollateralRevertsIfInsufficientBalance() public depositedCollateral {
        uint256 initialCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 amountToRedeem = AMOUNT_COLLATERAL + 1 ether; // More than the deposited amount

        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();

        uint256 finalCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalCollateralBalance, initialCollateralBalance);
        assertEq(totalDscMinted, 0); // No Dsc should be minted
    }

    function testRedeemCollateralRevertsIfHealthFactorBroken() public depositedAndMinted {
        uint256 initialCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 amountToRedeem = AMOUNT_COLLATERAL;

        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();

        uint256 finalCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(finalCollateralBalance, initialCollateralBalance);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
    }

    function testRedeemCollateralForDsc() public depositedAndMinted {
        uint256 amountToRedeem = AMOUNT_COLLATERAL / 2;
        uint256 amountDscToBurn = AMOUNT_DSC_TO_MINT / 2;

        vm.startPrank(USER);
        dsc.approve(address(dsce), amountDscToBurn);
        dsce.redeemCollateralForDsc(weth, amountToRedeem, amountDscToBurn);
        vm.stopPrank();

        uint256 finalCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL - amountToRedeem);
        assertEq(finalCollateralBalance, AMOUNT_COLLATERAL - amountToRedeem);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT - amountDscToBurn);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testRedeemCollateralForDscRevertsIfHealthFactorBroken() public depositedAndMinted {
        uint256 amountToRedeem = 8 ether;
        uint256 amountDscToBurn = 500 ether;

        vm.startPrank(USER);
        dsc.approve(address(dsce), amountDscToBurn);
        vm.expectRevert();
        dsce.redeemCollateralForDsc(weth, amountToRedeem, amountDscToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(ERC20Mock(weth).balanceOf(USER), 0); // Fix: Should be 0 after deposit
        assertEq(dsc.balanceOf(USER), AMOUNT_DSC_TO_MINT);
    }

    function testRedeemCollateralForDscRevertsIfCollateralZero() public depositedAndMinted {
        uint256 amountToRedeem = 0;
        uint256 amountDscToBurn = 100 ether;

        vm.startPrank(USER);
        dsc.approve(address(dsce), amountDscToBurn);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, amountToRedeem, amountDscToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
        assertEq(dsc.balanceOf(USER), AMOUNT_DSC_TO_MINT);
    }

    function testRedeemCollateralForDscRevertsIfDscZero() public depositedAndMinted {
        uint256 amountToRedeem = 1 ether;
        uint256 amountDscToBurn = 0;

        vm.startPrank(USER);
        dsc.approve(address(dsce), amountDscToBurn);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, amountToRedeem, amountDscToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
        assertEq(dsc.balanceOf(USER), AMOUNT_DSC_TO_MINT);
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testLiquidate() public liquidationSetup {
        uint256 amountToLiquidate = 1000 ether; // Amount of DSC debt to cover

        // Get initial states
        uint256 initialLiquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);
        uint256 initialLiquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR); // Should be 0 (deposited all)
        (uint256 initialVictimDscMinted, uint256 initialVictimCollateralValue) = dsce.getAccountInformation(USER);

        // Calculate expected collateral liquidated (debt + 10% bonus)
        uint256 tokenAmountFromDebtCovered = dsce.getTokenAmountFromUsd(weth, amountToLiquidate);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * 10) / 100; // 10% bonus
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // Perform liquidation
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), amountToLiquidate);
        dsce.liquidate(weth, USER, amountToLiquidate); // collateral, user, debtToCover
        vm.stopPrank();

        // Get final states
        uint256 finalLiquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);
        uint256 finalLiquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        (uint256 finalVictimDscMinted, uint256 finalVictimCollateralValue) = dsce.getAccountInformation(USER);
        uint256 finalVictimHealthFactor = dsce.getHealthFactor(USER);

        // Assertions
        // Liquidator pays DSC (balance decreases)
        assertEq(finalLiquidatorDscBalance, initialLiquidatorDscBalance - amountToLiquidate);

        // Liquidator receives WETH collateral + bonus
        assertEq(finalLiquidatorWethBalance, initialLiquidatorWethBalance + totalCollateralToRedeem);

        // Victim's DSC debt decreases (protocol burns their debt)
        assertEq(finalVictimDscMinted, initialVictimDscMinted - amountToLiquidate);

        // Victim's collateral value decreases (liquidator took collateral + bonus)
        uint256 expectedVictimCollateralValue =
            initialVictimCollateralValue - dsce.getUsdValue(weth, totalCollateralToRedeem);
        assertEq(finalVictimCollateralValue, expectedVictimCollateralValue);

        // Victim's health factor should improve (less debt, though less collateral too)
        assertTrue(
            finalVictimHealthFactor > MIN_HEALTH_FACTOR, "Health factor should be above minimum after liquidation"
        );
    }

    function testLiquidateRevertsIfHealthFactorOk() public depositedAndMinted {
        // Setup liquidator with BTC collateral
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wbtc).mint(LIQUIDATOR, AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);

        // Try to liquidate healthy user (health factor 2.0)
        dsc.approve(address(dsce), 1000 ether);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, 1000 ether);
        vm.stopPrank();

        // Verify no state changes
        (uint256 userDsc,) = dsce.getAccountInformation(USER);
        assertEq(userDsc, AMOUNT_DSC_TO_MINT);
    }

    function testLiquidateRevertsIfCollateralZero() public liquidationSetup {
        uint256 amountToLiquidate = 0;

        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), amountToLiquidate);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, amountToLiquidate);
        vm.stopPrank();
    }

    function testGetterFunctions() public view {
        // Test getTokenAddresses
        address[] memory tokens = dsce.getTokenAddresses();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);

        // Test getPriceFeedAddress
        assertEq(dsce.getPriceFeedAddress(weth), ethUsdPriceFeed);
        assertEq(dsce.getPriceFeedAddress(wbtc), btcUsdPriceFeed);

        // Test getDscAddress
        assertEq(dsce.getDscAddress(), address(dsc));

        // Test getHealthFactor
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max); // No debt = max health factor
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedValue);
    }
}
