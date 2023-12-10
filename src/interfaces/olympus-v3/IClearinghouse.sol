// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ICooler} from "./ICooler.sol";

interface IClearinghouse {

    error BadEscrow();
    error DurationMaximum();
    error OnlyBurnable();
    error TooEarlyToFund();
    error LengthDiscrepancy();
    error OnlyBorrower();
    error NotLender();

    /// @notice Lend to a cooler.
    /// @dev    To simplify the UX and easily ensure that all holders get the same terms,
    ///         this function requests a new loan and clears it in the same transaction.
    /// @param  cooler_ to lend to.
    /// @param  amount_ of DAI to lend.
    /// @return the id of the granted loan.
    function lendToCooler(ICooler cooler_, uint256 amount_) external returns (uint256);

    /// @notice view function computing collateral for a loan amount.
    function getCollateralForLoan(uint256 principal_) external pure returns (uint256);
    
    /// @notice view function computing loan for a collateral amount.
    /// @param  collateral_ amount of gOHM.
    /// @return debt (amount to be lent + interest) for a given collateral amount.
    function getLoanForCollateral(uint256 collateral_) external pure returns (uint256, uint256);

    /// @notice view function to compute the interest for given principal amount.
    /// @param principal_ amount of DAI being lent.
    /// @param duration_ elapsed time in seconds.
    function interestForLoan(uint256 principal_, uint256 duration_) external pure returns (uint256);

    function sweepIntoDSR() external;

    function fundTime() external view returns (uint256);
}
