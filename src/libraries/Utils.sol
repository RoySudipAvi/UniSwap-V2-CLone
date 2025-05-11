//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Errors} from "src/interfaces/Errors.sol";
import {IPair} from "src/interfaces/IPair.sol";
import {console} from "forge-std/console.sol";

library Utils {
    bytes32 public constant BYTECODE_HASH = 0xac21dd428fadb61dc76376caeac99f9bea0a60c43a5b6e91d7d0555b429e2b1b;

    function getPairAddress(address _factory, address _tokenA, address _tokenB)
        internal
        pure
        returns (address _pairAddress)
    {
        (address _token0, address _token1) = sortTokens(_tokenA, _tokenB);

        bytes32 _hash = keccak256(
            abi.encodePacked(bytes1(0xff), _factory, keccak256(abi.encodePacked(_token0, _token1)), BYTECODE_HASH)
        );
        _pairAddress = address(uint160(uint256(_hash)));
    }

    function sortTokens(address _tokenA, address _tokenB) internal pure returns (address _token0, address _token1) {
        require(_tokenA != _tokenB, Errors.IdenticalTokenAddress());
        (_token0, _token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(_token0 != address(0), Errors.InvalidAddress());
    }

    function calculateTokenAmount(uint256 _amountTokenA, uint256 _reserveTokenA, uint256 _reserveTokenB)
        internal
        pure
        returns (uint256 _amountTokenB)
    {
        require(_amountTokenA > 0, Errors.InsufficientAmount());
        require(_reserveTokenA > 0 && _reserveTokenB > 0, Errors.InsufficientLiquidity());
        require(_reserveTokenB <= type(uint256).max / _amountTokenA, Errors.Overflow());
        _amountTokenB = (_reserveTokenB * _amountTokenA) / _reserveTokenA;
    }

    function getReserves(address _factory, address _tokenA, address _tokenB)
        internal
        view
        returns (uint256 _reserveTokenA, uint256 _reserveTokenB)
    {
        (address _token0,) = sortTokens(_tokenA, _tokenB);
        (uint256 _reserveToken0, uint256 _reserveToken1,) =
            IPair(getPairAddress(_factory, _tokenA, _tokenB)).getReserves();

        (_reserveTokenA, _reserveTokenB) =
            _tokenA == _token0 ? (_reserveToken0, _reserveToken1) : (_reserveToken1, _reserveToken0);
    }

    function getAmountOut(uint256 _reserveIn, uint256 _reserveOut, uint256 _amountIn)
        internal
        pure
        returns (uint256 _amountOut)
    {
        require(_amountIn > 0, Errors.InsufficientAmount());
        require(_reserveIn > 0 && _reserveOut > 0, Errors.InsufficientLiquidity());
        require(_reserveOut <= type(uint256).max / _amountIn, Errors.Overflow());
        require((_reserveOut * _amountIn) <= type(uint256).max / 997);
        require(_reserveIn <= type(uint256).max / 1000);
        require(_amountIn <= type(uint256).max / 997);
        require(_reserveIn * 1000 <= type(uint256).max / (_amountIn * 997));

        uint256 _numerator = _reserveOut * _amountIn * 997;
        uint256 _denominator = (_reserveIn * 1000) + (_amountIn * 997);
        _amountOut = _numerator / _denominator;
    }

    function getAmountIn(uint256 _reserveIn, uint256 _reserveOut, uint256 _amountOut)
        internal
        pure
        returns (uint256 _amountIn)
    {
        require(_amountOut > 0, Errors.InsufficientAmount());
        require(_reserveIn > 0 && _reserveOut > 0, Errors.InsufficientLiquidity());
        require(_amountOut <= type(uint256).max / 1000, Errors.Overflow());
        require(_reserveIn <= type(uint256).max / (_amountOut * 1000), Errors.Overflow());
        require((_reserveOut - _amountOut) <= type(uint256).max / 997, Errors.Overflow());

        uint256 _numerator = _reserveIn * _amountOut * 1000;
        uint256 _denominator = (_reserveOut - _amountOut) * 997;
        _amountIn = _numerator / _denominator;
        console.log("num: ", _numerator);
        console.log("den: ", _denominator);
        console.log("amountIn: ", _amountIn);
    }

    function getAmountsOut(address _factory, uint256 _amountIn, address[] memory _path)
        internal
        view
        returns (uint256[] memory _amounts)
    {
        require(_path.length >= 2, Errors.InvalidAddressPath());
        _amounts = new uint256[](_path.length);
        _amounts[0] = _amountIn;
        for (uint256 _i; _i < _path.length - 1; _i++) {
            (uint256 _reserveIn, uint256 _reserveOut) = getReserves(_factory, _path[_i], _path[_i + 1]);
            _amounts[_i + 1] = getAmountOut(_reserveIn, _reserveOut, _amounts[_i]);
        }
    }

    function getAmountsIn(address _factory, uint256 _amountOut, address[] memory _path)
        internal
        view
        returns (uint256[] memory _amounts)
    {
        require(_path.length > 2, Errors.InvalidAddressPath());
        _amounts = new uint256[](_path.length);
        _amounts[_amounts.length - 1] = _amountOut;
        for (uint256 _i = _amounts.length - 1; _i > 0; _i--) {
            console.log(_i);
            (uint256 _reserveIn, uint256 _reserveOut) = getReserves(_factory, _path[_i - 1], _path[_i]);

            _amounts[_i - 1] = getAmountIn(_reserveIn, _reserveOut, _amounts[_i]);
        }
    }
}
