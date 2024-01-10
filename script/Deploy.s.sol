// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {CoolerUtils} from "src/CoolerUtils.sol";

contract Deploy is Script {

    function run() public {
        // Setup
        address gohm = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
        address sdai = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address aave = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
        // Deploy contract
        vm.broadcast();
        CoolerUtils utils = new CoolerUtils(
            gohm,
            sdai,
            dai,
            aave
        );

        // Log outcome
        console2.log("Cooler Utils deployed at:", address(utils));
        console2.log("  >  gohm:", gohm);
        console2.log("  >  sdai:", sdai);
        console2.log("  >   dai:", dai);
        console2.log("  >  aave:", aave);
    }
}
