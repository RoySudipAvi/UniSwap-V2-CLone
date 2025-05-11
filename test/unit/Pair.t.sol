//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Pair} from "src/contracts/Pair.sol";

contract PairTest is Test {
    Pair private s_pair;

    function setUp() external {
        s_pair = new Pair();
    }

    function testGetBytecodeHash() external {
        console.logBytes32(keccak256(type(Pair).creationCode));
    }
}
