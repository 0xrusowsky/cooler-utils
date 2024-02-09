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
    address public adai;

    address public walletA;
    address public walletB;
    address public walletC;
    address public walletD;
    address public walletE;
    address public walletF;
    address public walletG;
    address public walletH;
    address public walletZ;

    ICooler public coolerA;
    ICooler public coolerB;
    ICooler public coolerC;
    ICooler public coolerD;
    ICooler public coolerE;
    ICooler public coolerF;
    ICooler public coolerG;
    ICooler public coolerH;
    ICooler public coolerZ;

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
        adai = 0x018008bfb33d285247A21d44E50697654f754e63;

        // Deploy CoolerUtils
        utils = new CoolerUtils(
            address(gohm),
            address(sdai),
            address(dai),
            aave
        );

        // Inform user wallets that are owners of coolers
        walletA = vm.addr(0xA);
        walletB = vm.addr(0xB);
        walletC = vm.addr(0xC);
        walletD = vm.addr(0xD);
        walletE = vm.addr(0xE);
        walletF = vm.addr(0xF);
        walletG = vm.addr(0x1);
        walletH = vm.addr(0x2);
        walletZ = vm.addr(0x9);

        // Get cooler contracts owned by user wallets
        coolerA = ICooler(coolerFactory.getCoolerFor(walletA, gohm, dai));
        coolerB = ICooler(coolerFactory.getCoolerFor(walletB, gohm, dai));
        coolerC = ICooler(coolerFactory.getCoolerFor(walletC, gohm, dai));
        coolerD = ICooler(coolerFactory.getCoolerFor(walletD, gohm, dai));
        coolerE = ICooler(coolerFactory.getCoolerFor(walletE, gohm, dai));
        coolerF = ICooler(coolerFactory.getCoolerFor(walletF, gohm, dai));
        coolerG = ICooler(coolerFactory.getCoolerFor(walletG, gohm, dai));
        coolerH = ICooler(coolerFactory.getCoolerFor(walletH, gohm, dai));
    }

    // --- consolidateLoansWithoutFunds --------------------------------------------

    function test_userCheck() public {
        uint256[] memory idsA = _idsA();
        uint256[] memory idsB = _idsB();
        uint256[] memory idsC = _idsC();
        uint256[] memory idsD = _idsD();
        uint256[] memory idsE = _idsE();
        uint256[] memory idsF = _idsF();
        uint256[] memory idsG = _idsG();
        uint256[] memory idsH = _idsH();

        uint256 initPrincipal =
            gohm.balanceOf(coolerA) +
            gohm.balanceOf(coolerB) +
            gohm.balanceOf(coolerC) +
            gohm.balanceOf(coolerD) +
            gohm.balanceOf(coolerE) +
            gohm.balanceOf(coolerF) +
            gohm.balanceOf(coolerG) +
            gohm.balanceOf(coolerH);

        // -------------------------------------------------------------------------
        //                 NECESSARY USER SETUP BEFORE CONSOLIDATING
        // -------------------------------------------------------------------------

        uint256 totalDebt;
        uint256 totalCollateral;

        // Ensure that walletA grants gOHM approval
        console2.log("REQUIRED APPROVALS:");
        {
            (address owner, uint256 gohmApproval, uint256 daiApproval, ) = utils.requiredApprovals(address(coolerA), idsA);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletA);
            console2.log("Wallet A: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerA));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletA);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerA), walletZ);
            vm.stopPrank();

            // Ensure that walletB grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerB), idsB);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletB);
            console2.log("Wallet B: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerB));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletB);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerB), walletZ);
            vm.stopPrank();

            // Ensure that walletC grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerC), idsC);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletC);
            console2.log("Wallet C: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerC));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletC);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerC), walletZ);
            vm.stopPrank();

            // Ensure that walletD grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerD), idsD);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletD);
            console2.log("Wallet D: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerD));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletD);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerD), walletZ);
            vm.stopPrank();

            // Ensure that walletE grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerE), idsE);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletE);
            console2.log("Wallet E: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerE));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletE);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerE), walletZ);
            vm.stopPrank();

            // Ensure that walletF grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerF), idsF);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletF);
            console2.log("Wallet F: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerF));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletF);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerF), walletZ);
            vm.stopPrank();
            
            // Ensure that walletG grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerG), idsG);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletG);
            console2.log("Wallet G: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerG));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletG);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerG), walletZ);
            vm.stopPrank();

            // Ensure that walletH grants gOHM approval
            (owner, gohmApproval, daiApproval, ) = utils.requiredApprovals(address(coolerH), idsH);
            totalDebt += daiApproval;
            totalCollateral += gohmApproval;
            assertEq(owner, walletH);
            console2.log("Wallet H: ", owner);
            console2.log(" > gohm.approve()");
            console2.log("   - cooler utils:", address(utils));
            console2.log("   -  gohm amount:", gohmApproval);
            console2.log(" > utils.approve()");
            console2.log("   - cooler utils:", address(coolerH));
            console2.log("   - consolidator:", walletZ);
            console2.log("");

            vm.startPrank(walletH);
            gohm.approve(address(utils), gohmApproval);
            utils.approve(address(coolerH), walletZ);
            vm.stopPrank();
        }

        // Calculate flashloan requirements (in DAI)
        IPool POOL = IPool(IPoolAddressesProvider(aave).getPool());
        uint256 flashLoan = dai.balanceOf(adai) > totalDebt ? totalDebt : dai.balanceOf(adai);
        uint256 flashloanFee = flashLoan * POOL.FLASHLOAN_PREMIUM_TOTAL() / 10_000;
        uint256 availableFunds = totalDebt - flashLoan + flashloanFee;
        uint256 requiredApproval = flashLoan;

        // Owner of cooler where funds will be consolidated must grant approval for DAI
        vm.prank(walletA);
        dai.approve(address(utils), requiredApproval);
        console2.log(" > walletA:", walletA);
        console2.log("   - dai.approve()");
        console2.log("     - cooler utils:", address(utils));
        console2.log("     -  dai amount:", requiredApproval);
        console2.log("");
    
        // Ensure that walletZ has enough DAI to consolidate and grant necessary approval
        deal(address(dai), walletZ, availableFunds);
        vm.prank(walletZ);
        dai.approve(address(utils), availableFunds);
        console2.log(" > walletZ:", walletZ);
        console2.log("   - dai.approve()");
        console2.log("     - cooler utils:", address(utils));
        console2.log("     -  dai amount:", availableFunds);
        console2.log("");
        console2.log("REQUIRED FUNDS:");
        console2.log(" > walletZ:", walletZ);
        console2.log("   - dai amount:", availableFunds);
        console2.log("");


        // -------------------------------------------------------------------------

        CoolerUtils.BatchFashLoan[] memory batches = new CoolerUtils.BatchFashLoan[](8);
        batches[0] = CoolerUtils.BatchFashLoan(address(coolerA), idsA);
        batches[1] = CoolerUtils.BatchFashLoan(address(coolerB), idsB);
        batches[2] = CoolerUtils.BatchFashLoan(address(coolerC), idsC);
        batches[3] = CoolerUtils.BatchFashLoan(address(coolerD), idsD);
        batches[4] = CoolerUtils.BatchFashLoan(address(coolerE), idsE);
        batches[5] = CoolerUtils.BatchFashLoan(address(coolerF), idsF);
        batches[6] = CoolerUtils.BatchFashLoan(address(coolerG), idsG);
        batches[7] = CoolerUtils.BatchFashLoan(address(coolerH), idsH);

        // Consolidate loans for coolers A, B, and C into coolerC
        vm.prank(walletZ);
        utils.consolidateLoansWithoutFunds(address(coolerA), address(clearinghouse), batches, availableFunds, false);

        // -------------------------------------------------------------------------
        //                   CHECKS AFTER CONSOLIDATING LOANS
        // -------------------------------------------------------------------------

        ICooler.Loan memory loan;
        // Check that old loans are closed for coolerA
        for (uint256 i = 0; i < idsA.length; i++) {
            loan = coolerA.getLoan(idsA[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerB
        for (uint256 i = 0; i < idsB.length; i++) {
            loan = coolerB.getLoan(idsB[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerC
        for (uint256 i = 0; i < idsC.length; i++) {
            loan = coolerC.getLoan(idsC[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerD
        for (uint256 i = 0; i < idsD.length; i++) {
            loan = coolerC.getLoan(idsD[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerE
        for (uint256 i = 0; i < idsE.length; i++) {
            loan = coolerC.getLoan(idsE[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerF
        for (uint256 i = 0; i < idsF.length; i++) {
            loan = coolerC.getLoan(idsF[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerG
        for (uint256 i = 0; i < idsG.length; i++) {
            loan = coolerC.getLoan(idsG[i]);
            assertEq(loan.collateral, 0);
        }
        // Check that old loans are closed for coolerH
        for (uint256 i = 0; i < idsH.length; i++) {
            loan = coolerC.getLoan(idsH[i]);
            assertEq(loan.collateral, 0);
        }

        // Check that new loan is created for coolerA
        loan = coolerA.getLoan(idsA.length);
        assertEq(loan.collateral, totalCollateral);

        // Check token balances
        assertEq(dai.balanceOf(address(utils)), 0);
        assertEq(dai.balanceOf(walletA), initPrincipal - flashLoan);
        assertEq(dai.balanceOf(walletB), 0);
        assertEq(dai.balanceOf(walletC), 0);
        assertEq(dai.balanceOf(walletD), 0);
        assertEq(dai.balanceOf(walletE), 0);
        assertEq(dai.balanceOf(walletF), 0);
        assertEq(dai.balanceOf(walletG), 0);
        assertEq(dai.balanceOf(walletH), 0);
        assertEq(dai.balanceOf(walletZ), 0);
        assertEq(gohm.balanceOf(address(coolerA)), totalCollateral);
        assertEq(gohm.balanceOf(address(coolerB)), 0);
        assertEq(gohm.balanceOf(address(coolerC)), 0);
        assertEq(gohm.balanceOf(address(coolerD)), 0);
        assertEq(gohm.balanceOf(address(coolerE)), 0);
        assertEq(gohm.balanceOf(address(coolerF)), 0);
        assertEq(gohm.balanceOf(address(coolerG)), 0);
        assertEq(gohm.balanceOf(address(coolerH)), 0);
        assertEq(gohm.balanceOf(address(utils)), 0);
        // Check allowances
        assertEq(dai.allowance(address(walletA), address(utils)), 0);
        assertEq(gohm.allowance(address(walletA), address(utils)), 0);
        assertEq(dai.allowance(address(walletB), address(utils)), 0);
        assertEq(gohm.allowance(address(walletB), address(utils)), 0);
        assertEq(dai.allowance(address(walletC), address(utils)), 0);
        assertEq(gohm.allowance(address(walletC), address(utils)), 0);
        assertEq(dai.allowance(address(walletD), address(utils)), 0);
        assertEq(gohm.allowance(address(walletD), address(utils)), 0);
        assertEq(dai.allowance(address(walletE), address(utils)), 0);
        assertEq(gohm.allowance(address(walletE), address(utils)), 0);
        assertEq(dai.allowance(address(walletF), address(utils)), 0);
        assertEq(gohm.allowance(address(walletF), address(utils)), 0);
        assertEq(dai.allowance(address(walletG), address(utils)), 0);
        assertEq(gohm.allowance(address(walletG), address(utils)), 0);
        assertEq(dai.allowance(address(walletH), address(utils)), 0);
        assertEq(gohm.allowance(address(walletH), address(utils)), 0);
        assertEq(dai.allowance(address(walletZ), address(utils)), 0);

        console2.log("OUTSTANDING FUNDS:");
        console2.log(" > walletA:", walletA);
        console2.log_named_decimal_uint("   - dai amount:", initPrincipal - flashLoan, 18);
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

    function _idsD() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        return ids;
    }

    function _idsE() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        return ids;
    }

    function _idsF() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        return ids;
    }

    function _idsG() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        return ids;
    }

    function _idsH() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        return ids;
    }
}