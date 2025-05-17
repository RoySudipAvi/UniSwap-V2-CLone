//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Utils, IPair, Errors} from "src/libraries/Utils.sol";
import {IFactory} from "src/interfaces/IFactory.sol";
import {SafeTransferLib} from "@solady/contracts/utils/SafeTransferLib.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract Router {
    using SafeTransferLib for address;

    address private immutable I_FACTORY;
    address private immutable I_WETH;

    modifier withinDeadline(uint256 _deadline) {
        require(_deadline >= block.timestamp, Errors.Expired());
        _;
    }

    constructor(address _factory, address _weth) {
        I_FACTORY = _factory;
        I_WETH = _weth;
    }

    function _addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin
    ) private returns (uint256 _amountTokenA, uint256 _amountTokenB) {
        if (IFactory(I_FACTORY).getPairAddress(_tokenA, _tokenB) == address(0)) {
            IFactory(I_FACTORY).createPair(_tokenA, _tokenB);
        }
        (uint256 _reserveTokenA, uint256 _reserveTokenB) = Utils.getReserves(I_FACTORY, _tokenA, _tokenB);
        if (_reserveTokenA == 0 && _reserveTokenB == 0) {
            _amountTokenA = _amountTokenADesired;
            _amountTokenB = _amountTokenBDesired;
        } else {
            uint256 _amountTokenBOptimal =
                Utils.calculateTokenAmount(_amountTokenADesired, _reserveTokenA, _reserveTokenB);
            if (_amountTokenBOptimal <= _amountTokenBDesired) {
                require(_amountTokenBOptimal >= _amountTokenBMin, Errors.InsufficientAmount());
                _amountTokenA = _amountTokenADesired;
                _amountTokenB = _amountTokenBOptimal;
            } else {
                uint256 _amountTokenAOptimal =
                    Utils.calculateTokenAmount(_amountTokenBDesired, _reserveTokenA, _reserveTokenB);
                assert(_amountTokenAOptimal <= _amountTokenADesired);
                require(_amountTokenAOptimal >= _amountTokenAMin, Errors.InsufficientAmount());
                _amountTokenA = _amountTokenAOptimal;
                _amountTokenB = _amountTokenADesired;
            }
        }
    }

    function _transferTokensAndMintLiquidity(
        address _pairAddress,
        address _tokenA,
        address _tokenB,
        uint256 _amountTokenA,
        uint256 _amountTokenB,
        address _to
    ) private returns (uint256 _liquidity) {
        if (_tokenB == I_WETH) {
            _tokenA.safeTransferFrom(msg.sender, _pairAddress, _amountTokenA);
            IWETH(I_WETH).deposit{value: _amountTokenB}();
            assert(IWETH(I_WETH).transfer(_pairAddress, _amountTokenB));
            _liquidity = IPair(_pairAddress).mint(_to);
        } else {
            console.log(
                "allowance in router: ",
                IERC20(_tokenA).allowance(msg.sender, address(this)),
                IERC20(_tokenB).allowance(msg.sender, address(this))
            );
            console.log("sender: ", msg.sender);
            console.log("actual amounts: ", _amountTokenA, _amountTokenB);
            _tokenA.safeTransferFrom(msg.sender, _pairAddress, _amountTokenA);
            _tokenB.safeTransferFrom(msg.sender, _pairAddress, _amountTokenB);

            _liquidity = IPair(_pairAddress).mint(_to);
        }
    }

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) {
        (_amountTokenA, _amountTokenB) = _addLiquidity(
            _tokenA, _tokenB, _amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin
        );

        address _pairAddress = Utils.getPairAddress(I_FACTORY, _tokenA, _tokenB);
        _liquidity = _transferTokensAndMintLiquidity(_pairAddress, _tokenA, _tokenB, _amountTokenA, _amountTokenB, _to);
    }

    function addLiquidityETH(
        address _tokenA,
        uint256 _amountTokenADesired,
        uint256 _amountETHDesired,
        uint256 _amountTokenAMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256 _amountTokenA, uint256 _amountETH, uint256 _liquidity) {
        (_amountTokenA, _amountETH) =
            _addLiquidity(_tokenA, I_WETH, _amountTokenADesired, _amountETHDesired, _amountTokenAMin, _amountETHMin);
        address _pairAddress = Utils.getPairAddress(I_FACTORY, _tokenA, I_WETH);
        _liquidity = _transferTokensAndMintLiquidity(_pairAddress, _tokenA, I_WETH, _amountTokenA, _amountETH, _to);
    }

    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _liquidity,
        address _to,
        uint256 _deadline
    ) public withinDeadline(_deadline) returns (uint256 _amountTokenA, uint256 _amountTokenB) {
        address _pairAddress = Utils.getPairAddress(I_FACTORY, _tokenA, _tokenB);
        _pairAddress.safeTransferFrom(msg.sender, _pairAddress, _liquidity);
        (uint256 _amount0, uint256 _amount1) = IPair(_pairAddress).burn(_to);
        (address _token0,) = Utils.sortTokens(_tokenA, _tokenB);
        (_amountTokenA, _amountTokenB) = _tokenA == _token0 ? (_amount0, _amount1) : (_amount1, _amount0);

        require(_amountTokenA >= _amountAMin && _amountTokenB >= _amountBMin, Errors.InsufficientAmount());
    }

    function removeLiquidityETH(
        address _tokenA,
        uint256 _liquidity,
        uint256 _amountTokenAMin,
        uint256 _amountETHMin,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256 _amountTokenA, uint256 _amountETH) {
        (_amountTokenA, _amountETH) =
            removeLiquidity(_tokenA, I_WETH, _amountTokenAMin, _amountETHMin, _liquidity, address(this), _deadline);
        _tokenA.safeTransfer(_to, _amountTokenA);
        IWETH(I_WETH).withdraw(_amountETH);
        _to.safeTransferETH(_amountETH);
    }

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256[] memory _amounts) {
        require(_amountIn > 0, Errors.InsufficientAmount());

        _amounts = Utils.getAmountsOut(I_FACTORY, _amountIn, _path);
        require(_amounts[_path.length - 1] >= _amountOutMin, Errors.InsufficientAmount());

        _path[0].safeTransferFrom(msg.sender, Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]);
        _swap(_amounts, _path, _to);
    }

    function swapTokensForExactTokens(
        uint256 _maxAmountIn,
        uint256 _amountOut,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256[] memory _amounts) {
        _amounts = Utils.getAmountsIn(I_FACTORY, _amountOut, _path);
        require(_amounts[0] <= _maxAmountIn, Errors.ExcessiveInputAmount());
        _path[0].safeTransferFrom(msg.sender, Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]);
        _swap(_amounts, _path, _to);
    }

    function swapExactEthForTokens(uint256 _amountOutMin, address[] memory _path, address _to, uint256 _deadline)
        external
        payable
        withinDeadline(_deadline)
        returns (uint256[] memory _amounts)
    {
        require(_path[0] == I_WETH, Errors.InvalidAddressPath());
        require(msg.value > 0, Errors.InsufficientAmount());
        _amounts = Utils.getAmountsOut(I_FACTORY, msg.value, _path);
        require(_amounts[_path.length - 1] >= _amountOutMin, Errors.InsufficientAmount());
        IWETH(I_WETH).deposit{value: _amounts[0]}();
        assert(IWETH(I_WETH).transfer(Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]));
        _swap(_amounts, _path, _to);
    }

    function swapTokensForExactEth(
        uint256 _maxAmountIn,
        uint256 _amountOut,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256[] memory _amounts) {
        require(_path[_path.length - 1] == I_WETH, Errors.InvalidAddressPath());
        _amounts = Utils.getAmountsIn(I_FACTORY, _amountOut, _path);
        require(_amounts[0] <= _maxAmountIn, Errors.ExcessiveInputAmount());
        _path[0].safeTransferFrom(msg.sender, Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]);
        _swap(_amounts, _path, address(this));
        IWETH(I_WETH).withdraw(_amounts[_amounts.length - 1]);
        _to.safeTransferETH(_amounts[_amounts.length - 1]);
    }

    function swapExactTokensForEth(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256[] memory _amounts) {
        require(_amountIn > 0, Errors.InsufficientAmount());
        _amounts = Utils.getAmountsOut(I_FACTORY, _amountIn, _path);
        require(_amounts[_path.length - 1] >= _amountOutMin, Errors.InsufficientAmount());
        _path[0].safeTransferFrom(msg.sender, Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]);
        _swap(_amounts, _path, address(this));
        IWETH(I_WETH).withdraw(_amounts[_amounts.length - 1]);
        _to.safeTransferETH(_amounts[_amounts.length - 1]);
    }

    function swapEthForExactTokens(uint256 _amountOut, address[] memory _path, address _to, uint256 _deadline)
        external
        payable
        withinDeadline(_deadline)
        returns (uint256[] memory _amounts)
    {
        require(_path[0] == I_WETH, Errors.InvalidAddressPath());
        require(msg.value > 0, Errors.InsufficientAmount());
        _amounts = Utils.getAmountsIn(I_FACTORY, _amountOut, _path);
        require(msg.value >= _amount[0], Errors.ExcessiveInputAmount());
        IWETH(I_WETH).deposit{value: _amounts[0]}();
        assert(IWETH(I_WETH).transfer(Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]));
        _swap(_amounts, _path, _to);
    }

    function _swap(uint256[] memory _amounts, address[] memory _path, address _to) private {
        for (uint256 _i; _i < _path.length - 1; _i++) {
            (address _token0,) = Utils.sortTokens(_path[_i], _path[_i + 1]);
            (uint256 _amount0Out, uint256 _amount1Out) =
                _path[_i] == _token0 ? (uint256(0), _amounts[_i + 1]) : (_amounts[_i + 1], uint256(0));
            address to = _i < _path.length - 2 ? Utils.getPairAddress(I_FACTORY, _path[_i + 1], _path[_i + 2]) : _to;

            IPair(Utils.getPairAddress(I_FACTORY, _path[_i], _path[_i + 1])).swap(_amount0Out, _amount1Out, to);
        }
    }
}
