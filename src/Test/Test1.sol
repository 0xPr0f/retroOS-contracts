// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract Test {
    uint8 public x;

    function callData(uint8 number) public {
        x = number;
    }
}
