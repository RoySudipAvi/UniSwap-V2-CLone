//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Factory} from "src/contracts/Factory.sol";
import {Router} from "src/contracts/Router.sol";
import {WETH} from "test/mocks/WETH.sol";

contract FactoryRouterDeployment is Script {
    Factory private s_factory;
    Router private s_router;
    WETH private s_wETH;

    function run() external returns (WETH, Factory, Router) {
        vm.startBroadcast();
        s_factory = new Factory();
        s_wETH = new WETH();
        s_router = new Router(address(s_factory), address(s_wETH));
        vm.stopBroadcast();
        return (s_wETH, s_factory, s_router);
    }
}
