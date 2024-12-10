// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/forge-std/src/Test.sol";
import "../src/libraries/Fenwick.sol";

contract FenwickTest is Test {
    using Fenwick for uint256[];

    uint256[] private tree;

    function setUp() public {
        // The tree starts empty, so no setup is needed
    }

    function testEmptyTree() public {
        assertEq(tree.length, 0, "Empty tree should have size 0");
       // assertEq(tree.suffixSum(0), 0, "Empty tree should have sum 0");
    }

    function testSingleAppend() public {
        tree.append(5);
        console.log("tree %d", tree[0]);
        assertEq(tree.length, 1, "Tree size should be 1 after single append");
        assertEq(tree.suffixSum(1), 5, "Prefix sum should be 5");
    }

    function testMultipleAppends() public {
        tree.append(5);
        tree.append(3); 
        tree.append(7);
        assertEq(tree.length, 3, "Tree size should be 3");
        console.log("tree %d", tree[0]);
        console.log("tree %d", tree[1]);
        console.log("tree %d", tree[2]);
        // 5 + 3 + 7 = 15
        assertEq(tree.suffixSum(1), 15, "Prefix sum up to index 3 should be 15");
        // 3 + 7 = 10   
        assertEq(tree.suffixSum(2), 10, "Prefix sum up to index 3 should be 15");
        // 7
        assertEq(tree.suffixSum(3), 7, "Prefix sum up to index 3 should be 15");
        // range sum
        // 5 + 3 = 8
        assertEq(tree.rangeSum(1, 2), 8, "Range sum from 1 to 2 should be 8");
        // 3 + 7 = 10
        assertEq(tree.rangeSum(2, 3), 10, "Range sum from 2 to 3 should be 10");
        // 5 + 3 + 7 = 15
        assertEq(tree.rangeSum(1, 3), 15, "Range sum from 1 to 3 should be 15");
    }

    function testLargeAppends() public {
        uint256 sum = 0;    
        for (uint256 i = 1; i <= 100; i++) {
            tree.append(i);
            sum += i;
        }
        assertEq(tree.length, 100, "Tree size should be 100");
        assertEq(tree.suffixSum(1), sum, "Sum of first 100 numbers should be 5050");
    }

    function testRangeSumEdgeCases() public {
        tree.append(5);
        tree.append(3);
        tree.append(7);
        tree.append(2);

        assertEq(tree.rangeSum(1, 1), 5, "Range sum of single element should be correct");
        assertEq(tree.rangeSum(1, 4), 17, "Range sum of entire array should be correct");
        assertEq(tree.rangeSum(2, 3), 10, "Range sum of middle elements should be correct");
    }

    function testAppendZero() public {
        tree.append(0);
        assertEq(tree.length, 1, "Tree size should be 1 after appending 0");
        assertEq(tree.suffixSum(1), 0, "Sum should be 0 after appending 0");
    }

    function testLSB() public {
        assertEq(Fenwick.lsb(1), 1, "LSB of 1 should be 1");
        assertEq(Fenwick.lsb(2), 2, "LSB of 2 should be 2");
        assertEq(Fenwick.lsb(3), 1, "LSB of 3 should be 1");
        assertEq(Fenwick.lsb(4), 4, "LSB of 4 should be 4");
        assertEq(Fenwick.lsb(7), 1, "LSB of 7 should be 1");
        assertEq(Fenwick.lsb(8), 8, "LSB of 8 should be 8");
    }

    function testSuffixSumOutOfBounds() public {
        tree.append(5);
        tree.append(3);
        // expect equals 0 
        assertEq(tree.suffixSum(3), 0, "Suffix sum should be 0");
    }

    function testRangeSumInvalidRange() public {
        tree.append(5);
        tree.append(3);
        tree.append(7);
        // expect equals 0 
        assertEq(tree.rangeSum(3, 2), 0, "Range sum should be 0");
    }

    function testIncrement() public {
        tree.append(5);
        tree.append(3);
        tree.append(7);

        // Increment the second element by 2
        tree.increment(2, 2);

        assertEq(tree.suffixSum(1), 17, "Total sum should be 17 after increment");
        assertEq(tree.suffixSum(2), 12, "Sum from index 2 should be 12 after increment");
        assertEq(tree.rangeSum(2, 2), 5, "Value at index 2 should be 5 after increment");
    }

    function testMultipleIncrements() public {
        tree.append(5);
        tree.append(3);
        tree.append(7);
        tree.append(2);

        tree.increment(1, 1);  // 6, 3, 7, 2
        tree.increment(3, 3);  // 6, 3, 10, 2
        tree.increment(4, 2);  // 6, 3, 10, 4

        assertEq(tree.suffixSum(1), 23, "Total sum should be 23 after increments");
        assertEq(tree.rangeSum(1, 4), 23, "Range sum should match total sum");
        assertEq(tree.rangeSum(2, 3), 13, "Range sum for middle elements should be correct");
    }

    function testIncrementFirstElement() public {
        tree.append(5);
        tree.append(3);
        tree.append(7);

        tree.increment(1, 10);

        assertEq(tree.suffixSum(1), 25, "Total sum should be 25 after incrementing first element");
        assertEq(tree.rangeSum(1, 1), 15, "First element should be 15 after increment");
    }

    function testIncrementLastElement() public {
        tree.append(5);
        tree.append(3);
        tree.append(7);

        tree.increment(3, 5);

        assertEq(tree.suffixSum(1), 20, "Total sum should be 20 after incrementing last element");
        assertEq(tree.rangeSum(3, 3), 12, "Last element should be 12 after increment");
    }

    function testFuzzIncrement(uint128[] memory values, uint256 index, uint128 delta) public {
        vm.assume(values.length > 0 && values.length <= 100);
        vm.assume(index > 0 && index <= values.length);
        
        uint256 originalSum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            tree.append(values[i]);
            originalSum += values[i];
        }

        uint256 originalValue = values[index - 1];
        tree.increment(index, delta);

        assertEq(tree.suffixSum(1), originalSum + delta, "Total sum should increase by delta after increment");
        assertEq(tree.rangeSum(index, index), originalValue + delta, "Incremented value should be correct");
    }

    function testIncrementOverflow() public {
        tree.append(type(uint256).max);
        
        // This should revert due to overflow
        vm.expectRevert();
        tree.increment(1, 1);
    }
}