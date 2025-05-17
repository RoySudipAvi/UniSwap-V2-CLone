//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Utils, Errors, Router, IWETH, SafeTransferLib} from "src/contracts/Router.sol";
import {Pair, IPair, IFactory, Factory} from "src/contracts/Factory.sol";
import {WETH, FactoryRouterDeployment, HelperConfig} from "script/deployments/FactoryRouter.s.sol";
import {MockToken} from "test/mocks/MockToken.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {FixedPointMathLib} from "@solady/contracts/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract TestSetup is Test {
    using FixedPointMathLib for uint256;

    uint256 internal constant INITIAL_BALANCE_USER1_WBTC = 100 * (10 ** 8);
    uint256 internal constant INITIAL_BALANCE_USER1_USDC = 10366042 * (10 ** 18);
    uint256 internal constant INITIAL_BALANCE_USER1_LINK = 597466 * (10 ** 18);

    uint256 internal constant INITIAL_BALANCE_USER2_LINK = 300000 * (10 ** 18);
    uint256 internal constant INITIAL_BALANCE_USER2_USDC = 5548000 * (10 ** 18);
    uint256 internal constant MINIMUM_LIQUIDITY_AMOUNT = 1000;
    uint256 internal constant MINIMUM_SWAP_AMOUNT = 50;
    address public s_tokenA;
    address public s_tokenB;
    AggregatorV3Interface internal s_priceFeed;
    Factory internal s_factory;
    Pair internal s_pair;
    Router internal s_router;
    HelperConfig internal s_helperConfig;
    FactoryRouterDeployment internal s_factoryRouterDeployment;
    WETH internal s_wETH;

    Vm.Wallet internal s_user1;
    Vm.Wallet internal s_user2;
    Vm.Wallet internal s_user3;
    address[3] internal s_tokens;
    address[3] internal s_priceFeeds;

    function setUp() external {
        s_factoryRouterDeployment = new FactoryRouterDeployment();
        (s_factory, s_router, s_wETH, s_helperConfig) = s_factoryRouterDeployment.run();
        s_tokens = s_helperConfig.getTokens();
        s_user1 = vm.createWallet("User 1");
        s_user2 = vm.createWallet("User 2");
        s_user3 = vm.createWallet("User 3");
        MockToken(s_tokens[0]).mint(s_user1.addr, INITIAL_BALANCE_USER1_WBTC);
        MockToken(s_tokens[1]).mint(s_user1.addr, INITIAL_BALANCE_USER1_USDC);
        MockToken(s_tokens[2]).mint(s_user1.addr, INITIAL_BALANCE_USER1_LINK);
        MockToken(s_tokens[1]).mint(s_user2.addr, INITIAL_BALANCE_USER2_USDC);
        MockToken(s_tokens[2]).mint(s_user2.addr, INITIAL_BALANCE_USER2_LINK);
        MockToken(s_tokens[0]).mint(s_user3.addr, 100 * (10 ** 8));
        console.log(s_tokens[0], s_tokens[1], s_tokens[2]);
        (int256 _price1,) = getTokenToUSDPrice(s_helperConfig.getPriceFeedByToken(s_tokens[0]));
        (int256 _price2,) = getTokenToUSDPrice(s_helperConfig.getPriceFeedByToken(s_tokens[1]));
        (int256 _price3,) = getTokenToUSDPrice(s_helperConfig.getPriceFeedByToken(s_tokens[2]));

        try vm.envAddress("TOKEN_A") returns (address _address) {
            s_tokenA = _address;
        } catch {
            s_tokenA = s_tokens[0]; // Default value
        }

        try vm.envAddress("TOKEN_B") returns (address _address) {
            s_tokenB = _address;
        } catch {
            s_tokenB = s_tokens[1]; // Default value
        }
    }

    function addLiquiditySetUp(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline,
        address _to
    ) internal returns (uint256, uint256, uint256, uint256, uint256) {
        (_amountTokenAMin, _amountTokenBMin) = minAmountCalculation(_to, _amountTokenAMin, _amountTokenBMin);
        (_amountTokenADesired, _amountTokenBDesired) = desiredAmountCalculation(
            _to, _amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin
        );
        tokenApproval(s_tokenA, s_tokenB, _to, address(s_router));
        _deadline = bound(_deadline, block.timestamp + 5, block.timestamp + 900);

        return (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
    }

    function tokenApproval(address _tokenA, address _tokenB, address _to, address _router) internal {
        vm.startPrank(_to);
        IERC20(_tokenA).approve(_router, IERC20(s_tokenA).balanceOf(_to));
        IERC20(_tokenB).approve(_router, IERC20(s_tokenB).balanceOf(_to));
        vm.stopPrank();
    }

    function minAmountCalculation(address _to, uint256 _amountTokenAMin, uint256 _amountTokenBMin)
        internal
        returns (uint256, uint256)
    {
        (uint256 _minAmountA, uint256 _minAmountB) = getUSDToMinTokenPrice(
            MINIMUM_LIQUIDITY_AMOUNT, s_tokenA, s_tokenB, MockToken(s_tokenA).decimals(), MockToken(s_tokenB).decimals()
        );

        _amountTokenAMin = bound(_amountTokenAMin, _minAmountA, IERC20(s_tokenA).balanceOf(_to) - 100);
        _amountTokenBMin = bound(_amountTokenBMin, _minAmountB, IERC20(s_tokenB).balanceOf(_to) - 100);
        return (_amountTokenAMin, _amountTokenBMin);
    }

    function desiredAmountCalculation(
        address _to,
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin
    ) internal returns (uint256, uint256) {
        _amountTokenADesired = bound(_amountTokenADesired, _amountTokenAMin, IERC20(s_tokenA).balanceOf(_to));
        _amountTokenBDesired = bound(_amountTokenBDesired, _amountTokenBMin, IERC20(s_tokenB).balanceOf(_to));

        return (_amountTokenADesired, _amountTokenBDesired);
    }

    function calculateActualPrices(address _tokenA, address _tokenB)
        internal
        view
        returns (uint256 _actualPriceA, uint256 _actualPriceB)
    {
        address _pricefeedA = s_helperConfig.getPriceFeedByToken(_tokenA);
        (int256 _priceA, uint8 _decimalsA) = getTokenToUSDPrice(_pricefeedA);
        _actualPriceA = uint256(_priceA) / (10 ** _decimalsA);
        address _pricefeedB = s_helperConfig.getPriceFeedByToken(_tokenB);
        (int256 _priceB, uint8 _decimalsB) = getTokenToUSDPrice(_pricefeedB);
        _actualPriceB = uint256(_priceB) / (10 ** _decimalsB);
    }

    function getUSDToMinTokenPrice(uint256 _usdAmount, address _tokenA, address _tokenB, uint256 _wadA, uint256 _wadB)
        internal
        returns (uint256 _minAmountA, uint256 _minAmountB)
    {
        (uint256 _actualPriceA, uint256 _actualPriceB) = calculateActualPrices(_tokenA, _tokenB);

        _minAmountA = (_usdAmount * (10 ** _wadA)) / _actualPriceA;
        _minAmountB = (_usdAmount * (10 ** _wadB)) * _actualPriceB;
    }

    function getTokenToUSDPrice(address _pricefeed) internal view returns (int256, uint8) {
        (, int256 answer,,,) = AggregatorV3Interface(_pricefeed).latestRoundData();
        return (answer, AggregatorV3Interface(_pricefeed).decimals());
    }

    function getUsdToTokenPrice(uint256 _usdAmount, address _tokenA, uint256 _wadA)
        internal
        returns (uint256 _amountA)
    {
        address _pricefeedA = s_helperConfig.getPriceFeedByToken(_tokenA);
        (int256 _priceA, uint8 _decimalsA) = getTokenToUSDPrice(_pricefeedA);
        uint256 _actualPriceA = uint256(_priceA) / (10 ** _decimalsA);
        _amountA = (_usdAmount * (10 ** _wadA)) / _actualPriceA;
    }
}
