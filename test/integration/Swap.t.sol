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

contract SwapTest is TestSetup {
    function callAddLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountTokenADesiredDeposit,
        uint256 _amountTokenBDesiredDeposit,
        uint256 _amountTokenAMinDeposit,
        uint256 _amountTokenBMinDeposit,
        uint256 _deadlineDeposit,
        address _to
    ) public returns (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) {
        vm.startPrank(_to);
        (_amountTokenA, _amountTokenB, _liquidity) = s_router.addLiquidity(
            address(_tokenA),
            address(_tokenB),
            _amountTokenADesiredDeposit,
            _amountTokenBDesiredDeposit,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _to,
            _deadlineDeposit
        );
        vm.stopPrank();
    }

    function calculateAmountIn(uint256 _amountIn, address _path0, address _path1) private returns (uint256) {
        uint256 _minBound = getUsdToTokenPrice(MINIMUM_SWAP_AMOUNT, _path0, MockToken(_path0).decimals());
        (uint256 _amountAReserve,) = Utils.getReserves(address(s_factory), _path0, _path1);

        _amountIn = bound(_amountIn, _minBound, _amountAReserve);
        return _amountIn;
    }

    function calculateBalances(address[] memory _path) private returns (uint256, uint256) {
        address _pairAddressIn = Utils.getPairAddress(address(s_factory), _path[0], _path[1]);
        address _pairAddressOut =
            Utils.getPairAddress(address(s_factory), _path[_path.length - 2], _path[_path.length - 1]);
        uint256 _balanceIn = IERC20(_path[0]).balanceOf(_pairAddressIn);
        uint256 _balanceOut = IERC20(_path[_path.length - 1]).balanceOf(_pairAddressOut);
        return (_balanceIn, _balanceOut);
    }

    function _createPathAndUsers() private view returns (address[] memory _path, address[] memory _users) {
        _path = new address[](3);
        _path[0] = s_tokens[0];
        _path[1] = s_tokens[1];
        _path[2] = s_tokens[2];

        _users = new address[](2);
        _users[0] = s_user1.addr;
        _users[1] = s_user2.addr;
    }

    function testSwapExactTokensForTokensUpdateReserve(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline,
        uint256 _amountIn
    ) external {
        (address[] memory _path, address[] memory _users) = _createPathAndUsers();

        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) = addLiquiditySetUp(
            _amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline, s_user1.addr
        );
        vm.startPrank(s_user1.addr);
        s_router.addLiquidity(
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

        s_tokenA = s_tokens[1];
        s_tokenB = s_tokens[2];
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) = addLiquiditySetUp(
            _amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline, s_user2.addr
        );
        vm.startPrank(s_user2.addr);
        s_router.addLiquidity(
            s_tokenA,
            s_tokenB,
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            s_user2.addr,
            _deadline
        );
        vm.stopPrank();
        (_amountIn) = calculateAmountIn(_amountIn, _path[0], _path[1]);
        uint256[] memory _amounts = Utils.getAmountsOut(address(s_factory), _amountIn, _path);
        (uint256 _balanceIn, uint256 _balanceOut) = calculateBalances(_path);
        vm.startPrank(s_user3.addr);
        IERC20(_path[0]).approve(address(s_router), IERC20(_path[0]).balanceOf(s_user3.addr));
        s_router.swapExactTokensForTokens(
            _amountIn, (_amounts[_amounts.length - 1] * 98) / 100, _path, s_user3.addr, _deadline
        );
        vm.stopPrank();

        (uint256 _reserveIn,) = Utils.getReserves(address(s_factory), _path[0], _path[1]);
        (, uint256 _reserveOut) =
            Utils.getReserves(address(s_factory), _path[_path.length - 2], _path[_path.length - 1]);
        assertEq(_reserveIn, _balanceIn + _amounts[0]);

        assertEq(_reserveOut, _balanceOut - _amounts[_amounts.length - 1]);
    }
}
