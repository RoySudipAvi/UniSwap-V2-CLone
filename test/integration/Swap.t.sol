//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    Test,
    console,
    Utils,
    Errors,
    Router,
    IWETH,
    SafeTransferLib,
    Pair,
    IPair,
    IFactory,
    Factory,
    WETH,
    FactoryRouterDeployment,
    MockToken,
    Vm,
    IERC20,
    FixedPointMathLib,
    AddLiquidityTest
} from "test/integration/AddLiquidity.t.sol";

contract SwapTest is Test {
    using FixedPointMathLib for uint256;

    uint256 private constant s_initialBalanceUser1TokenA = 100 * (10 ** 18);
    uint256 private constant s_initialBalanceUser1TokenB = 290367 * (10 ** 18);
    uint256 private constant s_initialBalanceUser2TokenB = 908172 * (10 ** 18);
    uint256 private constant s_initialBalanceUser2TokenC = 70000 * (10 ** 18);

    Factory private s_factory;
    Pair private s_pair;
    Router private s_router;
    WETH private s_wETH;
    FactoryRouterDeployment private s_factoryRouterDeployment;
    MockToken private s_tokenA;
    MockToken private s_tokenB;
    MockToken private s_tokenC;

    Vm.Wallet private s_user1;
    Vm.Wallet private s_user2;
    Vm.Wallet private s_user3;
    AddLiquidityTest private s_addLiquidityTest;

    event Mint(
        address indexed _sender, uint256 indexed _amountTokenA, uint256 indexed _amountTokenB, uint256 _liquidity
    );

    event Burn(address indexed _sender, uint256 indexed _amountTokenA, uint256 indexed _amountTokenB, address _to);

    event sync(uint112 indexed _reserveTokenA, uint112 indexed _reserveTokenB, uint32 indexed _lastBlockTimestamp);

    function setUp() external {
        s_factoryRouterDeployment = new FactoryRouterDeployment();
        (s_wETH, s_factory, s_router) = s_factoryRouterDeployment.run();
        s_tokenA = new MockToken("Token A", "TKNA", 18);
        s_tokenB = new MockToken("Token B", "TKNB", 18);
        s_tokenC = new MockToken("Token C", "TKNC", 18);
        s_user1 = vm.createWallet("User 1");
        s_user2 = vm.createWallet("User 2");
        s_user3 = vm.createWallet("User 3");

        s_tokenA.mint(s_user1.addr, s_initialBalanceUser1TokenA);
        s_tokenB.mint(s_user1.addr, s_initialBalanceUser1TokenB);
        s_tokenB.mint(s_user2.addr, s_initialBalanceUser2TokenB);
        s_tokenC.mint(s_user2.addr, s_initialBalanceUser2TokenC);
        s_tokenA.mint(s_user3.addr, 1000 * (10 ** 18));

        s_addLiquidityTest = new AddLiquidityTest();
    }

    function addLiquiditySetUp(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        address _tokenA,
        address _tokenB,
        uint256 _deadline,
        address _to
    ) public view returns (uint256, uint256, uint256, uint256, uint256) {
        _deadline = bound(_deadline, 5, 3600);
        _deadline = block.timestamp + _deadline;
        vm.assume(_amountTokenAMin > 0);
        vm.assume(_amountTokenBMin > 0);
        if (IERC20(_tokenA).balanceOf(_to) <= IERC20(_tokenB).balanceOf(_to)) {
            _amountTokenAMin = bound(_amountTokenAMin, 1 * (10 ** 17), IERC20(_tokenA).balanceOf(_to) - 1000);
            uint256 _tokenBMinStart =
                (_amountTokenAMin * (IERC20(_tokenB).balanceOf(_to)) / IERC20(_tokenA).balanceOf(_to));
            uint256 _tokenBMinEnd = IERC20(_tokenB).balanceOf(_to) - 1000;

            _amountTokenBMin = bound(_amountTokenBMin, _tokenBMinStart, _tokenBMinEnd);
        } else {
            _amountTokenBMin = bound(_amountTokenBMin, 1 * (10 ** 17), IERC20(_tokenB).balanceOf(_to) - 1000);
            uint256 _tokenAMinStart =
                (_amountTokenBMin * (IERC20(_tokenA).balanceOf(_to)) / IERC20(_tokenB).balanceOf(_to));
            uint256 _tokenAMinEnd = IERC20(_tokenA).balanceOf(_to) - 1000;

            _amountTokenAMin = bound(_amountTokenAMin, _tokenAMinStart, _tokenAMinEnd);
        }
        _amountTokenADesired = bound(_amountTokenADesired, _amountTokenAMin, IERC20(_tokenA).balanceOf(_to));
        _amountTokenBDesired = bound(_amountTokenBDesired, _amountTokenBMin, IERC20(_tokenB).balanceOf(_to));

        return (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
    }

    function _tokenApproval(address _tokenA, address _tokenB, address _to, address _router) private {
        vm.startPrank(_to);

        IERC20(_tokenA).approve(_router, IERC20(_tokenA).balanceOf(_to));
        IERC20(_tokenB).approve(_router, IERC20(_tokenB).balanceOf(_to));

        vm.stopPrank();
    }

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

    function _createPathAndUsers() private view returns (address[] memory _path, address[] memory _users) {
        _path = new address[](3);
        _path[0] = address(s_tokenA);
        _path[1] = address(s_tokenB);
        _path[2] = address(s_tokenC);

        _users = new address[](2);
        _users[0] = s_user1.addr;
        _users[1] = s_user2.addr;
    }

    function testSwapExactTokensForTokensUpdateReserve(
        uint256 _amountTokenADesiredDeposit,
        uint256 _amountTokenBDesiredDeposit,
        uint256 _amountTokenAMinDeposit,
        uint256 _amountTokenBMinDeposit,
        uint256 _deadline,
        uint256 _amountIn
    ) external {
        (address[] memory _path, address[] memory _users) = _createPathAndUsers();

        for (uint256 _i; _i < _path.length - 1; _i++) {
            (
                _amountTokenADesiredDeposit,
                _amountTokenBDesiredDeposit,
                _amountTokenAMinDeposit,
                _amountTokenBMinDeposit,
                _deadline
            ) = addLiquiditySetUp(
                _amountTokenADesiredDeposit,
                _amountTokenBDesiredDeposit,
                _amountTokenAMinDeposit,
                _amountTokenBMinDeposit,
                _path[_i],
                _path[_i + 1],
                _deadline,
                _users[_i]
            );
            _tokenApproval(_path[_i], _path[_i + 1], _users[_i], address(s_router));

            callAddLiquidity(
                _path[_i],
                _path[_i + 1],
                _amountTokenADesiredDeposit,
                _amountTokenBDesiredDeposit,
                _amountTokenAMinDeposit,
                _amountTokenBMinDeposit,
                _deadline,
                _users[_i]
            );
        }
        (uint256 _amountAReserve,) = Utils.getReserves(address(s_factory), _path[0], _path[1]);
        _amountIn = bound(_amountIn, 1 * (10 ** 17), _amountAReserve);
        uint256[] memory _amounts = Utils.getAmountsOut(address(s_factory), _amountIn, _path);
        address _pairAddressIn = Utils.getPairAddress(address(s_factory), _path[0], _path[1]);
        address _pairAddressOut =
            Utils.getPairAddress(address(s_factory), _path[_path.length - 2], _path[_path.length - 1]);
        uint256 _balanceIn = IERC20(_path[0]).balanceOf(_pairAddressIn);
        uint256 _balanceOut = IERC20(_path[_path.length - 1]).balanceOf(_pairAddressOut);

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
