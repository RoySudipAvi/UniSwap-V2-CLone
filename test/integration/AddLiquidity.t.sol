//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Utils, Errors, Router, IWETH, SafeTransferLib} from "src/contracts/Router.sol";
import {Pair, IPair, IFactory, Factory} from "src/contracts/Factory.sol";
import {WETH, FactoryRouterDeployment} from "script/deployments/FactoryRouter.s.sol";
import {MockToken} from "test/mocks/MockToken.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {FixedPointMathLib} from "@solady/contracts/utils/FixedPointMathLib.sol";

contract AddLiquidityTest is Test {
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

    event Mint(
        address indexed _sender, uint256 indexed _amountTokenA, uint256 indexed _amountTokenB, uint256 _liquidity
    );

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
    }

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
            address(s_tokenA),
            address(s_tokenB),
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
            address(s_tokenA),
            address(s_tokenB),
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            _to,
            _deadline
        );
        vm.stopPrank();
    }

    function addLiquiditySetUp(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline
    ) public view returns (uint256, uint256, uint256, uint256, uint256) {
        _deadline = bound(_deadline, 5, 3600);
        _deadline = block.timestamp + _deadline;
        vm.assume(_amountTokenAMin > 0);
        vm.assume(_amountTokenBMin > 0);
        _amountTokenAMin = bound(_amountTokenAMin, 1 * (10 ** 18), s_initialBalanceUser1TokenA - 1);
        _amountTokenBMin = bound(_amountTokenBMin, 1 * (10 ** 18), s_initialBalanceUser1TokenB - 1);
        _amountTokenADesired = bound(_amountTokenADesired, _amountTokenAMin, s_initialBalanceUser1TokenA);
        _amountTokenBDesired = bound(_amountTokenBDesired, _amountTokenBMin, s_initialBalanceUser1TokenB);

        return (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
    }

    function _tokenApproval(address _tokenA, address _tokenB, address _to, address _router) public {
        vm.startPrank(_to);
        IERC20(_tokenA).approve(_router, s_initialBalanceUser1TokenA);
        IERC20(_tokenB).approve(_router, s_initialBalanceUser1TokenB);
        vm.stopPrank();
    }

    function testAddLiquidityUpdateReserves(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline
    ) external {
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) =
            addLiquiditySetUp(_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
        _tokenApproval(address(s_tokenA), address(s_tokenB), s_user1.addr, address(s_router));
        address _pairAddress = Utils.getPairAddress(address(s_factory), address(s_tokenA), address(s_tokenB));
        uint256 _pairContractBalanceTokenA = IERC20(address(s_tokenA)).balanceOf(_pairAddress);
        uint256 _pairContractBalanceTokenB = IERC20(address(s_tokenB)).balanceOf(_pairAddress);
        vm.startPrank(s_user1.addr);
        (uint256 _amountTokenA, uint256 _amountTokenB,) = s_router.addLiquidity(
            address(s_tokenA),
            address(s_tokenB),
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            s_user1.addr,
            _deadline
        );
        vm.stopPrank();
        uint112 _reserveTokenA = uint112(_pairContractBalanceTokenA + _amountTokenA);
        uint112 _reserveTokenB = uint112(_pairContractBalanceTokenB + _amountTokenB);
        (uint112 _getReservesTokenA, uint112 _getReservesTokenB,) = Pair(_pairAddress).getReserves();
        assertEq(_reserveTokenA, _getReservesTokenA);
        assertEq(_reserveTokenB, _getReservesTokenB);
    }

    function testAddLiquidityLiquidityToken(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline
    ) external {
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) =
            addLiquiditySetUp(_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
        _tokenApproval(address(s_tokenA), address(s_tokenB), s_user1.addr, address(s_router));
        address _pairAddress = Utils.getPairAddress(address(s_factory), address(s_tokenA), address(s_tokenB));
        vm.startPrank(s_user1.addr);
        (,, uint256 _liquidity) = s_router.addLiquidity(
            address(s_tokenA),
            address(s_tokenB),
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            s_user1.addr,
            _deadline
        );
        vm.stopPrank();
        assertEq(IERC20(_pairAddress).balanceOf(s_user1.addr), _liquidity);
    }

    function _addLiquidityCalculation(
        address _tokenA,
        address _tokenB,
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        address _pairAddress
    ) public returns (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) {
        IFactory(address(s_factory)).createPair(_tokenA, _tokenB);
        _amountTokenA = _amountTokenADesired;
        _amountTokenB = _amountTokenBDesired;
        _liquidity = (_amountTokenA * _amountTokenB).sqrt() - IPair(_pairAddress).MINIMUM_LIQUIDITY();
    }

    function testAddLiquidityEmitEvent(
        uint256 _amountTokenADesired,
        uint256 _amountTokenBDesired,
        uint256 _amountTokenAMin,
        uint256 _amountTokenBMin,
        uint256 _deadline
    ) external {
        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) =
            addLiquiditySetUp(_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
        _tokenApproval(address(s_tokenC), address(s_tokenB), s_user1.addr, address(s_router));

        address _pairAddress = Utils.getPairAddress(address(s_factory), address(s_tokenC), address(s_tokenB));
        (uint256 _amountTokenA, uint256 _amountTokenB, uint256 _liquidity) = _addLiquidityCalculation(
            address(s_tokenC), address(s_tokenB), _amountTokenADesired, _amountTokenBDesired, _pairAddress
        );

        (_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline) =
            addLiquiditySetUp(_amountTokenADesired, _amountTokenBDesired, _amountTokenAMin, _amountTokenBMin, _deadline);
        _tokenApproval(address(s_tokenA), address(s_tokenB), s_user1.addr, address(s_router));

        vm.startPrank(s_user1.addr);
        vm.expectEmit(true, true, true, true);
        emit Mint(address(s_router), _amountTokenA, _amountTokenB, _liquidity);
        s_router.addLiquidity(
            address(s_tokenA),
            address(s_tokenB),
            _amountTokenADesired,
            _amountTokenBDesired,
            _amountTokenAMin,
            _amountTokenBMin,
            s_user1.addr,
            _deadline
        );
        vm.stopPrank();
    }
}
