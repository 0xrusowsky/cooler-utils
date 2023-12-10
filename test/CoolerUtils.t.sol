// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";

import { IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool } from "src/interfaces/aave-v3/IFlashLoanSimpleReceiver.sol";
import { IClearinghouse } from "src/interfaces/olympus-v3/IClearinghouse.sol";
import { ICoolerFactory } from "src/interfaces/olympus-v3/ICoolerFactory.sol";
import { ICooler } from "src/interfaces/olympus-v3/ICooler.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import {CoolerUtils} from "src/CoolerUtils.sol";

contract CoolerUtilsTest is Test {
    CoolerUtils public utils;

    ICoolerFactory public coolerFactory;
    IClearinghouse public clearinghouse;
    IERC20 public gohm;
    IERC20 public dai;
    IERC4626 public sdai;
    address public aave;

    address public walletA;
    address public walletB;
    address public walletC;

    ICooler public coolerA;
    ICooler public coolerB;
    ICooler public coolerC;

    function setUp() public {
        // Mainnet Fork at current block.
        vm.createSelectFork(vm.rpcUrl("MAINNET"));

        // Required Contracts
        coolerFactory = ICoolerFactory(0x30Ce56e80aA96EbbA1E1a74bC5c0FEB5B0dB4216);
        clearinghouse = IClearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);
        gohm = IERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        sdai = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
        aave = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

        // Deploy CoolerUtils
        utils = new CoolerUtils(
            aave,
            address(dai),
            address(sdai),
            address(gohm)
        );

        walletA = vm.addr(0xA);
        walletB = vm.addr(0xB);
        walletC = vm.addr(0xC);

        // Fund wallets with gOHM
        deal(address(gohm), walletA, 3_333 * 1e18);
        deal(address(gohm), walletB, 1_000 * 1e18);
        deal(address(gohm), walletC, 500 * 1e18);

        // Ensure Clearinghouse has enough DAI
        deal(address(dai), address(clearinghouse), 18_000_000 * 1e18);

        vm.startPrank(walletA);
        // Deploy a cooler for walletA
        address coolerA_ = coolerFactory.generateCooler(gohm, dai);
        coolerA = ICooler(coolerA_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), 3_333 * 1e18);
        // Loan 0 for coolerA (collateral: 2,000 gOHM)
        (uint256 loan,) = clearinghouse.getLoanForCollateral(2_000 * 1e18);
        clearinghouse.lendToCooler(coolerA, loan);
        // Loan 1 for coolerA (collateral: 1,000 gOHM)
        (loan,) = clearinghouse.getLoanForCollateral(1_000 * 1e18);
        clearinghouse.lendToCooler(coolerA, loan);
        // Loan 2 for coolerA (collateral: 333 gOHM)
        (loan,) = clearinghouse.getLoanForCollateral(333 * 1e18);
        clearinghouse.lendToCooler(coolerA, loan);
        vm.stopPrank();

        vm.startPrank(walletB);
        // Deploy a cooler for walletB
        address coolerB_ = coolerFactory.generateCooler(gohm, dai);
        coolerB = ICooler(coolerB_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), 1_000 * 1e18);
        // Loan 0 for coolerB (collateral: 600 gOHM)
        (loan, ) = clearinghouse.getLoanForCollateral(600 * 1e18);
        clearinghouse.lendToCooler(coolerB, loan);
        // Loan 1 for coolerB (collateral: 400 gOHM)
        (loan, ) = clearinghouse.getLoanForCollateral(400 * 1e18);
        clearinghouse.lendToCooler(coolerB, loan);
        vm.stopPrank();

        vm.startPrank(walletC);
        // Deploy a cooler for walletC
        address coolerC_ = coolerFactory.generateCooler(gohm, dai);
        coolerC = ICooler(coolerC_);

        // Approve clearinghouse to spend gOHM
        gohm.approve(address(clearinghouse), 500 * 1e18);
        // Loan 0 for coolerC (collateral: 500 gOHM)
        (loan, ) = clearinghouse.getLoanForCollateral(500 * 1e18);
        clearinghouse.lendToCooler(coolerC, loan);
        vm.stopPrank();
    }
}