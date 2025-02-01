// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Fenwick {
    function suffixSum(mapping(uint256 => uint256) storage self, uint256 len, uint256 index) internal view returns (uint256 sum) {
        while (index <= len) {
            sum += self[index - 1];
            index += lsb(index);
        }
    }

    function rangeSum(mapping(uint256 => uint256) storage self, uint256 len, uint256 l, uint256 r) internal view returns (uint256) {
        return suffixSum(self, len, l) - (r < len ? suffixSum(self, len, r + 1) : 0);
    }

    function increment(uint256[] storage self, uint256 index, uint256 delta) internal {
        while (index > 0) {
            self[index - 1] += delta;
            index -= lsb(index);
        }
    }

    // Least significant bit
    function lsb(uint256 i) internal pure returns (uint256) {
        // "i & (-i)"
        return
            i &
            ((i ^
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) +
                1);
    }
}