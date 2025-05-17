//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Factory} from "src/contracts/Factory.sol";
import {Router} from "src/contracts/Router.sol";
import {HelperConfig} from "script/utils/HelperConfig.s.sol";
import {WETH} from "test/mocks/WETH.sol";

contract FactoryRouterDeployment is Script {
    Factory private s_factory;
    Router private s_router;
    HelperConfig private s_helperConfig;

    function run() external returns (Factory, Router, WETH, HelperConfig) {
        s_helperConfig = new HelperConfig();
        address[3] memory _tokens = s_helperConfig.getTokens();
        vm.startBroadcast();
        s_factory = new Factory();
        WETH _weth = new WETH();
        s_router = new Router(address(s_factory), address(_weth));
        vm.stopBroadcast();
        return (s_factory, s_router, _weth, s_helperConfig);
    }
}
