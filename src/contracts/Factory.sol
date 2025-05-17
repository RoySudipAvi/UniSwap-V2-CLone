//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFactory} from "src/interfaces/IFactory.sol";
import {Utils, Errors} from "src/libraries/Utils.sol";
import {Pair, IPair} from "src/contracts/Pair.sol";
import {console} from "forge-std/console.sol";

/// @title The Factory Contract
/// @notice contract to create a new token pair address from two tokens
/// @notice This function replicates the uniswap v2 factory contract
/// @notice It omits the section of protocol fee
/// @custom:experimental This is an experimental contract
contract Factory is IFactory {
    mapping(address _tokenA => mapping(address _tokenB => address _pairAddress)) private s_tokenPairAddress;
    address[] private s_allPairAddresses;

    event PairCreated(address indexed _tokenA, address indexed _tokenB, address indexed _pairAddress);

    /// @notice This function creates the token pair address
    /// @notice It can be called from end user, any other contract or
    /// @notice it gets called by router contract while trying to add liquidity to a new pool
    /// @dev It uses CREATE2 to deploy the pair contract, it does so to create deterministic addresses
    /// @dev that can be used during add or remove liqidity and token swaps
    /// @dev the create2 first reads the size of the bytecode using mload, the size is stored in memory
    /// @dev in the first 32 bytes, then it goes to the start of the actual bytecode, by adding 32 bytes
    /// @dev it then calculates the actual bytecode based on tha starting point and the size
    /// @param _tokenA first token
    /// @param _tokenB  second token
    /// @return _pairAddress pair address
    function createPair(address _tokenA, address _tokenB) external returns (address _pairAddress) {
        (address _token0, address _token1) = Utils.sortTokens(_tokenA, _tokenB);
        require(s_tokenPairAddress[_token0][_token1] == address(0), Errors.PairAddressExists());
        bytes memory _bytecode = type(Pair).creationCode;
        bytes32 _salt = keccak256(abi.encodePacked(_token0, _token1));
        assembly {
            _pairAddress := create2(0, add(_bytecode, 32), mload(_bytecode), _salt)
        }
        require(_pairAddress != address(0), Errors.InvalidAddress());
        s_tokenPairAddress[_token0][_token1] = _pairAddress;
        s_tokenPairAddress[_token1][_token0] = _pairAddress;
        s_allPairAddresses.push(_pairAddress);
        console.log("factory tokens:", _token0, _token1);
        console.log("factory pair: ", _pairAddress);
        IPair(_pairAddress).initialize(_token0, _token1);
        emit PairCreated(_token0, _token1, _pairAddress);
    }

    /// @notice get the pair address of two tokens
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @return _pairAddress the pair address
    function getPairAddress(address _tokenA, address _tokenB) external view returns (address _pairAddress) {
        return s_tokenPairAddress[_tokenA][_tokenB];
    }
}
