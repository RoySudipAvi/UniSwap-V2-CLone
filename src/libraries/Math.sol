//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library Math {
    uint8 public constant SHIFT_BY = 112;

    function encode(uint112 _input) internal pure returns (uint224 _output) {
        return uint224(_input) << SHIFT_BY;
    }

    function divide(uint224 _input1, uint112 _input2) internal pure returns (uint224 _output) {
        return _input1 / _input2;
    }
}
