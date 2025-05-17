//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockToken} from "test/mocks/MockToken.sol";

contract HelperConfig is Script {
    int256 private constant WBTC_INTIAL_PRICE = 105000e8;
    int256 private constant LINK_INITIAL_PRICE = 20e8;
    int256 private constant DUMMY_INITIAL_PRICE = 1e8;
    uint8 private constant DECIMALS = 8;
    uint256 private constant LOCAL_CHAIN_ID = 31337;
    uint256 private constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address[3] private s_tokens;
    mapping(uint256 _chainId => mapping(address _token => address _priceFeed)) private s_tokenPriceFeed;

    constructor() {
        if (block.chainid == LOCAL_CHAIN_ID) {
            anvilConfig();
        } else {
            baseSepoliaConfig();
        }
    }

    function getTokens() external view returns (address[3] memory) {
        return s_tokens;
    }

    function getPriceFeedByToken(address _token) external view returns (address) {
        return s_tokenPriceFeed[block.chainid][_token];
    }

    function baseSepoliaConfig() private {
        s_tokens[0] = 0x4131600fd78Eb697413cA806A8f748edB959ddcd;
        s_tokens[1] = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
        s_tokens[2] = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        s_tokenPriceFeed[block.chainid][0x4131600fd78Eb697413cA806A8f748edB959ddcd] =
            0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298;
        s_tokenPriceFeed[block.chainid][0xE4aB69C077896252FAFBD49EFD26B5D171A32410] =
            0xb113F5A928BCfF189C998ab20d753a47F9dE5A61;
        s_tokenPriceFeed[block.chainid][0x036CbD53842c5426634e7929541eC2318f3dCF7e] =
            0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    }

    function anvilConfig() private {
        require(s_tokens[0] == address(0), "address already exists");
        vm.startBroadcast();
        MockToken _wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        MockToken _dummy = new MockToken("Dummy Token", "DT", 18);
        MockToken _link = new MockToken("Chainlink", "LINK", 18);
        MockV3Aggregator _wbtcUsd = new MockV3Aggregator(DECIMALS, WBTC_INTIAL_PRICE);
        MockV3Aggregator _linkUsd = new MockV3Aggregator(DECIMALS, LINK_INITIAL_PRICE);
        MockV3Aggregator _dummyUsd = new MockV3Aggregator(DECIMALS, DUMMY_INITIAL_PRICE);
        vm.stopBroadcast();
        s_tokens[0] = address(_wbtc);
        s_tokens[1] = address(_dummy);
        s_tokens[2] = address(_link);
        s_tokenPriceFeed[block.chainid][address(_wbtc)] = address(_wbtcUsd);
        s_tokenPriceFeed[block.chainid][address(_dummy)] = address(_dummyUsd);
        s_tokenPriceFeed[block.chainid][address(_link)] = address(_linkUsd);
    }
}
