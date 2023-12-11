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

    IERC20 public gohm;
    IERC20 public dai;
    IERC4626 public sdai;

    ICoolerFactory public coolerFactory;
    IClearinghouse public clearinghouse;
    address public aave;

    address public walletA;
    address public walletB;
    address public walletC;

    ICooler public coolerA;
    ICooler public coolerB;
    ICooler public coolerC;

    function setUp() public {
        // Mainnet Fork at current block.
        vm.createSelectFork(vm.rpcUrl("MAINNET"), 18762666);

        // Required Contracts
        coolerFactory = ICoolerFactory(0x30Ce56e80aA96EbbA1E1a74bC5c0FEB5B0dB4216);
        clearinghouse = IClearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);
        gohm = IERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        sdai = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
        aave = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

        // Deploy CoolerUtils
        utils = new CoolerUtils(
            address(dai),
            address(sdai),
            address(gohm),
            aave
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

    function test_consolidateLoansFromSingleCooler_DAI() public {
        uint256[] memory idsA = _idsA();
        uint256 initPrincipal = dai.balanceOf(walletA);

        // Check that coolerA has 3 open loans
        ICooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);

        // Ensure that walletA has enough DAI to consolidate
        (address owner, uint256 gohmApproval, uint256 daiApproval, ) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(dai), walletA, daiApproval);
        assertEq(owner, walletA);

        vm.startPrank(walletA);

        // Grant necessary approvals
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);

        // Consolidate loans for coolerA
        utils.consolidateLoansFromSingleCooler(address(coolerA), address(clearinghouse), idsA, false);

        // Check that coolerA has a single open loan
        loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(3);
        assertEq(loan.collateral, 3_333 * 1e18);
        // Check token balances
        assertEq(dai.balanceOf(walletA), initPrincipal);
        assertEq(gohm.balanceOf(address(coolerA)), 3_333 * 1e18);
        // Check allowances
        assertEq(dai.allowance(address(coolerA), address(utils)), 0);
        assertEq(gohm.allowance(address(coolerA), address(utils)), 0);
    }

    function test_consolidateLoansFromSingleCooler_sDAI() public {
        uint256[] memory idsA = _idsA();
        uint256 initPrincipal = dai.balanceOf(walletA);

        // Check that coolerA has 3 open loans
        ICooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);

        // Ensure that walletA has enough sDAI to consolidate (and get rid of DAI to avoid confusion)
        (address owner, uint256 gohmApproval, , uint256 sdaiApproval ) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(sdai), walletA, sdaiApproval);
        deal(address(dai), walletA, 0);
        assertEq(owner, walletA);

        vm.startPrank(walletA);

        // Grant necessary approvals
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);

        // Consolidate loans for coolerA
        utils.consolidateLoansFromSingleCooler(address(coolerA), address(clearinghouse), idsA, true);

        // Check that coolerA has a single open loan
        loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(3);
        assertEq(loan.collateral, 3_333 * 1e18);
        // Check token balances
        assertEq(sdai.balanceOf(walletA), 0);
        assertEq(dai.balanceOf(walletA), initPrincipal);
        assertEq(gohm.balanceOf(address(coolerA)), 3_333 * 1e18);
        // Check allowances
        assertEq(sdai.allowance(address(coolerA), address(utils)), 0);
        assertEq(gohm.allowance(address(coolerA), address(utils)), 0);
    }

    // --- AUX FUNCTIONS -----------------------------------------------------------

    function _idsA() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        return ids;
    }

    function _idsB() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        return ids;
    }

    function _idsC() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        return ids;
    }
}