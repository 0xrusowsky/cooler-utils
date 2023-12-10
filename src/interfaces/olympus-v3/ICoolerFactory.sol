// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface ICoolerFactory {

    function generateCooler(IERC20 collateral_, IERC20 debt_) external returns (address cooler);
}
