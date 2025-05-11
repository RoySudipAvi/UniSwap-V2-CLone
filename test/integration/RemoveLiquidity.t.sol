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

contract RemoveLiquidityTest is Test {
    using FixedPointMathLib for uint256;

    uint256 private constant s_initialBalanceUser1TokenA = 1000 * (10 ** 18);
    uint256 private constant s_initialBalanceUser2TokenA = 3000 * (10 ** 18);
    uint256 private constant s_initialBalanceUser1TokenB = 15000 * (10 ** 18);
    uint256 private constant s_initialBalanceUser2TokenB = 45000 * (10 ** 18);
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
        s_tokenA.mint(s_user1.addr, s_initialBalanceUser1TokenA);
        s_tokenA.mint(s_user2.addr, s_initialBalanceUser2TokenA);
        s_tokenB.mint(s_user1.addr, s_initialBalanceUser1TokenB);
        s_tokenB.mint(s_user2.addr, s_initialBalanceUser2TokenB);
        s_tokenC.mint(s_user1.addr, s_initialBalanceUser1TokenA);
        s_tokenC.mint(s_user2.addr, s_initialBalanceUser2TokenA);
        s_addLiquidityTest = new AddLiquidityTest();
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

    function liquidityLimitCalculation(uint256 _liquidityBurn, uint256 _liquidity) public returns (uint256) {
        _liquidityBurn = bound(_liquidityBurn, 1 * (10 ** 18), _liquidity);
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

        _amountTokenAMinWithdraw = bound(_amountTokenAMinWithdraw, 1 * (10 ** 13), _amountTokenAWithdrawMax);

        _amountTokenBMinWithdraw =
            bound(_amountTokenBMinWithdraw, 1 * (10 ** 13), (_amountTokenAMinWithdraw * _amountTokenB) / _amountTokenA);

        return (_amountTokenAMinWithdraw, _amountTokenBMinWithdraw);
    }

    function deadlineLimitCalculation(uint256 _deadlineWithdraw) public returns (uint256) {
        _deadlineWithdraw = bound(_deadlineWithdraw, 5, 3600);
        _deadlineWithdraw = block.timestamp + _deadlineWithdraw;
        return _deadlineWithdraw;
    }

    function testRemoveLiquidityTransferAmounts(
        uint256 _amountTokenADesiredDeposit,
        uint256 _amountTokenBDesiredDeposit,
        uint256 _amountTokenAMinDeposit,
        uint256 _amountTokenBMinDeposit,
        uint256 _deadlineDeposit,
        uint256 _liquidityBurn,
        uint256 _amountTokenAMinWithdraw,
        uint256 _amountTokenBMinWithdraw,
        uint256 _deadlineWithdraw
    ) external {
        (
            _amountTokenADesiredDeposit,
            _amountTokenBDesiredDeposit,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _deadlineDeposit
        ) = s_addLiquidityTest.addLiquiditySetUp(
            _amountTokenADesiredDeposit,
            _amountTokenBDesiredDeposit,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _deadlineDeposit
        );
        s_addLiquidityTest._tokenApproval(address(s_tokenA), address(s_tokenB), s_user1.addr, address(s_router));
        (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) = callAddLiquidity(
            address(s_tokenA),
            address(s_tokenB),
            _amountTokenADesiredDeposit,
            _amountTokenBDesiredDeposit,
            _amountTokenAMinDeposit,
            _amountTokenBMinDeposit,
            _deadlineDeposit,
            s_user1.addr
        );

        address _pairAddress = Utils.getPairAddress(address(s_factory), address(s_tokenA), address(s_tokenB));
        _liquidityBurn = liquidityLimitCalculation(_liquidityBurn, _liquidity);
        (_amountTokenAMinWithdraw, _amountTokenBMinWithdraw) = tokenAmountLimitCalculation(
            _liquidityBurn,
            _amountTokenAMinWithdraw,
            _amountTokenBMinWithdraw,
            _amountTokenA,
            _amountTokenB,
            _pairAddress
        );
        _deadlineWithdraw = deadlineLimitCalculation(_deadlineWithdraw);

        vm.startPrank(s_user1.addr);
        IERC20(_pairAddress).approve(address(s_router), _liquidityBurn);
        vm.stopPrank();
        vm.startPrank(s_user1.addr);
        (uint256 _withdrawnTokenA, uint256 _withdrawnTokenB) = s_router.removeLiquidity(
            address(s_tokenA),
            address(s_tokenB),
            _amountTokenAMinWithdraw,
            _amountTokenBMinWithdraw,
            _liquidityBurn,
            s_user1.addr,
            _deadlineWithdraw
        );
        vm.stopPrank();
    }
}
