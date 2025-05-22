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

    /// @notice this contract takes factory contract address and WETH address dut=ring deployment
    constructor(address _factory, address _weth) {
        I_FACTORY = _factory;
        I_WETH = _weth;
    }

    /// @notice this function calculates the token amounts for the pool liquidity
    /// @notice It creates the pool if it doesn't existe already
    /// @notice If reserve of both the tokens are 0 then desired amount will be added to the pool
    /// @notice else it will be calculated based on the following simple calculation
    /// @notice _amountTokenB = (_reserveTokenB * _amountTokenA) / _reserveTokenA;
    /// @notice if _amountTokenB is > _amountTokenBDesired, then the calculation will be
    /// @notice _amountTokenA = (_reserveTokenA * _amountTokenB) / _reserveTokenB;
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @param _amountTokenADesired desired liquidity for _tokenA
    /// @param _amountTokenBDesired desired liquidity for tokenB
    /// @param _amountTokenAMin minimum accepted liquidity for _tokenA
    /// @param _amountTokenBMin minimum accepted liquidity for _tokenB
    /// @return _amountTokenA the calculated amount of liquidity for _tokenA
    /// @return _amountTokenB the calculated amount of liquidity for _tokenB
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

    /// @notice this internal function transfers the two tokens with the calculated amount to the pair contract
    /// @notice it then calls the mint function on the pair contract
    /// @notice if _tokenB is the address of wEth, then first the _tokenA is transferred to pair contract
    /// @notice then the deposit function of wEth interface is called with the amount of wEth
    /// @notice That amount is minted to the router contract
    /// @notice then the router transfers the weth amount to the pair contract
    /// @notice else both the tokens are sent to pair contract directly
    /// @param _pairAddress Pair contract address
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @param _amountTokenA the calculated amount of liquidity for _tokenA
    /// @param _amountTokenB the calculated amount of liquidity for _tokenB
    /// @param _to the address to which liquidity tokens will be minted
    /// @return _liquidity the amount of liquidity minted
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
            _tokenA.safeTransferFrom(msg.sender, _pairAddress, _amountTokenA);
            _tokenB.safeTransferFrom(msg.sender, _pairAddress, _amountTokenB);

            _liquidity = IPair(_pairAddress).mint(_to);
        }
    }

    /// @notice this function takes two tokens and their respective amounts to add Liquidity to the pool
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @param _amountTokenADesired desired liquidity for _tokenA
    /// @param _amountTokenBDesired desired liquidity for tokenB
    /// @param _amountTokenAMin minimum accepted liquidity for _tokenA
    /// @param _amountTokenBMin minimum accepted liquidity for _tokenB
    /// @param _to the address to which liquidity tokens will be minted
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amountTokenA amount of liquidity for _tokenA
    /// @return _amountTokenB amount of liquidity for _tokenB
    /// @return _liquidity amount of liquidity token for minted
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

    /// @notice this function removes the liquidity from a pool
    /// @notice it sends the liquidity token of a user and burn it and return the user two tokens
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @param _amountAMin minimum accepted amount for _tokenA
    /// @param _amountBMin minimum accepted amount for _tokenB
    /// @param _to the address to which the amounts will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amountTokenA amount of liquidity removed for _tokenA
    /// @return _amountTokenB amount of liquidity removed for _tokenB
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

    /// @notice this function removes the liquidity from a pool of WETH and another token
    /// @notice it sends the liquidity token of a user and burn it and return the user two tokens
    /// @notice It calls the removeLiquidity function with address(this) in _to argument
    /// @notice so the two tokens are sent to this address
    /// @notice It's done so, because this contract has deposited the Eth token while adding the liquidity
    /// @notice so this contract needs to withdraw the ETH from weth contract which will burn equal amount of weth
    /// @notice after withdrawal this contract will send weth to the _to address
    /// @param _tokenA the first token
    /// @param _amountTokenAMin minimum accepted amount for _tokenA
    /// @param _amountETHMin minimum accepted amount for Weth
    /// @param _to the address to which the amounts will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amountTokenA amount of liquidity removed for _tokenA
    /// @return _amountETH amount of liquidity removed for Eth
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

    /// @notice This function is to perform swap for calculated amount of output token against
    /// @notice exact amount of input token
    /// @notice the input amount is fixed, the output amount will be calculated using constant product formula and
    /// @notice subtracting the fee
    /// @dev use getAmountOut() to calculate the output amount
    /// What is happening here? So, we are using getAmountOut to get all the amounts of the tokens in _path
    /// then we are checking if the last amount(the actual ouput amount) is greater or equal to _amountOutMin
    /// if it is, we are sending the input token to the pair contract
    /// and calling internal _swap function
    /// @param _amountIn exact input amount
    /// @param _amountOutMin minimum output amount
    /// @param _path array of tokens in order to be swapped
    /// @param _to the address to which the amount will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amounts array of amounts with respect to array of tokens in _path
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

    /// @notice This function is to perform swap for exact amount of output token against
    /// @notice calculated amount of input token
    /// @notice the output is fixed, the input amount will be calculated using constant product formula
    /// @dev use getAmountIn() to calculate the input amount
    /// What is happening here? we are using getAmountIn to get all the amounts of the tokens in _path
    /// then we are checking if the first amount(the actual input amount) is less or equal to _maxAmountIn
    /// if it is, we are sending the input token to the pair contract
    /// and calling internal _swap function
    /// @param _maxAmountIn max input amount
    /// @param _amountOut exact output amount
    /// @param _path array of tokens in order to be swapped
    /// @param _to the address to which the amount will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amounts array of amounts with respect to array of tokens in _path
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

    /// @notice This function is to perform swap for calculated amount of output token against
    /// @notice exact amount of input Eth
    /// @notice the input amount is fixed, the output amount will be calculated using constant product formula and
    /// @notice subtracting the fee
    /// @dev use getAmountOut() to calculate the output amount
    /// What is happening here? We are checking if the first token address is weth or not
    /// Also checking if the amount of eth sent to the function is greater than 0 or not
    /// we are using getAmountOut to get all the amounts of the tokens in _path
    /// then we are checking if the last amount(the actual output amount) is greater or equal to _amountOutMin
    /// if it is, this contract is depositing the ETh to the weth contract
    /// and the weth contract minting equal amount to the router contract
    /// then the router transfers the input weth to pair address
    /// and calls internal _swap function
    /// @param _amountOutMin minimum output amount
    /// @param _path array of tokens in order to be swapped
    /// @param _to the address to which the amount will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amounts array of amounts with respect to array of tokens in _path
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

    /// @notice This function is to perform swap for exact amount of ETH against
    /// @notice calculated amount of input token
    /// @notice the output is fixed, the input amount will be calculated using constant product formula
    /// @dev use getAmountIn() to calculate the input amount
    /// What is happening here? We are checking if the last token address is weth or not
    /// we are using getAmountIn to get all the amounts of the tokens in _path
    /// then we are checking if the first amount(the actual input amount) is less or equal to _maxAmountIn
    /// if it is, we are sending the input token to the pair contract
    /// and calls internal _swap function, check the to address is address of this contract
    /// which means the output token will be returned to this contract
    /// as this contract deposited the eth during liquidity addition,
    /// now it will withdraw the required ETH by burning the weth it holds by calling withdraw method in weth contract
    /// then it will transfer that eth to the _to address
    /// @param _maxAmountIn max input amount
    /// @param _amountOut exact output amount
    /// @param _path array of tokens in order to be swapped
    /// @param _to the address to which the amount will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amounts array of amounts with respect to array of tokens in _path
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

    /// @notice This function is to perform swap for calculated amount of Eth against
    /// @notice exact amount of input token
    /// @notice the input amount is fixed, the output amount will be calculated using constant product formula and
    /// @notice subtracting the fee
    /// @dev use getAmountOut() to calculate the output amount
    /// What is happening here? We are checking if the last token address is weth or not
    /// we are using getAmountOut to get all the amounts of the tokens in _path
    /// then we are checking if the last amount(the actual output amount) is greater or equal to _amountOutMin
    /// we are sending the input token to the pair contract
    /// and calls internal _swap function, check the to address is address of this contract
    /// which means the output token will be returned to this contract
    /// as this contract deposited the eth during liquidity addition,
    /// now it will withdraw the required ETH by burning the weth it holds by calling withdraw method in weth contract
    /// then it will transfer that eth to the _to address
    /// @param _amountIn exact input amount
    /// @param _amountOutMin minimum output amount
    /// @param _path array of tokens in order to be swapped
    /// @param _to the address to which the amount will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amounts array of amounts with respect to array of tokens in _path
    function swapExactTokensForEth(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) external withinDeadline(_deadline) returns (uint256[] memory _amounts) {
        require(_amountIn > 0, Errors.InsufficientAmount());
        require(_path[_path.length - 1] == I_WETH, Errors.InvalidAddressPath());
        _amounts = Utils.getAmountsOut(I_FACTORY, _amountIn, _path);
        require(_amounts[_path.length - 1] >= _amountOutMin, Errors.InsufficientAmount());
        _path[0].safeTransferFrom(msg.sender, Utils.getPairAddress(I_FACTORY, _path[0], _path[1]), _amounts[0]);
        _swap(_amounts, _path, address(this));
        IWETH(I_WETH).withdraw(_amounts[_amounts.length - 1]);
        _to.safeTransferETH(_amounts[_amounts.length - 1]);
    }

    /// @notice This function is to perform swap for exact amount of output token against
    /// @notice calculated amount of input Eth
    /// @notice the output is fixed, the input amount will be calculated using constant product formula
    /// @dev use getAmountIn() to calculate the input amount
    /// What is happening here? We are checking if the first token address is weth or not
    /// Also checking if the amount of eth sent to the function is greater than 0 or not
    /// we are using getAmountIn to get all the amounts of the tokens in _path
    /// then we are checking if the first amount(the actual input amount) is less or equal to msg.value
    /// if it is, this contract is depositing the ETh to the weth contract
    /// and the weth contract minting equal amount to the router contract
    /// then the router transfers the input weth to pair address
    /// and calls internal _swap function
    /// @param _amountOut exact output amount
    /// @param _path array of tokens in order to be swapped
    /// @param _to the address to which the amount will be transferred
    /// @param _deadline the deadline before which this function needs to be called
    /// @return _amounts array of amounts with respect to array of tokens in _path
    function swapEthForExactTokens(uint256 _amountOut, address[] memory _path, address _to, uint256 _deadline)
        external
        payable
        withinDeadline(_deadline)
        returns (uint256[] memory _amounts)
    {
        require(_path[0] == I_WETH, Errors.InvalidAddressPath());
        require(msg.value > 0, Errors.InsufficientAmount());
        _amounts = Utils.getAmountsIn(I_FACTORY, _amountOut, _path);
        require(msg.value >= _amounts[0], Errors.ExcessiveInputAmount());
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
