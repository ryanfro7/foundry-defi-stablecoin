// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.prank(owner);
        dsc = new DecentralizedStableCoin();
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsCorrectOwner() public view {
        assertEq(dsc.owner(), owner);
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.decimals(), 18);
        assertEq(dsc.totalSupply(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMintSuccess() public {
        uint256 amount = 100e18;

        vm.prank(owner);
        bool success = dsc.mint(user, amount);

        assertTrue(success);
        assertEq(dsc.balanceOf(user), amount);
        assertEq(dsc.totalSupply(), amount);
    }

    function testMintRevertsIfNotOwner() public {
        uint256 amount = 100e18;

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(user, amount);

        assertEq(dsc.balanceOf(user), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    function testMintZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.mint(user, 0);

        assertEq(dsc.balanceOf(user), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    function testMintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 100e18);
    }

    function testMintMultipleTimes() public {
        vm.startPrank(owner);

        dsc.mint(user, 50e18);
        dsc.mint(user, 50e18);

        vm.stopPrank();

        assertEq(dsc.balanceOf(user), 100e18);
        assertEq(dsc.totalSupply(), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                              BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function testBurnSuccess() public {
        uint256 mintAmount = 100e18;
        uint256 burnAmount = 30e18;

        vm.startPrank(owner);
        dsc.mint(owner, mintAmount);
        dsc.burn(burnAmount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(owner), mintAmount - burnAmount);
        assertEq(dsc.totalSupply(), mintAmount - burnAmount);
    }

    function testBurnRevertsIfNotOwner() public {
        uint256 amount = 50e18;

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.burn(amount);
    }

    function testBurnZeroAmount() public {
        vm.startPrank(owner);
        dsc.mint(owner, 100e18);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();

        assertEq(dsc.balanceOf(owner), 100e18);
        assertEq(dsc.totalSupply(), 100e18);
    }

    function testBurnMoreThanBalance() public {
        uint256 mintAmount = 50e18;
        uint256 burnAmount = 100e18;

        vm.startPrank(owner);
        dsc.mint(owner, mintAmount);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(burnAmount);
        vm.stopPrank();
    }

    function testBurnEntireSupply() public {
        uint256 amount = 100e18;

        vm.startPrank(owner);
        dsc.mint(owner, amount);
        dsc.burn(amount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnershipTransfer() public {
        vm.prank(owner);
        dsc.transferOwnership(user);

        assertEq(dsc.owner(), user);

        // New owner can mint
        vm.prank(user);
        bool success = dsc.mint(stranger, 100e18);
        assertTrue(success);

        // Old owner cannot mint
        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(stranger, 100e18);
    }

    function testRenounceOwnership() public {
        vm.prank(owner);
        dsc.renounceOwnership();

        assertEq(dsc.owner(), address(0));

        // No one can mint after renouncing
        vm.prank(owner);
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(user, 100e18);
    }
}
