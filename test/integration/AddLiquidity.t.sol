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
    IERC20
} from "test/integration/Setup.t.sol";

contract AddLiquidityTest is TestSetup {
    function testRevertIfDeadlinePassed() external {
        uint256 _amountTokenADesired = 3e3;
        uint256 _amountTokenBDesired = 7e4;
        uint256 _amountTokenAMin = 2700;
        uint256 _amountTokenBMin = 69000;
        uint256 _deadline = block.timestamp + 180;
        address _to = s_user1.addr;

        vm.expectRevert(Errors.Expired.selector);
        vm.warp(block.timestamp + 190);
        s_router.addLiquidity(
            s_tokens[0],
            s_tokens[1],
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            _to,
            _deadline
        );
    }

    function testRevertIfNoInitialBalance() external {
        uint256 _amountTokenADesired = 3e3;
        uint256 _amountTokenBDesired = 7e4;
        uint256 _amountTokenAMin = 2700;
        uint256 _amountTokenBMin = 69000;
        uint256 _deadline = block.timestamp + 180;
        address _to = s_user1.addr;
        vm.startPrank(s_user1.addr);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        s_router.addLiquidity(
            s_tokens[0],
            s_tokens[1],
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            _to,
            _deadline
        );
        vm.stopPrank();
    }

    function testAddLiquidityUpdateReserves(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline
    ) external {
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) = addLiquiditySetUp(
            _amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline, s_user1.addr
        );
        vm.startPrank(s_user1.addr);
        (,, uint256 _liquidity) = s_router.addLiquidity(
            s_tokenA,
            s_tokenB,
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            s_user1.addr,
            _deadline
        );
        vm.stopPrank();

        address _pairAddress = Utils.getPairAddress(address(s_factory), address(s_tokenA), address(s_tokenB));
        (uint256 _reserveTokenA, uint256 _reserveTokenB) = Utils.getReserves(address(s_factory), s_tokenA, s_tokenB);
        assertEq(_reserveTokenA, IERC20(s_tokenA).balanceOf(_pairAddress));
        assertEq(_reserveTokenB, IERC20(s_tokenB).balanceOf(_pairAddress));
    }

    function testAddLiquidityCheckLiquidity(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline
    ) external {
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) = addLiquiditySetUp(
            _amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline, s_user1.addr
        );
        vm.startPrank(s_user1.addr);
        (,, uint256 _liquidity) = s_router.addLiquidity(
            s_tokenA,
            s_tokenB,
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            s_user1.addr,
            _deadline
        );
        vm.stopPrank();

        address _pairAddress = Utils.getPairAddress(address(s_factory), address(s_tokenA), address(s_tokenB));

        assertEq(IERC20(_pairAddress).balanceOf(s_user1.addr), _liquidity);
    }

    // function _addLiquidityCalculation(
    //     address _tokenA,
    //     address _tokenB,
    //     uint256 _amountTokenADesired,
    //     uint256 _amountTokenBDesired,
    //     address _pairAddress
    // ) public returns (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) {
    //     IFactory(address(s_factory)).createPair(_tokenA, _tokenB);
    //     _amountTokenA = _amountTokenADesired;
    //     _amountTokenB = _amountTokenBDesired;
    //     _liquidity = (_amountTokenA * _amountTokenB).sqrt() - IPair(_pairAddress).MINIMUM_LIQUIDITY();
    // }
}
