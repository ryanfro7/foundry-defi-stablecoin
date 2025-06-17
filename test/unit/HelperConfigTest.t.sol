// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {console} from "forge-std/console.sol";

contract HelperConfigTest is Test {
    function testBasic() public {
        vm.chainId(31337);
        HelperConfig helperConfig = new HelperConfig();
        assertTrue(address(helperConfig) != address(0));
    }

    function testGetActiveNetworkConfigAnvil() public {
        vm.chainId(31337);
        HelperConfig helperConfig = new HelperConfig();
        (,, address weth,,) = helperConfig.activeNetworkConfig();
        assertTrue(weth != address(0));
    }

    function testGetSepoliaConfigDirectly() public {
        uint256 fakePrivateKey = 0x123456789;
        vm.setEnv("PRIVATE_KEY", vm.toString(fakePrivateKey));

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getSepoliaEthConfig();

        assertEq(config.wethUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        assertEq(config.wbtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
        assertEq(config.weth, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81);
        assertEq(config.wbtc, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    }

    function testUnsupportedChain() public {
        vm.chainId(1);
        vm.expectRevert("Unsupported network");
        new HelperConfig();
    }

    function testAnvilConfigCaching() public {
        vm.chainId(31337);
        HelperConfig helperConfig = new HelperConfig();

        // First call should create mocks
        HelperConfig.NetworkConfig memory config1 = helperConfig.getorCreateAnvilEthConfig();

        // Second call should return cached version
        HelperConfig.NetworkConfig memory config2 = helperConfig.getorCreateAnvilEthConfig();

        // Should be same addresses (cached)
        assertEq(config1.wethUsdPriceFeed, config2.wethUsdPriceFeed);
        assertEq(config1.wbtcUsdPriceFeed, config2.wbtcUsdPriceFeed);
        assertEq(config1.weth, config2.weth);
        assertEq(config1.wbtc, config2.wbtc);
    }

    function testDefaultAnvilKey() public {
        vm.chainId(31337);
        HelperConfig helperConfig = new HelperConfig();
        (,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        assertEq(deployerKey, 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
    }

    function testAnvilConfigFromScratch() public {
        vm.chainId(31337);

        // Create a fresh HelperConfig
        HelperConfig helperConfig = new HelperConfig();

        // The constructor should have already set activeNetworkConfig
        // Let's check what's actually in it
        (address wethFeed, address btcFeed, address weth, address btc, uint256 key) = helperConfig.activeNetworkConfig();

        console.log("wethFeed:", wethFeed);
        console.log("btcFeed:", btcFeed);
        console.log("weth:", weth);
        console.log("btc:", btc);
        console.log("key:", key);

        // Now call getorCreateAnvilEthConfig directly
        HelperConfig.NetworkConfig memory directConfig = helperConfig.getorCreateAnvilEthConfig();

        console.log("direct wethFeed:", directConfig.wethUsdPriceFeed);
    }

    function testSepoliaConfigFromConstructor() public {
        uint256 fakePrivateKey = 0x123456789;
        vm.setEnv("PRIVATE_KEY", vm.toString(fakePrivateKey));

        vm.chainId(11155111);
        HelperConfig helperConfig = new HelperConfig();

        (address wethFeed,,,,) = helperConfig.activeNetworkConfig();
        assertEq(wethFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
    }
}
