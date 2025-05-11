//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title The factory interface
/// @notice This interface is used to call factory contract functions
interface IFactory {
    /// @notice function for creating pair address of two tokens
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @return _pairAddress the pair address
    function createPair(address _tokenA, address _tokenB) external returns (address _pairAddress);

    /// @notice function for retrieving the pair address of two tokens
    /// @param _tokenA the first token
    /// @param _tokenB the second token
    /// @return _pairAddress the pair address
    function getPairAddress(address _tokenA, address _tokenB) external returns (address _pairAddress);
}
