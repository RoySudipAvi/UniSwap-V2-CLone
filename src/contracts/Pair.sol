//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPair} from "src/interfaces/IPair.sol";
import {ERC20} from "@solady/contracts/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solady/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {Errors} from "src/interfaces/Errors.sol";
import {FixedPointMathLib} from "@solady/contracts/utils/FixedPointMathLib.sol";
import {Math} from "src/libraries/Math.sol";
import {SafeTransferLib} from "@solady/contracts/utils/SafeTransferLib.sol";
import {console} from "forge-std/console.sol";

/// @title Pair Contract
/// @notice It replicates Uniswap V2 pair contract
/// @notice It doesn't implement the mintFee and skim
/// @notice It is itself an ERC20 contract and
/// @notice at the same time does other important tasks like perform swap,
/// @notice perform TWAP and update reserves
contract Pair is IPair, ERC20, ReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;
    using Math for uint112;
    using Math for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    address private s_tokenA;
    address private s_tokenB;
    uint112 private s_reserveTokenA;
    uint112 private s_reserveTokenB;
    uint32 private s_lastBlockTimestamp;
    uint256 private s_accumulatedPriceTokenA;
    uint256 private s_accumulatedPriceTokenB;

    event Mint(
        address indexed _sender, uint256 indexed _amountTokenA, uint256 indexed _amountTokenB, uint256 _liquidity
    );

    event Burn(address indexed _sender, uint256 indexed _amountTokenA, uint256 indexed _amountTokenB, address _to);

    event sync(uint112 indexed _reserveTokenA, uint112 indexed _reserveTokenB, uint32 indexed _lastBlockTimestamp);

    function initialize(address _tokenA, address _tokenB) external {
        s_tokenA = _tokenA;
        s_tokenB = _tokenB;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (s_reserveTokenA, s_reserveTokenB, s_lastBlockTimestamp);
    }

    function name() public pure override returns (string memory) {
        return "UniV2CloneToken";
    }

    function symbol() public pure override returns (string memory) {
        return "UVCT";
    }

    /// @notice it gets called when one is providing liquidity to the protocol
    /// @notice It mints liquidity tokens to the liquidity provider based on the amount of liquidity provided
    /// @notice It also updates the reserve and accumalted prices
    function mint(address _to) external nonReentrant returns (uint256 _liquidity) {
        uint256 _balanceTokenA = IERC20(s_tokenA).balanceOf(address(this));
        uint256 _balanceTokenB = IERC20(s_tokenB).balanceOf(address(this));
        (uint112 _reserveTokenA, uint112 _reserveTokenB,) = getReserves();
        uint256 _amountTokenA = _balanceTokenA - _reserveTokenA;
        uint256 _amountTokenB = _balanceTokenB - _reserveTokenB;
        require(_amountTokenA > 0 && _amountTokenB > 0, Errors.InsufficientAmount());
        uint256 _totalsupply = totalSupply();
        if (_totalsupply == 0) {
            _liquidity = (_amountTokenA * _amountTokenB).sqrt() - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            _liquidity =
                ((_amountTokenA * _totalsupply) / _reserveTokenA).min((_amountTokenB * _totalsupply) / _reserveTokenB);
        }
        require(_liquidity > 0, Errors.InsufficientAmount());
        _update(_balanceTokenA, _balanceTokenB, _reserveTokenA, _reserveTokenB);
        emit Mint(msg.sender, _amountTokenA, _amountTokenB, _liquidity);
        _mint(_to, _liquidity);
    }

    function burn(address _to) external nonReentrant returns (uint256 _amountTokenA, uint256 _amountTokenB) {
        (uint112 _reserveTokenA, uint112 _reserveTokenB,) = getReserves();
        uint256 _liquidity = balanceOf(address(this));
        uint256 _balanceTokenA = IERC20(s_tokenA).balanceOf(address(this));
        uint256 _balanceTokenB = IERC20(s_tokenB).balanceOf(address(this));
        uint256 _totalsupply = totalSupply();
        require(_balanceTokenA <= type(uint256).max / _liquidity, Errors.Overflow());
        require(_balanceTokenB <= type(uint256).max / _liquidity, Errors.Overflow());
        _amountTokenA = (_balanceTokenA * _liquidity) / _totalsupply;
        _amountTokenB = (_balanceTokenB * _liquidity) / _totalsupply;
        _burn(address(this), _liquidity);
        s_tokenA.safeTransfer(_to, _amountTokenA);
        s_tokenB.safeTransfer(_to, _amountTokenB);
        _update(
            IERC20(s_tokenA).balanceOf(address(this)),
            IERC20(s_tokenB).balanceOf(address(this)),
            _reserveTokenA,
            _reserveTokenB
        );

        emit Burn(msg.sender, _amountTokenA, _amountTokenB, _to);
    }

    function swap(uint256 _amount0Out, uint256 _amount1Out, address _to) external nonReentrant {
        require(_amount0Out > 0 || _amount1Out > 0, Errors.InsufficientAmount());
        (uint112 _reserveTokenA, uint112 _reserveTokenB,) = getReserves();
        require(_reserveTokenA > 0 && _reserveTokenB > 0, Errors.InsufficientLiquidity());
        address _tokenA = s_tokenA;
        address _tokenB = s_tokenB;

        if (_amount0Out > 0) _tokenA.safeTransfer(_to, _amount0Out);
        if (_amount1Out > 0) _tokenB.safeTransfer(_to, _amount1Out);

        uint256 _balanceA = _tokenA.balanceOf(address(this));
        uint256 _balanceB = _tokenB.balanceOf(address(this));

        uint256 _amount0In = _balanceA > (_reserveTokenA - _amount0Out) ? _balanceA - (_reserveTokenA - _amount0Out) : 0;
        uint256 _amount1In = _balanceB > (_reserveTokenB - _amount1Out) ? _balanceB - (_reserveTokenB - _amount1Out) : 0;
        uint256 _balanceAdjustedTokenA = (1000 * _balanceA) - (3 * _amount0In);
        uint256 _balanceAdjustedTokenB = (1000 * _balanceB) - (3 * _amount1In);
        require(
            _balanceAdjustedTokenA * _balanceAdjustedTokenB
                >= uint256(_reserveTokenA) * uint256(_reserveTokenB) * 1000 ** 2
        );
        _update(_balanceA, _balanceB, _reserveTokenA, _reserveTokenB);
    }

    function _update(uint256 _balanceTokenA, uint256 _balanceTokenB, uint112 _reserveTokenA, uint112 _reserveTokenB)
        private
    {
        require(_balanceTokenA <= type(uint112).max && _balanceTokenB <= type(uint112).max, Errors.Overflow());
        uint32 _currentTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 _elapsedTime = _currentTimestamp - s_lastBlockTimestamp;
        if (_elapsedTime > 0 && _reserveTokenA > 0 && _reserveTokenB > 0) {
            s_accumulatedPriceTokenA += (_reserveTokenB.encode().divide(_reserveTokenA)) * _elapsedTime;
            s_accumulatedPriceTokenB += (_reserveTokenA.encode().divide(_reserveTokenB)) * _elapsedTime;
        }
        s_reserveTokenA = uint112(_balanceTokenA);
        s_reserveTokenB = uint112(_balanceTokenB);
        s_lastBlockTimestamp = _currentTimestamp;
        emit sync(s_reserveTokenA, s_reserveTokenB, s_lastBlockTimestamp);
    }
}
