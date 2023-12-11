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
    address public walletZ;

    ICooler public coolerA;
    ICooler public coolerB;
    ICooler public coolerC;
    ICooler public coolerZ;

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
        walletZ = vm.addr(0xD);

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

        vm.startPrank(walletZ);
        // Deploy a cooler for walletZ
        address coolerZ_ = coolerFactory.generateCooler(gohm, dai);
        coolerZ = ICooler(coolerZ_);
        vm.stopPrank();
    }

    // --- consolidateLoansFromSingleCooler ----------------------------------------

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

        // -------------------------------------------------------------------------
        //           NECESSARY USER SETUP BEFORE CALLING CONSOLIDATION
        // -------------------------------------------------------------------------

        // Ensure that walletA has enough DAI to consolidate
        (address owner, uint256 gohmApproval, uint256 daiApproval, ) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(dai), walletA, daiApproval);
        assertEq(owner, walletA);

        vm.startPrank(walletA);

        // Grant necessary approvals
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);

        // -------------------------------------------------------------------------

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
        assertEq(dai.allowance(address(walletA), address(utils)), 0);
        assertEq(gohm.allowance(address(walletA), address(utils)), 0);
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

        // -------------------------------------------------------------------------
        //           NECESSARY USER SETUP BEFORE CALLING CONSOLIDATION
        // -------------------------------------------------------------------------

        // Ensure that walletA has enough sDAI to consolidate (and get rid of DAI to avoid confusion)
        (address owner, uint256 gohmApproval, , uint256 sdaiApproval ) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(sdai), walletA, sdaiApproval);
        deal(address(dai), walletA, 0);
        assertEq(owner, walletA);

        vm.startPrank(walletA);

        // Grant necessary approvals
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);

        // -------------------------------------------------------------------------

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
        assertEq(sdai.allowance(address(walletA), address(utils)), 0);
        assertEq(gohm.allowance(address(walletA), address(utils)), 0);
    }

    // --- consolidateLoansFromMultipleCoolers -------------------------------------

    function test_consolidateLoansFromMultipleCoolers_DAI_all() public {
        uint256[] memory idsA = _idsA();
        uint256[] memory idsB = _idsB();
        uint256[] memory idsC = _idsC();
        uint256 initPrincipal = dai.balanceOf(walletA) + dai.balanceOf(walletB) + dai.balanceOf(walletC);

        // Check that coolerA has 3 open loans
        ICooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB has 2 open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 600 * 1e18);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 400 * 1e18);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has 1 open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 500 * 1e18);
        vm.expectRevert();
        loan = coolerC.getLoan(1);

        // -------------------------------------------------------------------------
        //           NECESSARY USER SETUP BEFORE CALLING CONSOLIDATION
        // -------------------------------------------------------------------------

        // Ensure that walletA has enough DAI to consolidate and grant necessary approvals
        (address owner, uint256 gohmApproval, uint256 daiApproval, ) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(dai), walletA, daiApproval);
        assertEq(owner, walletA);

        vm.startPrank(walletA);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletB has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerB), idsB);
        deal(address(dai), walletB, daiApproval);
        assertEq(owner, walletB);

        vm.startPrank(walletB);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletC has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerC), idsC);
        deal(address(dai), walletC, daiApproval);
        assertEq(owner, walletC);

        vm.startPrank(walletC);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // -------------------------------------------------------------------------

        CoolerUtils.Batch[] memory batches = new CoolerUtils.Batch[](3);
        batches[0] = CoolerUtils.Batch(false, address(coolerA), idsA);
        batches[1] = CoolerUtils.Batch(false, address(coolerB), idsB);
        batches[2] = CoolerUtils.Batch(false, address(coolerC), idsC);

        // Consolidate loans for coolerA
        utils.consolidateLoansFromMultipleCoolers(address(coolerC), address(clearinghouse), batches);

        // Check that coolerA doesn't have open loans
        loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB doesn't have open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 0);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has a single open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerC.getLoan(1);
        assertEq(loan.collateral, (3_333 + 1_000 + 500) * 1e18);

        // Check token balances
        assertEq(dai.balanceOf(walletA), 0);
        assertEq(dai.balanceOf(walletB), 0);
        assertEq(dai.balanceOf(walletC), initPrincipal);
        assertEq(gohm.balanceOf(address(coolerA)), 0);
        assertEq(gohm.balanceOf(address(coolerB)),0);
        assertEq(gohm.balanceOf(address(coolerC)), (3_333 + 1_000 + 500) * 1e18);
        // Check allowances
        assertEq(dai.allowance(address(walletA), address(utils)), 0);
        assertEq(gohm.allowance(address(walletA), address(utils)), 0);
        assertEq(dai.allowance(address(walletB), address(utils)), 0);
        assertEq(gohm.allowance(address(walletB), address(utils)), 0);
        assertEq(dai.allowance(address(walletC), address(utils)), 0);
        assertEq(gohm.allowance(address(walletC), address(utils)), 0);
    }

    function test_consolidateLoansFromMultipleCoolers_sDAI_all() public {
        uint256[] memory idsA = _idsA();
        uint256[] memory idsB = _idsB();
        uint256[] memory idsC = _idsC();
        uint256 initPrincipal = dai.balanceOf(walletA) + dai.balanceOf(walletB) + dai.balanceOf(walletC);

        // Check that coolerA has 3 open loans
        ICooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB has 2 open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 600 * 1e18);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 400 * 1e18);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has 1 open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 500 * 1e18);
        vm.expectRevert();
        loan = coolerC.getLoan(1);

        // -------------------------------------------------------------------------
        //           NECESSARY USER SETUP BEFORE CALLING CONSOLIDATION
        // -------------------------------------------------------------------------

        // Ensure that walletA has enough DAI to consolidate and grant necessary approvals
        (address owner, uint256 gohmApproval, , uint256 sdaiApproval) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(sdai), walletA, sdaiApproval);
        deal(address(dai), walletA, 0);
        assertEq(owner, walletA);

        vm.startPrank(walletA);
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletB has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, , sdaiApproval) = utils.requiredApprovals(address(coolerB), idsB);
        deal(address(sdai), walletB, sdaiApproval);
        deal(address(dai), walletB, 0);
        assertEq(owner, walletB);

        vm.startPrank(walletB);
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletC has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, , sdaiApproval) = utils.requiredApprovals(address(coolerC), idsC);
        deal(address(sdai), walletC, sdaiApproval);
        deal(address(dai), walletC, 0);
        assertEq(owner, walletC);

        vm.startPrank(walletC);
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // -------------------------------------------------------------------------

        CoolerUtils.Batch[] memory batches = new CoolerUtils.Batch[](3);
        batches[0] = CoolerUtils.Batch(true, address(coolerA), idsA);
        batches[1] = CoolerUtils.Batch(true, address(coolerB), idsB);
        batches[2] = CoolerUtils.Batch(true, address(coolerC), idsC);

        // Consolidate loans for coolerA
        utils.consolidateLoansFromMultipleCoolers(address(coolerC), address(clearinghouse), batches);

        // Check that coolerA doesn't have open loans
        loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB doesn't have open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 0);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has a single open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerC.getLoan(1);
        assertEq(loan.collateral, (3_333 + 1_000 + 500) * 1e18);

        // Check token balances
        assertEq(dai.balanceOf(walletA), 0);
        assertEq(dai.balanceOf(walletB), 0);
        assertEq(dai.balanceOf(walletC), initPrincipal);
        assertEq(sdai.balanceOf(walletA), 0);
        assertEq(sdai.balanceOf(walletB), 0);
        assertEq(sdai.balanceOf(walletC), 0);
        assertEq(gohm.balanceOf(address(coolerA)), 0);
        assertEq(gohm.balanceOf(address(coolerB)),0);
        assertEq(gohm.balanceOf(address(coolerC)), (3_333 + 1_000 + 500) * 1e18);
        // Check allowances
        assertEq(sdai.allowance(address(walletA), address(utils)), 0);
        assertEq(gohm.allowance(address(walletA), address(utils)), 0);
        assertEq(sdai.allowance(address(walletB), address(utils)), 0);
        assertEq(gohm.allowance(address(walletB), address(utils)), 0);
        assertEq(sdai.allowance(address(walletC), address(utils)), 0);
        assertEq(gohm.allowance(address(walletC), address(utils)), 0);
    }

    function test_consolidateLoansFromMultipleCoolers_DAI_some_sDAI_some() public {
        uint256[] memory idsA = _idsA();
        uint256[] memory idsB = _idsB();
        uint256[] memory idsC = _idsC();
        uint256 initPrincipal = dai.balanceOf(walletA) + dai.balanceOf(walletB) + dai.balanceOf(walletC);

        // Check that coolerA has 3 open loans
        ICooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB has 2 open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 600 * 1e18);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 400 * 1e18);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has 1 open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 500 * 1e18);
        vm.expectRevert();
        loan = coolerC.getLoan(1);

        // -------------------------------------------------------------------------
        //           NECESSARY USER SETUP BEFORE CALLING CONSOLIDATION
        // -------------------------------------------------------------------------

        // Ensure that walletA has enough DAI to consolidate and grant necessary approvals
        (address owner, uint256 gohmApproval, uint256 daiApproval, uint256 sdaiApproval) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(dai), walletA, daiApproval);
        assertEq(owner, walletA);

        vm.startPrank(walletA);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletB has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, , sdaiApproval) = utils.requiredApprovals(address(coolerB), idsB);
        deal(address(sdai), walletB, sdaiApproval);
        deal(address(dai), walletB, 0);
        assertEq(owner, walletB);

        vm.startPrank(walletB);
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletC has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, , sdaiApproval) = utils.requiredApprovals(address(coolerC), idsC);
        deal(address(sdai), walletC, sdaiApproval);
        deal(address(dai), walletC, 0);
        assertEq(owner, walletC);

        vm.startPrank(walletC);
        sdai.approve(address(utils), sdaiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // -------------------------------------------------------------------------

        CoolerUtils.Batch[] memory batches = new CoolerUtils.Batch[](3);
        batches[0] = CoolerUtils.Batch(false, address(coolerA), idsA);
        batches[1] = CoolerUtils.Batch(true, address(coolerB), idsB);
        batches[2] = CoolerUtils.Batch(true, address(coolerC), idsC);

        // Consolidate loans for coolerA
        utils.consolidateLoansFromMultipleCoolers(address(coolerC), address(clearinghouse), batches);

        // Check that coolerA doesn't have open loans
        loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 0);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 0);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB doesn't have open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 0);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has a single open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 0);
        loan = coolerC.getLoan(1);
        assertEq(loan.collateral, (3_333 + 1_000 + 500) * 1e18);

        // Check token balances
        assertEq(dai.balanceOf(walletA), 0);
        assertEq(dai.balanceOf(walletB), 0);
        assertEq(dai.balanceOf(walletC), initPrincipal);
        assertEq(sdai.balanceOf(walletB), 0);
        assertEq(sdai.balanceOf(walletC), 0);
        assertEq(gohm.balanceOf(address(coolerA)), 0);
        assertEq(gohm.balanceOf(address(coolerB)),0);
        assertEq(gohm.balanceOf(address(coolerC)), (3_333 + 1_000 + 500) * 1e18);
        // Check allowances
        assertEq(sdai.allowance(address(walletA), address(utils)), 0);
        assertEq(gohm.allowance(address(walletA), address(utils)), 0);
        assertEq(sdai.allowance(address(walletB), address(utils)), 0);
        assertEq(gohm.allowance(address(walletB), address(utils)), 0);
        assertEq(sdai.allowance(address(walletC), address(utils)), 0);
        assertEq(gohm.allowance(address(walletC), address(utils)), 0);
    }

    function testRevert_consolidateLoansFromMultipleCoolers_invalidTarget() public {
        uint256[] memory idsA = _idsA();
        uint256[] memory idsB = _idsB();
        uint256[] memory idsC = _idsC();
        uint256 initPrincipal = dai.balanceOf(walletA) + dai.balanceOf(walletB) + dai.balanceOf(walletC);

        // Check that coolerA has 3 open loans
        ICooler.Loan memory loan = coolerA.getLoan(0);
        assertEq(loan.collateral, 2_000 * 1e18);
        loan = coolerA.getLoan(1);
        assertEq(loan.collateral, 1_000 * 1e18);
        loan = coolerA.getLoan(2);
        assertEq(loan.collateral, 333 * 1e18);
        vm.expectRevert();
        loan = coolerA.getLoan(3);
        // Check that coolerB has 2 open loans
        loan = coolerB.getLoan(0);
        assertEq(loan.collateral, 600 * 1e18);
        loan = coolerB.getLoan(1);
        assertEq(loan.collateral, 400 * 1e18);
        vm.expectRevert();
        loan = coolerB.getLoan(2);
        // Check that coolerC has 1 open loan
        loan = coolerC.getLoan(0);
        assertEq(loan.collateral, 500 * 1e18);
        vm.expectRevert();
        loan = coolerC.getLoan(1);

        // -------------------------------------------------------------------------
        //           NECESSARY USER SETUP BEFORE CALLING CONSOLIDATION
        // -------------------------------------------------------------------------

        // Ensure that walletA has enough DAI to consolidate and grant necessary approvals
        (address owner, uint256 gohmApproval, uint256 daiApproval, ) = utils.requiredApprovals(address(coolerA), idsA);
        deal(address(dai), walletA, daiApproval);
        assertEq(owner, walletA);

        vm.startPrank(walletA);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletB has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerB), idsB);
        deal(address(dai), walletB, daiApproval);
        assertEq(owner, walletB);

        vm.startPrank(walletB);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // Ensure that walletC has enough DAI to consolidate and grant necessary approvals
        (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerC), idsC);
        deal(address(dai), walletC, daiApproval);
        assertEq(owner, walletC);

        vm.startPrank(walletC);
        dai.approve(address(utils), daiApproval);
        gohm.approve(address(utils), gohmApproval);
        vm.stopPrank();

        // -------------------------------------------------------------------------

        CoolerUtils.Batch[] memory batches = new CoolerUtils.Batch[](3);
        batches[0] = CoolerUtils.Batch(false, address(coolerA), idsA);
        batches[1] = CoolerUtils.Batch(false, address(coolerB), idsB);
        batches[2] = CoolerUtils.Batch(false, address(coolerC), idsC);

        // Attempt to consolidate loans into an invalid target
        vm.expectRevert(CoolerUtils.InvalidTargetCooler.selector);
        utils.consolidateLoansFromMultipleCoolers(address(coolerZ), address(clearinghouse), batches);
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