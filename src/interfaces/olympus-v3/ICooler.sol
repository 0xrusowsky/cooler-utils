// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ICooler {

    error OnlyApproved();
    error Deactivated();
    error Default();
    error NotExpired();
    error NotCoolerCallback();

    // --- DATA STRUCTURES -------------------------------------------

    /// @notice A loan begins with a borrow request.
    struct Request {
        uint256 amount;             // Amount to be borrowed.
        uint256 interest;           // Annualized percentage to be paid as interest.
        uint256 loanToCollateral;   // Requested loan-to-collateral ratio.
        uint256 duration;           // Time to repay the loan before it defaults.
        bool active;                // Any lender can clear an active loan request.
        address requester;          // The address that created the request.
    }

    /// @notice A request is converted to a loan when a lender clears it.
    struct Loan {
        Request request;        // Loan terms specified in the request.
        uint256 principal;      // Amount of principal debt owed to the lender.
        uint256 interestDue;    // Interest owed to the lender.
        uint256 collateral;     // Amount of collateral pledged.
        uint256 expiry;         // Time when the loan defaults.
        address lender;         // Lender's address.
        address recipient;      // Recipient of repayments.
        bool callback;          // If this is true, the lender must inherit CoolerCallback.
    }

    /// @notice Request a loan with given parameters.
    ///         Collateral is taken at time of request.
    /// @param  amount_ of debt tokens to borrow.
    /// @param  interest_ to pay (annualized % of 'amount_'). Expressed in DECIMALS_INTEREST.
    /// @param  loanToCollateral_ debt tokens per collateral token pledged. Expressed in 10**collateral().decimals().
    /// @param  duration_ of loan tenure in seconds.
    /// @return reqID of the created request. Equivalent to the index of request in requests[].
    function requestLoan(
        uint256 amount_,
        uint256 interest_,
        uint256 loanToCollateral_,
        uint256 duration_
    ) external returns (uint256 reqID);

    /// @notice Cancel a loan request and get the collateral back.
    /// @param  reqID_ index of request in requests[].
    function rescindRequest(uint256 reqID_) external;

    /// @notice Repay a loan to get the collateral back.
    /// @dev    Despite a malicious lender could reenter with the callback, the
    ///         usage of `msg.sender` prevents any economical benefit to the
    ///         attacker, since they would be repaying the loan themselves.
    /// @param  loanID_ index of loan in loans[].
    /// @param  repayment_ debt tokens to be repaid.
    /// @return collateral given back to the borrower.
    function repayLoan(uint256 loanID_, uint256 repayment_) external returns (uint256);

    /// @notice Delegate voting power on collateral.
    /// @param  to_ address to delegate.
    function delegateVoting(address to_) external;

    // --- LENDER ----------------------------------------------------

    /// @notice Fill a requested loan as a lender.
    /// @param  reqID_ index of request in requests[].
    /// @param  recipient_ address to repay the loan to.
    /// @param  isCallback_ true if the lender implements the CoolerCallback abstract. False otherwise.
    /// @return loanID of the granted loan. Equivalent to the index of loan in loans[].
    function clearRequest(
        uint256 reqID_,
        address recipient_,
        bool isCallback_
    ) external returns (uint256 loanID);


    /// @notice Allow lender to extend a loan for the borrower. Doesn't require
    ///         borrower permission because it doesn't have a negative impact for them.
    /// @dev    Since this function solely impacts the expiration day, the lender
    ///         should ensure that extension interest payments are done beforehand.
    /// @param  loanID_ index of loan in loans[].
    /// @param  times_ that the fixed-term loan duration is extended.
    function extendLoanTerms(uint256 loanID_, uint8 times_) external;

    /// @notice Claim collateral upon loan default.
    /// @param  loanID_ index of loan in loans[].
    /// @return defaulted debt by the borrower, collateral kept by the lender, elapsed time since expiry.
    function claimDefaulted(uint256 loanID_) external returns (uint256, uint256, uint256, uint256);

    /// @notice Approve transfer of loan ownership rights to a new address.
    /// @param  to_ address to be approved.
    /// @param  loanID_ index of loan in loans[].
    function approveTransfer(address to_, uint256 loanID_) external;

    /// @notice Execute loan ownership transfer. Must be previously approved by the lender.
    /// @param  loanID_ index of loan in loans[].
    function transferOwnership(uint256 loanID_) external;

    /// @notice Allow lender to set repayment recipient of a given loan.
    /// @param  loanID_ of lender's loan.
    /// @param  recipient_ reciever of repayments
    function setRepaymentAddress(uint256 loanID_, address recipient_) external;

    // --- AUX FUNCTIONS ---------------------------------------------

    /// @notice Compute collateral needed for a desired loan amount at given loan to collateral ratio.
    /// @param  principal_ amount of debt tokens.
    /// @param  loanToCollateral_ ratio for loan. Expressed in 10**collateral().decimals().
    function collateralFor(uint256 principal_, uint256 loanToCollateral_) external view returns (uint256);

    /// @notice Compute interest cost on amount for duration at given annualized rate.
    /// @param  principal_ amount of debt tokens.
    /// @param  rate_ of interest (annualized).
    /// @param  duration_ of the loan in seconds.
    /// @return Interest in debt token terms.
    function interestFor(uint256 principal_, uint256 rate_, uint256 duration_) external pure returns (uint256);

    /// @notice Check if given loan has expired.
    /// @param  loanID_ index of loan in loans[].
    /// @return Expiration status.
    function hasExpired(uint256 loanID_) external view returns (bool);

    /// @notice Check if a given request is active.
    /// @param  reqID_ index of request in requests[].
    /// @return Active status.
    function isActive(uint256 reqID_) external view returns (bool);

    /// @notice Getter for Request data as a struct.
    /// @param  reqID_ index of request in requests[].
    /// @return Request struct.
    function getRequest(uint256 reqID_) external view returns (Request memory);

    /// @notice Getter for Loan data as a struct.
    /// @param loanID_ index of loan in loans[].
    /// @return Loan struct.
    function getLoan(uint256 loanID_) external view returns (Loan memory);
}
