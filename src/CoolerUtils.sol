// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {Test, console2} from "forge-std/Test.sol";

import { IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool } from "src/interfaces/aave-v3/IFlashLoanSimpleReceiver.sol";
import { IClearinghouse } from "src/interfaces/olympus-v3/IClearinghouse.sol";
import { ICooler } from "src/interfaces/olympus-v3/ICooler.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

contract CoolerUtils is IFlashLoanSimpleReceiver {

    // --- ERRORS ------------------------------------------------------------------

    error NotCoolerOwner();
    error MissingApproval(address cooler_);

    // --- DATA STRUCTURES ---------------------------------------------------------

    struct Batch {
        bool sdai;
        address cooler;
        uint256[] ids;
    }

    struct BatchFashLoan {
        address cooler;
        uint256[] ids;
    }

    // --- IMMUTABLES --------------------------------------------------------------

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool public immutable POOL;

    IERC20 public immutable gohm;
    IERC4626 public immutable sdai;
    IERC20 public immutable dai;

    // --- STATE VARIABLES ---------------------------------------------------------

    /// @notice Tracks wether a cooler is approved for a given spender.
    mapping(address => mapping(address => bool)) public isApprovedFor;

    // --- INITIALIZATION ----------------------------------------------------------

    constructor(
        address gohm_,
        address sdai_,
        address dai_,
        address addressProviderAAVE_
    ) {
        // Initialize FlashLoan Simple Receiver constants
        ADDRESSES_PROVIDER = IPoolAddressesProvider(addressProviderAAVE_);
        POOL = IPool(IPoolAddressesProvider(addressProviderAAVE_).getPool());

        // Initialize Cooler Loans variables
        dai = IERC20(dai_);
        sdai = IERC4626(sdai_);
        gohm = IERC20(gohm_);
    }

    // --- ACCESS CONTROL ----------------------------------------------------------

    function approve(address cooler_, address spender_) external {
        if (msg.sender != ICooler(cooler_).owner()) revert NotCoolerOwner();
        isApprovedFor[cooler_][spender_] = true;
    }

    function revoke(address cooler_, address spender_) external {
        if (msg.sender != ICooler(cooler_).owner()) revert NotCoolerOwner();
        delete isApprovedFor[cooler_][spender_];
    }

    // --- OPERATION ---------------------------------------------------------------

    /// @notice Consolidate loans taken with a given Cooler contract into a single loan.
    ///         This function is meant to be used when the user has only taken loans with one wallet.
    ///
    /// @dev    This function will revert unless the user has:
    ///            - Approved this contract to spend the total debt owed to the Cooler.
    ///            - Approved this contract to spend the gOHM escrowed by the Cooler.
    ///         For flexibility purposes, this contract can either repay the loans with DAI or sDAI.
    ///
    /// @param  cooler_        Cooler which issued the loans and where they will be consolidated.
    /// @param  clearinghouse_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  ids_           Array of loan ids to be consolidated.
    /// @param  sdai_          Boolean indicating whether to repay using DAI or sDAI.
    function consolidateLoansFromSingleCooler(
        address cooler_,
        address clearinghouse_,
        uint256[] calldata ids_,
        bool sdai_
    ) public returns (uint256) {
        uint256 numLoans = ids_.length;

        // Cache total debt and principal
        (uint256 totalDebt, uint256 totalPrincipal) = _getDebtForLoans(cooler_, numLoans, ids_);

        // Transfer in necessary DAI to repay the loans
        if (sdai_) {
            sdai.withdraw(totalDebt, address(this), address(msg.sender));
        } else {
            dai.transferFrom(address(msg.sender), address(this), totalDebt);
        }

        // Repay all loans
        dai.approve(cooler_, totalDebt);
        _repayDebtForLoans(cooler_, numLoans, ids_);

        // Take a new loan with all the received collateral.
        gohm.approve(clearinghouse_, gohm.balanceOf(address(this)));
        return IClearinghouse(clearinghouse_).lendToCooler(ICooler(cooler_), totalPrincipal);
    }

    /// @notice Consolidate loans taken with multiple Cooler contracts into a single loan for a target Cooler.
    ///         This function is meant to be used when the user has taken loans with several wallets.
    ///
    /// @dev    This function will revert if:
    ///            - The target Cooler where loans will be consolidated is not included in the batches.
    /// @dev    This function will revert unless the owner of each Cooler has:
    ///            - Approved this contract to spend the total debt owed to each Cooler.
    ///            - Approved this contract to spend the gOHM escrowed by each Cooler.
    ///         For flexibility purposes, this contract can either repay the loans with DAI or sDAI.
    ///
    /// @param  target_        Cooler to which the loans will be consolidated.
    /// @param  clearinghouse_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  batch_         Array of structs containing the data the loans to be consolidated.
    function consolidateLoansFromMultipleCoolers(
        address target_,
        address clearinghouse_,
        Batch[] calldata batch_
    ) public returns (uint256) {
        uint256 totalPrincipal;
        uint256 numBatches = batch_.length;

        // Iterate over all batches
        for (uint256 i; i < numBatches; i++) {
            uint256 numLoans = batch_[i].ids.length;
            ICooler cooler = ICooler(batch_[i].cooler);
            address owner = cooler.owner();
        
            // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
            if (owner != msg.sender && !isApprovedFor[address(cooler)][msg.sender])
                revert MissingApproval(address(cooler));

            // Cache batch debt and principal
            (uint256 batchDebt, uint256 batchPrincipal) = _getDebtForLoans(batch_[i].cooler, numLoans, batch_[i].ids);
            totalPrincipal += batchPrincipal;

            // Transfer in necessary DAI to repay the loans
            if (batch_[i].sdai) {
                sdai.withdraw(batchDebt, address(this), cooler.owner());
            } else {
                dai.transferFrom(cooler.owner(), address(this), batchDebt);
            }

            // Repay all loans
            dai.approve(address(cooler), batchDebt);
            _repayDebtForLoans(address(cooler), numLoans, batch_[i].ids);
        }

        // Take a new loan with all the received collateral.
        gohm.approve(clearinghouse_, gohm.balanceOf(address(this)));
        return IClearinghouse(clearinghouse_).lendToCooler(ICooler(target_), totalPrincipal);
    }

    // --- FLASHLOAN FUNCTIONS -----------------------------------------------------

    /// @notice Consolidate loans taken with multiple Cooler contracts into a single loan by using
    ///         AAVE V3 flashloans.
    ///         This function is meant to be used when the user doesn't have access to enough funds
    ///         to repay each individual loan.
    ///
    /// @dev    This function will revert if:
    ///            - The target Cooler where loans will be consolidated is not included in the batches.
    /// @dev    This function will revert unless the message sender has:
    ///            - Approved this contract to spend the `availableFunds_`.
    ///            - Approved this contract to spend the gOHM escrowed by the target Cooler.
    ///         For flexibility purposes, this contract can either repay the loans with DAI or sDAI.
    ///
    /// @param  target_        Cooler to which the loans will be consolidated.
    /// @param  clearinghouse_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  batch_         Array of structs containing the data the loans to be consolidated.
    function consolidateLoansWithoutFunds(
        address target_,
        address clearinghouse_,
        BatchFashLoan[] calldata batch_,
        uint256 availableFunds_,
        bool sdai_
    ) public returns (uint256) {
        uint256 totalDebt;
        uint256 totalPrincipal;
        uint256 numBatches = batch_.length;

        // Iterate over all batches
        for (uint256 i; i < numBatches; i++) {
            uint256 numLoans = batch_[i].ids.length;
            ICooler cooler = ICooler(batch_[i].cooler);

            // Cache batch debt and principal
            (uint256 batchDebt, uint256 batchPrincipal) = _getDebtForLoans(address(cooler), numLoans, batch_[i].ids);
            totalPrincipal += batchPrincipal;
            totalDebt += batchDebt;

            // Grant approval to the Cooler to spend the debt
            dai.approve(address(cooler), batchDebt);
        
            // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
            if (cooler.owner() != msg.sender && !isApprovedFor[address(cooler)][msg.sender])
                revert MissingApproval(address(cooler));
        }

        // Transfer in necessary DAI to repay the loans
        if (sdai_) {
            sdai.redeem(availableFunds_, address(this), msg.sender);
        } else {
            dai.transferFrom(msg.sender, address(this), availableFunds_);
        }

        // Calculate the required flashloan amount based on the available funds.
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 flashloan = 10_000 * (totalDebt - daiBalance) / (10_000 - POOL.FLASHLOAN_PREMIUM_TOTAL());

        address receiverAddress = address(this);
        bytes memory params = abi.encode(target_, clearinghouse_, totalPrincipal, batch_);
        uint16 referralCode;

        // Take flashloan.
        POOL.flashLoanSimple(
            receiverAddress,
            address(dai),
            flashloan,
            params,
            referralCode
        );
    }

    function executeOperation(
        address asset_,
        uint256 amount_,
        uint256 premium_,
        address initiator_,
        bytes calldata params_
    )  external override returns (bool) {
        (address target, address clearinghouse, uint256 principal, BatchFashLoan[] memory batch) = abi.decode(params_, (address, address, uint256, BatchFashLoan[]));
        ICooler cooler = ICooler(target);

        {
            // Iterate over all batches
            uint256 numBatches = batch.length;
            for (uint256 i; i < numBatches; i++) {
                _repayDebtForLoans(batch[i].cooler, batch[i].ids.length, batch[i].ids);
            }
        }

        // Take a new loan with all the received collateral
        gohm.approve(clearinghouse, gohm.balanceOf(address(this)));
        IClearinghouse(clearinghouse).lendToCooler(cooler, principal);

        // Repay flashloan
        dai.transferFrom(cooler.owner(), address(this), amount_);
        dai.approve(address(POOL), amount_ + premium_);

        return true;
    }

    // --- INTERNAL FUNCTIONS ------------------------------------------------------

    function _getDebtForLoans(
        address cooler_,
        uint256 numLoans_,
        uint256[] calldata ids_
    ) internal view returns (uint256, uint256) {
        uint256 totalDebt;
        uint256 totalPrincipal;

        for (uint256 i; i < numLoans_; i++) {
            (, uint256 principal, uint256 interestDue, , , , , ) = ICooler(cooler_).loans(ids_[i]);
            totalDebt += principal + interestDue;
            totalPrincipal += principal;
        }

        return (totalDebt, totalPrincipal);
    }

    function _repayDebtForLoans(
        address cooler_,
        uint256 numLoans_,
        uint256[] memory ids_
    ) internal returns (uint256, uint256) {
        uint256 totalCollateral;
        ICooler cooler = ICooler(cooler_);

        for (uint256 i; i < numLoans_; i++) {
            (, uint256 principal, uint256 interestDue, uint256 collateral, , , , ) = cooler.loans(ids_[i]);
            cooler.repayLoan(ids_[i], principal + interestDue);
            totalCollateral += collateral;
        }

        gohm.transferFrom(cooler.owner(), address(this), totalCollateral);
    }

    // --- AUX FUNCTIONS -----------------------------------------------------------

    /// @notice View function to compute the required approval amounts that the owner of a given Cooler
    ///         must give to this contract in order to consolidate the loans.
    ///
    /// @param  cooler_ Contract which issued the loans.
    /// @param  ids_    Array of loan ids to be consolidated.
    /// @return         Tuple with the following values:
    ///                  - Owner of the Cooler (address that should grant the approval).
    ///                  - gOHM amount to be approved.
    ///                  - DAI amount to be approved (if sDAI option will be set to false).
    ///                  - sDAI amount to be approved (if sDAI option will be set to true).
    function requiredApprovals(
        address cooler_,
        uint256[] calldata ids_
    ) external view returns (address, uint256, uint256, uint256) {
        uint256 totalDebt;
        uint256 totalCollateral;
        uint256 numLoans = ids_.length;
        ICooler cooler = ICooler(cooler_);

        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, uint256 collateral, , , , ) = cooler.loans(ids_[i]);
            totalDebt += principal + interestDue;
            totalCollateral += collateral;
        }

        return (cooler.owner(), totalCollateral, totalDebt, sdai.previewWithdraw(totalDebt));
    }
}
