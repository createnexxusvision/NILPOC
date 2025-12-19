// spdx-license-identifier: MIT
pragma solidity ^0.8.19;

/*
    TexasNILDeferredVault (POC)

    - Let Texas high school seniors (17+) sign NIL deals WITHOUT receiving funds until:
        1) They have exhausted UIL eligibility, AND
        2) Their college ennrollment is confirmed.

   - Complies with
     * Texas HB 126: 17+ can sign, but pay is deferred until enrollment.
     * UIL 2025-26 NIL guidance: 17+ may sign with colleges; execution of deals with non-college entities must wait unitl UIL eligibility end

   - This contract does NOT override law. It's infrastructure to HELP athletes, families, UIL, and colleges honor the rules.
   
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TexasNILDeferredVault is Ownable, ReentrancyGuard {
    struct DealStatus {
        Pending,      // Signed, funded, waiting on enrollment + unlockTime
        Cancellable,  // Eligible to cancel/refund (optional)
        Withdrawable, // Athlete can withdraw
        Withdrawn,    // Funds withdrawn by athlete
        Refunded      // Funds refunded to sponsor) 
    }

    struct Deal {
        address athlete;
        address sponsor;
        address college;   // Postsecondary institution wallet (for attestations)
        uint256 amount;    // In native chain currency
        uint64 unlockTime;  // No earlier than graduation/enrollment date
        bytes32 metadataHash; // IPFS hash or off-chain metadata of the NIL contract
        bool enrollmentConfirmed;
        DealStatus status;
    }    

    // Deal storage
    Deal[] public deals;

    // Authorized verifiers: UIL / college compliance / trusted attesters
    mapping(address => bool) public verifiers;

    event VerifierUpdated(address verifier, bool allowed);
    event DealCreated(uint256 indexed dealId, address indexed athlete, address indexed sponsor, address college, uint256 amount, uint64 unlockTime, bytes32 metadataHash);
    event EnrollmentConfirmed(uint256 indexed dealId, address indexed by);
    event StatusUpdated(uint256 indexed dealId, DealStatus status);
    event Withdrawn(uint256 indexed dealId, address indexed athlete, uint256 amount);
    event Refunded(uint256 indexed dealId, address indexed sponsor, uint256 amount);    

    modifier onlyVerifier() {
        require(isVerifiers[msg.sender], "Not an authorized verifier");
        _;
    }

    constructor(address[] memory initialVerifiers) {
        for (uint i = 0; i < initialVerifiers.length; i++) {
            isVerifiers[initialVerifiers[i]] = true;
            emit VerifierUpdated(initialVerifiers[i], true);
        }
    }

    // OWNER (e.g., UIL / NextPlay Nexus admin) can add/remove verifiers.
    function setVerifier(address verifier, bool allowed) external onlyOwner {
        isVerifiers[verifier] = allowed;
        emit VerifierUpdated(verifier, allowed);
    }

    /*

        createDeal
        Called by sponsor (college or third party) to lock funds
        for an athlete under a NIL agreement.

        - 'college' can be zero address if it's a non-college entity,
        but UIL rules say such a deal "may not be executed" until eligibility is exhausted.
        That reality can be documented in metadata.

        - 'unlockTime' shhould be set to NO EARLIER than expected enrollment date or end of UIL eligibility.

        NOTE: Age/grade checks happen OFF-CHAIN (school + legal layer).
    */

  function createDeal(
        address athlete,
        address college,
        uint64 unlockTime,
        bytes32 metadataHash
    ) external payable nonReentrant returns (uint256 dealId) {
        require(msg.value > 0, "No funds sent");
        require(athlete != address(0), "Invalid athlete address");
        require(unlockTime >= block.timestamp, "Unlock time must be in future");

        deals.push(
            Deal({
            athlete: athlete,
            sponsor: msg.sender,
            college: college,
            amount: msg.value,
            unlockTime: unlockTime,
            metadataHash: metadataHash,
            enrollmentConfirmed: false,
            status: DealStatus.Pending
        })     
    );

     dealId = deals.length - 1;
    emit DealCreated(dealId, athlete, msg.sender, college, msg.value, unlockTime, metadataHash);
    }


    /*
        confirmEnrollment
        Called by:
        - Authorized verifier (UIL / compliance address), OR
        - College wallet listed on the deal.

        This signals the athlete has:
        - Officially enrolled at the colelge, AND
        - UIL eligibility is no longer in play.

        After this AND unlockTime, athlete can withdraw funds.  
    */
    function confirmEnrollment(uint256 dealId) external { 
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];

        require(deal.status == DealStatus.Pending || deal.status == DealStatus.Cancellable, "Deal not pendingactive/cancellable");
        require(
            isVerifiers[msg.sender] || msg.sender == deal.college,
            "Not authorized to confirm enrollment"
        );

        deal.enrollmentConfirmed = true;
        // Optionally mark it directly as Withdrawable if unlockTime already passed
        if (block.timestamp >= deal.unlockTime) {
            deal.status = DealStatus.Withdrawable;
    }

    /*
        setStatusCancellable

        OWNER can flip a deal to Cacnellable.

        Use case:
        - If compliance discovers issues, or deal is voided by mutual agreement,
        you move it to Cancellable and eventually allow refund.
    */
    function setStatusCancellable(uint256 dealId) external onlyOwner {
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];
        require(deal.status == DealStatus.Pending, "Deal not pending");
        deal.status = DealStatus.Cancellable;
        emit StatusUpdated(dealId, deal.status);
    }

    /*
        withdraw

        Athlete withdraws after:
        - Enrollment confirmed (by verifier/college)
        - unlockTime passed/reached
        - Deal not already withdrawn/refunded

    */
    function withdraw(uint256 dealId) external nonReentrant {
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];

        require(msg.sender == deal.athlete, "Not the athlete");
        require(deal.status == DealStatus.Pending  || deal.status == DealStatus.Withdrawable, "Deal not withdrawable");
        require(deal.enrollmentConfirmed, "Enrollment not confirmed");
        require(block.timestamp >= deal.unlockTime, "Unlock time not reached");
        require(deal.amount > 0, "No funds to withdraw");

        uint256 amount = deal.amount;
        deal.amount = 0; // Prevent re-entrancy
        deal.status = DealStatus.Withdrawn;

        (bool ok, ) = deal.athlete.call{value: amount}("");
        require(ok, "Transfer failed");

        emit Withdrawn(dealId, deal.athlete, amount);
        emit StatusUpdated(dealId, deal.status);
    }

    /*
        refund

        In limited cases (e.g. athlete never ennrolls, deal is voided),
        funds can be refunded to sponsor.

        Can only be called:
        - By OWNER (UIL / admin), OR
        - By sponsor IF contract sets such a rule (kept simple here).
    */
    function refund(uint256 dealId) external nonReentrant {
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];

        require(
            msg.sender == owner() || msg.sender == deal.sponsor,
            "Not authorized to refund"
        );
        require(
            deal.status == DealStatus.Cancellable || !deal.enrollmentConfirmed,
             "Deal not refundable after confirmation"
        );
        require(deal.amount > 0, "No funds to refund");

        uint256 amount = deal.amount;
        deal.amount = 0; // Prevent re-entrancy
        deal.status = DealStatus.Refunded;

        (bool ok, ) = deal.sponsor.call{value: amount}("");
        require(ok, "Refund failed");

        emit Refunded(dealId, deal.sponsor, amount);
        emit StatusUpdated(dealId, deal.status);
    }

    /*
        VIEW HELPERS
    */

    function dealsCount() external view returns (uint256) {
        return deals.length;
    }

    function getDeal(uint256 dealId) external view returns (Deal memory) {
        require(dealId < deals.length, "Invalid dealId");
        return deals[dealId];
    }
}
