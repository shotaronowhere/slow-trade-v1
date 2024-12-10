// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Fenwick {
    function suffixSum(uint256[] storage self, uint256 index) internal view returns (uint256 sum) {
        while (index <= self.length) {
            sum += self[index - 1];
            index += lsb(index);
        }
    }

    function rangeSum(uint256[] storage self, uint256 l, uint256 r) internal view returns (uint256) {
        return suffixSum(self, l) - (r < self.length ? suffixSum(self, r + 1) : 0);
    }

    function append(uint256[] storage self, uint256 value) internal {
        self.push();
        increment(self, self.length, value);
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