// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract MockV3AggregatorTest is Test {
    MockV3Aggregator mockPriceFeed;

    uint8 constant DECIMALS = 8;
    int256 constant INITIAL_PRICE = 2000e8;

    function setUp() public {
        mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructor() public view {
        assertEq(mockPriceFeed.decimals(), DECIMALS);
        assertEq(mockPriceFeed.latestAnswer(), INITIAL_PRICE);
        assertEq(mockPriceFeed.latestRound(), 1);
        assertTrue(mockPriceFeed.latestTimestamp() > 0);
        assertEq(mockPriceFeed.version(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        LATEST ROUND DATA TESTS
    //////////////////////////////////////////////////////////////*/

    function testLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mockPriceFeed.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
        assertEq(answeredInRound, roundId);
        assertEq(startedAt, updatedAt);
    }

    /*//////////////////////////////////////////////////////////////
                         UPDATE ANSWER TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateAnswer() public {
        int256 newPrice = 2500e8;
        uint256 initialRound = mockPriceFeed.latestRound();

        mockPriceFeed.updateAnswer(newPrice);

        assertEq(mockPriceFeed.latestAnswer(), newPrice);
        assertEq(mockPriceFeed.latestRound(), initialRound + 1);
        assertTrue(mockPriceFeed.latestTimestamp() > 0);

        assertEq(mockPriceFeed.getAnswer(initialRound + 1), newPrice);
        assertTrue(mockPriceFeed.getTimestamp(initialRound + 1) > 0);
    }

    function testUpdateAnswerMultipleTimes() public {
        int256 price1 = 2100e8;
        int256 price2 = 2200e8;
        int256 price3 = 2300e8;

        mockPriceFeed.updateAnswer(price1);
        mockPriceFeed.updateAnswer(price2);
        mockPriceFeed.updateAnswer(price3);

        assertEq(mockPriceFeed.latestAnswer(), price3);
        assertEq(mockPriceFeed.latestRound(), 4);

        assertEq(mockPriceFeed.getAnswer(2), price1);
        assertEq(mockPriceFeed.getAnswer(3), price2);
        assertEq(mockPriceFeed.getAnswer(4), price3);
    }

    /*//////////////////////////////////////////////////////////////
                      UPDATE ROUND DATA TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateRoundData() public {
        uint80 roundId = 5;
        int256 answer = 3000e8;
        uint256 timestamp = block.timestamp + 100;
        uint256 startedAt = block.timestamp + 50;

        mockPriceFeed.updateRoundData(roundId, answer, timestamp, startedAt);

        assertEq(mockPriceFeed.latestRound(), roundId);
        assertEq(mockPriceFeed.latestAnswer(), answer);
        assertEq(mockPriceFeed.latestTimestamp(), timestamp);
        assertEq(mockPriceFeed.getAnswer(roundId), answer);
        assertEq(mockPriceFeed.getTimestamp(roundId), timestamp);
    }

    function testUpdateRoundDataOverwritesPrevious() public {
        mockPriceFeed.updateRoundData(10, 2500e8, block.timestamp, block.timestamp);
        mockPriceFeed.updateRoundData(10, 2600e8, block.timestamp + 100, block.timestamp + 50);

        assertEq(mockPriceFeed.latestAnswer(), 2600e8);
        assertEq(mockPriceFeed.getAnswer(10), 2600e8);
    }

    /*//////////////////////////////////////////////////////////////
                        GET ROUND DATA TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetRoundData() public {
        uint80 targetRound = 3;
        int256 targetAnswer = 2750e8;
        uint256 targetTimestamp = block.timestamp + 200;
        uint256 targetStartedAt = block.timestamp + 100;

        mockPriceFeed.updateRoundData(targetRound, targetAnswer, targetTimestamp, targetStartedAt);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mockPriceFeed.getRoundData(targetRound);

        assertEq(roundId, targetRound);
        assertEq(answer, targetAnswer);
        assertEq(startedAt, targetStartedAt);
        assertEq(updatedAt, targetTimestamp);
        assertEq(answeredInRound, targetRound);
    }

    function testGetRoundDataNonExistentRound() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mockPriceFeed.getRoundData(999);

        assertEq(roundId, 999);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 999);
    }

    /*//////////////////////////////////////////////////////////////
                         DESCRIPTION TEST
    //////////////////////////////////////////////////////////////*/

    function testDescription() public view {
        string memory desc = mockPriceFeed.description();
        assertEq(desc, "v0.6/tests/MockV3Aggregator.sol");
    }

    /*//////////////////////////////////////////////////////////////
                           VERSION TEST
    //////////////////////////////////////////////////////////////*/

    function testVersion() public view {
        assertEq(mockPriceFeed.version(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                      INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetRoundDataAfterUpdate() public {
        int256 newPrice = 1800e8;
        mockPriceFeed.updateAnswer(newPrice);

        uint256 currentRound = mockPriceFeed.latestRound();
        (uint80 roundId, int256 answer,,,) = mockPriceFeed.getRoundData(uint80(currentRound));

        assertEq(roundId, currentRound);
        assertEq(answer, newPrice);
    }

    function testLatestRoundDataAfterCustomUpdate() public {
        mockPriceFeed.updateRoundData(20, 1500e8, block.timestamp, block.timestamp);

        (uint80 roundId, int256 answer,,,) = mockPriceFeed.latestRoundData();

        assertEq(roundId, 20);
        assertEq(answer, 1500e8);
    }
}
