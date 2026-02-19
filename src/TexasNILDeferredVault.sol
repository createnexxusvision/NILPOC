// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
    TexasNILDeferredVault (POC)

    - Let Texas high school seniors (17+) sign NIL deals WITHOUT receiving funds until:
        1) They have exhausted UIL eligibility, AND
        2) Their college enrollment is confirmed.

    - Supports Texas HB 126 and UIL 2025-26 NIL guidance.
    - This contract does NOT override law. It's infrastructure to help athletes,
      families, UIL, and colleges honor the rules.
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TexasNILDeferredVault is Ownable, ReentrancyGuard {

    // FIX: Enum cannot be defined inside a struct in Solidity — moved to contract scope.
    // FIX: Original had 'Refunded' with a stray ')' at the end of the enum body.
    enum DealStatus {
        Pending,      // Signed, funded, waiting on enrollment + unlockTime
        Cancellable,  // Eligible to cancel/refund
        Withdrawable, // Athlete can withdraw
        Withdrawn,    // Funds withdrawn by athlete
        Refunded      // Funds refunded to sponsor
    }

    struct Deal {
        address athlete;
        address sponsor;
        address college;        // Postsecondary institution wallet (for attestations)
        uint256 amount;         // In native chain currency
        uint64 unlockTime;      // No earlier than graduation/enrollment date
        bytes32 metadataHash;   // IPFS hash or off-chain metadata of the NIL contract
        bool enrollmentConfirmed;
        DealStatus status;
    }

    Deal[] public deals;

    // FIX: modifier and constructor referenced 'isVerifiers' but mapping was declared as 'verifiers'.
    // Renamed mapping to 'isVerifier' everywhere for consistency.
    mapping(address => bool) public isVerifier;

    event VerifierUpdated(address verifier, bool allowed);
    event DealCreated(
        uint256 indexed dealId,
        address indexed athlete,
        address indexed sponsor,
        address college,
        uint256 amount,
        uint64 unlockTime,
        bytes32 metadataHash
    );
    event EnrollmentConfirmed(uint256 indexed dealId, address indexed by);
    event StatusUpdated(uint256 indexed dealId, DealStatus status);
    event Withdrawn(uint256 indexed dealId, address indexed athlete, uint256 amount);
    event Refunded(uint256 indexed dealId, address indexed sponsor, uint256 amount);

    // FIX: Modifier referenced 'isVerifiers' (wrong name) — fixed to 'isVerifier'.
    modifier onlyVerifier() {
        require(isVerifier[msg.sender], "Not an authorized verifier");
        _;
    }

    constructor(address[] memory initialVerifiers) Ownable(msg.sender) {
        for (uint256 i = 0; i < initialVerifiers.length; i++) {
            isVerifier[initialVerifiers[i]] = true;
            emit VerifierUpdated(initialVerifiers[i], true);
        }
    }

    function setVerifier(address verifier, bool allowed) external onlyOwner {
        isVerifier[verifier] = allowed;
        emit VerifierUpdated(verifier, allowed);
    }

    /// @notice Sponsor locks funds for an athlete under a NIL agreement.
    function createDeal(
        address athlete,
        address college,
        uint64 unlockTime,
        bytes32 metadataHash
    ) external payable nonReentrant returns (uint256 dealId) {
        require(msg.value > 0, "No funds sent");
        require(athlete != address(0), "Invalid athlete address");
        // FIX: Changed >= to > so unlock time must actually be in the future.
        require(unlockTime > block.timestamp, "Unlock time must be in future");

        deals.push(Deal({
            athlete: athlete,
            sponsor: msg.sender,
            college: college,
            amount: msg.value,
            unlockTime: unlockTime,
            metadataHash: metadataHash,
            enrollmentConfirmed: false,
            status: DealStatus.Pending
        }));

        dealId = deals.length - 1;
        emit DealCreated(dealId, athlete, msg.sender, college, msg.value, unlockTime, metadataHash);
    }

    /// @notice Verifier or college confirms athlete has enrolled and UIL eligibility is exhausted.
    function confirmEnrollment(uint256 dealId) external {
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];

        require(
            deal.status == DealStatus.Pending || deal.status == DealStatus.Cancellable,
            "Deal not pending/cancellable"
        );
        require(
            isVerifier[msg.sender] || msg.sender == deal.college,
            "Not authorized to confirm enrollment"
        );

        deal.enrollmentConfirmed = true;
        if (block.timestamp >= deal.unlockTime) {
            deal.status = DealStatus.Withdrawable;
            emit StatusUpdated(dealId, deal.status);
        }
        emit EnrollmentConfirmed(dealId, msg.sender);
    } // FIX: confirmEnrollment was missing its closing brace — the next function was swallowed inside it.

    /// @notice Owner flips a deal to Cancellable (e.g., compliance issue or mutual void).
    function setStatusCancellable(uint256 dealId) external onlyOwner {
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];
        require(deal.status == DealStatus.Pending, "Deal not pending");
        deal.status = DealStatus.Cancellable;
        emit StatusUpdated(dealId, deal.status);
    }

    /// @notice Athlete withdraws after enrollment confirmed and unlockTime reached.
    function withdraw(uint256 dealId) external nonReentrant {
        require(dealId < deals.length, "Invalid dealId");
        Deal storage deal = deals[dealId];

        require(msg.sender == deal.athlete, "Not the athlete");
        require(
            deal.status == DealStatus.Pending || deal.status == DealStatus.Withdrawable,
            "Deal not withdrawable"
        );
        require(deal.enrollmentConfirmed, "Enrollment not confirmed");
        require(block.timestamp >= deal.unlockTime, "Unlock time not reached");
        require(deal.amount > 0, "No funds to withdraw");

        uint256 amount = deal.amount;
        deal.amount = 0; // CEI: state before interaction
        deal.status = DealStatus.Withdrawn;

        (bool ok, ) = deal.athlete.call{value: amount}("");
        require(ok, "Transfer failed");

        emit Withdrawn(dealId, deal.athlete, amount);
        emit StatusUpdated(dealId, deal.status);
    }

    /// @notice Refund sponsor if athlete never enrolls or deal is voided.
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
        deal.amount = 0; // CEI: state before interaction
        deal.status = DealStatus.Refunded;

        (bool ok, ) = deal.sponsor.call{value: amount}("");
        require(ok, "Refund failed");

        emit Refunded(dealId, deal.sponsor, amount);
        emit StatusUpdated(dealId, deal.status);
    }

    // -------- View Helpers --------

    function dealsCount() external view returns (uint256) {
        return deals.length;
    }

    function getDeal(uint256 dealId) external view returns (Deal memory) {
        require(dealId < deals.length, "Invalid dealId");
        return deals[dealId];
    }
}
