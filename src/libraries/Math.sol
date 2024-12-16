// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Math {
    /**
     * @dev Calculates the square root of a number. Uses the Babylonian Method.
     * @param x The input.
     * @return y The square root of the input.
     **/
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
