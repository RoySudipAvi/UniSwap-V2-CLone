//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Pair Interface
/// @notice This interface is used to call pair contract functions
interface IPair {
    /// @notice this function can only be called from factory contract
    /// @notice createPair function of factory initializes this pair address with it's respective tokens
    /// @param _tokenA First token
    /// @param _tokenB second token
    function initialize(address _tokenA, address _tokenB) external;

    /// @notice this function returns the reserves of tokens and last timestamp when they were updated
    /// @return _reserveTokenA reserve of tokenA
    /// @return _reserveTokenB reserve of tokenB
    /// @return _lastBlockTimestamp last update block timestamp
    function getReserves()
        external
        view
        returns (uint112 _reserveTokenA, uint112 _reserveTokenB, uint32 _lastBlockTimestamp);

    /// @notice this function mints the liquidity token based on liquidity provided
    /// @param _to address to which token will be minted
    /// @return _liquidity amount of token minted
    function mint(address _to) external returns (uint256 _liquidity);

    /// @notice this function burns the liquidity token and returns the original tokens to the provider
    /// @param _to address to which token will be minted
    /// @return _amountTokenA the first token
    /// @return _amountTokenB the second token
    function burn(address _to) external returns (uint256 _amountTokenA, uint256 _amountTokenB);

    function swap(uint256 _amount0Out, uint256 _amount1Out, address _to) external;

    function MINIMUM_LIQUIDITY() external returns (uint256);
}
