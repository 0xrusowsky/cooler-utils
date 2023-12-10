// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

contract CoolerUtils {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
