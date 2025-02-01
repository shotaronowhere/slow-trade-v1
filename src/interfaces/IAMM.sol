// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAMM {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function totalSupply() external view returns (uint256);
    
    /// @dev Buy outcome tokens.
    /// @param _outcomeOut Amount of outcome tokens to buy.
    function buy(uint256 _outcomeOut) external;

    /// @dev Sell outcome tokens.
    /// @param _outcomeIn Amount of tokens to sell.
    function sell(uint256 _outcomeIn) external;

    /// @dev Add liquidity.
    function addLiquidity(uint256 _underlyingToAdd) external;

    /// @dev Remove liquidity.
    function removeLiquidity(uint256 _amount) external;
}
