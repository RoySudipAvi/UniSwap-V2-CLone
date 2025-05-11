//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Factory} from "src/contracts/Factory.sol";
import {Utils, Errors} from "src/libraries/Utils.sol";
import {Pair, IPair} from "src/contracts/Pair.sol";

contract FactoryTest is Test {
    Factory private s_factory;

    event PairCreated(address indexed _tokenA, address indexed _tokenB, address indexed _pairAddress);

    function setUp() external {
        s_factory = new Factory();
    }

    function testRevertIfIdenticalTokens() external {
        address _tokenA = address(4);
        vm.expectRevert(Errors.IdenticalTokenAddress.selector);
        s_factory.createPair(_tokenA, _tokenA);
    }

    function testRevertIfTokenAddressZero() external {
        address _tokenA = address(4);
        address _tokenB = address(0);
        vm.expectRevert(Errors.InvalidAddress.selector);
        s_factory.createPair(_tokenA, _tokenB);
    }

    function testPairAddress(address _tokenA, address _tokenB) external {
        vm.assume(_tokenA != _tokenB);
        vm.assume(_tokenA != address(0));
        vm.assume(_tokenB != address(0));
        s_factory.createPair(_tokenA, _tokenB);
        address _pairAddress = Utils.getPairAddress(address(s_factory), _tokenA, _tokenB);
        assertEq(s_factory.getPairAddress(_tokenA, _tokenB), _pairAddress);
    }

    function testEmitEvenOnPairCreation(address _tokenA, address _tokenB) external {
        vm.assume(_tokenA != _tokenB);
        vm.assume(_tokenA != address(0));
        vm.assume(_tokenB != address(0));
        (address _token0, address _token1) = Utils.sortTokens(_tokenA, _tokenB);
        address _pairAddress = Utils.getPairAddress(address(s_factory), _tokenA, _tokenB);
        vm.expectEmit(true, true, true, false);
        emit PairCreated(_token0, _token1, _pairAddress);
        s_factory.createPair(_tokenA, _tokenB);
    }
}
