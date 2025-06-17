// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator mockPriceFeed;
    uint8 constant DECIMALS = 8;
    int256 constant INITIAL_PRICE = 2000e8;

    function setUp() public {
        // Set a reasonable starting timestamp (like January 1, 2024)
        vm.warp(1704067200); // January 1, 2024 00:00:00 UTC
        mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                           SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testStaleCheckLatestRoundDataSuccess() public view {
        // Price feed is fresh (just created)
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockPriceFeed)));

        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
        assertEq(answeredInRound, 1);
    }

    function testStaleCheckWithRecentUpdate() public {
        // Update the price to ensure it's fresh
        mockPriceFeed.updateAnswer(2500e8);

        // Should not revert since price is fresh
        (uint80 roundId, int256 answer,,,) =
            OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockPriceFeed)));

        assertEq(roundId, 2); // Second round after update
        assertEq(answer, 2500e8);
    }

    /*//////////////////////////////////////////////////////////////
                           STALE PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testStaleCheckRevertsOnStalePrice() public {
        // Set current time to a safe value
        uint256 currentTime = block.timestamp;

        // Create stale timestamp (4 hours ago)
        uint256 staleTimestamp = currentTime - 4 hours;
        mockPriceFeed.updateRoundData(1, INITIAL_PRICE, staleTimestamp, staleTimestamp);

        // Should revert because price is stale
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockPriceFeed)));
    }

    function testStaleCheckExactlyAtTimeout() public {
        uint256 currentTime = block.timestamp;

        // Create timestamp exactly 3 hours + 1 second ago (just over threshold)
        uint256 staleTimestamp = currentTime - 3 hours - 1;
        mockPriceFeed.updateRoundData(1, INITIAL_PRICE, staleTimestamp, staleTimestamp);

        // Should revert because it's just over the 3 hour timeout
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockPriceFeed)));
    }

    function testStaleCheckJustUnderTimeout() public {
        uint256 currentTime = block.timestamp;

        // Create timestamp just under 3 hours ago (2 hours 59 minutes)
        uint256 almostStaleTimestamp = currentTime - 2 hours - 59 minutes;
        mockPriceFeed.updateRoundData(1, INITIAL_PRICE, almostStaleTimestamp, almostStaleTimestamp);

        // Should NOT revert because it's under the timeout
        (uint80 roundId, int256 answer,,,) =
            OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockPriceFeed)));

        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                           EDGE CASE TESTS  
    //////////////////////////////////////////////////////////////*/

    function testStaleCheckWithVeryOldPrice() public {
        uint256 currentTime = block.timestamp;

        // Very old timestamp (1 day ago)
        uint256 veryOldTimestamp = currentTime - 1 days;
        mockPriceFeed.updateRoundData(1, INITIAL_PRICE, veryOldTimestamp, veryOldTimestamp);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockPriceFeed)));
    }
}
