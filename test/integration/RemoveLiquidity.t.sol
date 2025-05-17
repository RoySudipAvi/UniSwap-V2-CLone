//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    TestSetup,
    console,
    Utils,
    Errors,
    Router,
    SafeTransferLib,
    Pair,
    IPair,
    IFactory,
    Factory,
    MockToken,
    IERC20,
    FixedPointMathLib
} from "test/integration/Setup.t.sol";

contract RemoveLiquidityTest is TestSetup {
    using FixedPointMathLib for uint256;

    function callAddLiquidity(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMinDeposit,
        uint256 _amountTokenBMinDeposit,
        uint256 _deadline,
        address _to
    ) public returns (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) {
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMinDeposit, _amountTokenBMinDeposit, _deadline) =
        addLiquiditySetUp(
            _amountTokenADesired, _amountTokenBDesired, _amountTokenAMinDeposit, _amountTokenBMinDeposit, _deadline, _to
        );
        vm.startPrank(s_user1.addr);
        (_amountTokenA, _amountTokenB, _liquidity) = s_router.addLiquidity(
            s_tokenA,
            s_tokenB,
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _to,
            _deadline
        );

        vm.stopPrank();
    }

    function liquidityLimitCalculation(uint256 _liquidityBurn, uint256 _liquidity) public returns (uint256) {
        (uint256 _minAmountA, uint256 _minAmountB) = getUSDToMinTokenPrice(
            MINIMUM_LIQUIDITY_AMOUNT, s_tokenA, s_tokenB, MockToken(s_tokenA).decimals(), MockToken(s_tokenB).decimals()
        );
        uint256 _minLiquidity = (_minAmountA * _minAmountB).sqrt() - 1000;
        console.log("minLiqu: ", _minLiquidity);
        _liquidityBurn = bound(_liquidityBurn, _minLiquidity, _liquidity);
        return _liquidityBurn;
    }

    function tokenAmountLimitCalculation(
        uint256 _liquidityBurn,
        uint256 _amountTokenAMinWithdraw,
        uint256 _amountTokenBMinWithdraw,
        uint256 _amountTokenA,
        uint256 _amountTokenB,
        address _pairAddress
    ) public returns (uint256, uint256) {
        uint256 _totalsupply = IERC20(_pairAddress).totalSupply();
        uint256 _amountTokenAWithdrawMax = (_amountTokenA * _liquidityBurn) / _totalsupply;
        uint256 _amountTokenBWithdrawMax = (_amountTokenB * _liquidityBurn) / _totalsupply;
        _amountTokenAMinWithdraw =
            bound(_amountTokenAMinWithdraw, (_amountTokenAWithdrawMax * 95) / 100, _amountTokenAWithdrawMax);

        _amountTokenBMinWithdraw =
            bound(_amountTokenBMinWithdraw, (_amountTokenBWithdrawMax * 95) / 100, _amountTokenBWithdrawMax);

        return (_amountTokenAMinWithdraw, _amountTokenBMinWithdraw);
    }

    function removeLiquiditySetUp(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMinDeposit,
        uint256 _amountTokenBMinDeposit,
        uint256 _deadline,
        uint256 _liquidityBurn,
        uint256 _amountTokenAMinWithdraw,
        uint256 _amountTokenBMinWithdraw
    ) private returns (uint256, uint256, uint256, uint256) {
        (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) = callAddLiquidity(
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _deadline,
            s_user1.addr
        );

        address _pairAddress = Utils.getPairAddress(address(s_factory), s_tokenA, s_tokenB);

        _liquidityBurn = liquidityLimitCalculation(_liquidityBurn, _liquidity);
        (_amountTokenAMinWithdraw, _amountTokenBMinWithdraw) = tokenAmountLimitCalculation(
            _liquidityBurn,
            _amountTokenAMinWithdraw,
            _amountTokenBMinWithdraw,
            _amountTokenA,
            _amountTokenB,
            _pairAddress
        );

        vm.startPrank(s_user1.addr);
        IERC20(_pairAddress).approve(address(s_router), _liquidityBurn);
        vm.stopPrank();
        _deadline = bound(_deadline, block.timestamp + 5, block.timestamp + 900);
        return (_amountTokenAMinWithdraw, _amountTokenBMinWithdraw, _liquidityBurn, _deadline);
    }

    function testRemoveLiquidityTransferAmounts(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMinDeposit,
        uint256 _amountTokenBMinDeposit,
        uint256 _deadline,
        uint256 _liquidityBurn,
        uint256 _amountTokenAMinWithdraw,
        uint256 _amountTokenBMinWithdraw
    ) external {
        (uint256 _amountTokenAMinWithdraw, uint256 _amountTokenBMinWithdraw, uint256 _liquidityBurn, uint256 _deadline)
        = removeLiquiditySetUp(
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _deadline,
            _liquidityBurn,
            _amountTokenAMinWithdraw,
            _amountTokenBMinWithdraw
        );

        (uint256 _reserveA, uint256 _reserveB) = Utils.getReserves(address(s_factory), s_tokenA, s_tokenB);

        vm.startPrank(s_user1.addr);
        (uint256 _withdrawnTokenA, uint256 _withdrawnTokenB) = s_router.removeLiquidity(
            s_tokenA,
            s_tokenB,
            _amountTokenAMinWithdraw,
            _amountTokenBMinWithdraw,
            _liquidityBurn,
            s_user1.addr,
            _deadline
        );
        vm.stopPrank();

        (uint256 _reserveNewA, uint256 _reserveNewB) = Utils.getReserves(address(s_factory), s_tokenA, s_tokenB);

        assertEq(_reserveNewA, _reserveA - _withdrawnTokenA);
        assertEq(_reserveNewB, _reserveB - _withdrawnTokenB);
    }
}
