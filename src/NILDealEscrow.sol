// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    NILDealEscrow

    IRL problem:
    - Non-revenue and small-program athletes get ghosted by small businesses.
    - Businesses fear paying first and then getting ghosted by the athlete.

    Solution:
    - Sponsor deposits funds UPFRONT into escrow.
    - Deal terms (IPFS CID) are stored on-chain.
    - Athlete marks "delivered".
    - Sponsor confirms -> funds released to athlete.
    - If sponsor ghosts past the deadline, athlete can force release.
    - Either side can trigger a dispute; owner resolves it.
    - Reputation (completed vs disputed) tracked per address.
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NILDealEscrow is Ownable, ReentrancyGuard {

    enum EscrowStatus {
        Pending,    // Funded, waiting for athlete delivery
        Delivered,  // Athlete marked delivered, waiting for sponsor approval
        Completed,  // Funds released to athlete
        Disputed,   // Either party raised a dispute
        Refunded    // Sponsor refunded
    }

    struct NILDeal {
        address athlete;
        address sponsor;
        uint256 amount;       // in native currency (ETH)
        uint64  deadline;     // timestamp after which athlete can force release
        bytes32 metadataHash; // IPFS CID or hash of the NIL deal terms
        uint64  deliveredAt;  // when athlete marked delivered (0 if not yet)
        EscrowStatus status;
    }

    NILDeal[] public deals;

    // Reputation tracking
    mapping(address => uint256) public completedDeals;
    mapping(address => uint256) public disputedDeals;

    event DealCreated(
        uint256 indexed dealId,
        address indexed sponsor,
        address indexed athlete,
        uint256 amount,
        uint64  deadline,
        bytes32 metadataHash
    );
    event DealDelivered(uint256 indexed dealId, address indexed athlete, uint64 timestamp);
    event DealConfirmed(uint256 indexed dealId, address indexed sponsor, uint256 amount);
    event ForceReleased(uint256 indexed dealId, address indexed athlete, uint256 amount);
    event DealDisputed(uint256 indexed dealId, address indexed by);
    event DealRefunded(uint256 indexed dealId, address indexed sponsor, uint256 amount);

    constructor() Ownable(msg.sender) {}

    // -------- Core User Flows --------

    /// @notice Sponsor creates and funds a new NIL deal escrow.
    function createDeal(
        address athlete,
        uint64  deadline,
        bytes32 metadataHash
    ) external payable nonReentrant returns (uint256 dealId) {
        require(msg.value > 0,                       "NILDealEscrow: zero funding");
        require(athlete != address(0),               "NILDealEscrow: zero athlete");
        require(deadline > uint64(block.timestamp),  "NILDealEscrow: invalid deadline");

        deals.push(NILDeal({
            athlete:      athlete,
            sponsor:      msg.sender,
            amount:       msg.value,
            deadline:     deadline,
            metadataHash: metadataHash,
            deliveredAt:  0,
            status:       EscrowStatus.Pending
        }));

        dealId = deals.length - 1;
        emit DealCreated(dealId, msg.sender, athlete, msg.value, deadline, metadataHash);
    }

    /// @notice Athlete marks work as delivered; sponsor must confirm to release funds.
    function markDelivered(uint256 dealId) external {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        NILDeal storage d = deals[dealId];
        require(msg.sender == d.athlete,             "NILDealEscrow: not athlete");
        require(d.status == EscrowStatus.Pending,    "NILDealEscrow: invalid status");

        d.status      = EscrowStatus.Delivered;
        d.deliveredAt = uint64(block.timestamp);
        emit DealDelivered(dealId, msg.sender, uint64(block.timestamp));
    }

    /// @notice Sponsor confirms delivery; funds sent to athlete.
    function confirmDelivery(uint256 dealId) external nonReentrant {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        NILDeal storage d = deals[dealId];
        require(msg.sender == d.sponsor,               "NILDealEscrow: not sponsor");
        require(d.status == EscrowStatus.Delivered,    "NILDealEscrow: not delivered");
        require(d.amount > 0,                          "NILDealEscrow: zero funds");

        uint256 amount = d.amount;
        d.amount = 0;
        d.status = EscrowStatus.Completed;
        completedDeals[d.athlete]  += 1;
        completedDeals[d.sponsor]  += 1;

        (bool ok, ) = d.athlete.call{value: amount}("");
        require(ok, "NILDealEscrow: transfer failed");
        emit DealConfirmed(dealId, msg.sender, amount);
    }

    /// @notice Athlete force-releases funds after sponsor ghosts past deadline.
    function forceRelease(uint256 dealId) external nonReentrant {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        NILDeal storage d = deals[dealId];
        require(msg.sender == d.athlete,               "NILDealEscrow: not athlete");
        require(d.status == EscrowStatus.Delivered,    "NILDealEscrow: not delivered");
        require(block.timestamp > d.deadline,          "NILDealEscrow: deadline not passed");
        require(d.amount > 0,                          "NILDealEscrow: zero funds");

        uint256 amount = d.amount;
        d.amount = 0;
        d.status = EscrowStatus.Completed;
        completedDeals[d.athlete] += 1;
        completedDeals[d.sponsor] += 1;

        (bool ok, ) = d.athlete.call{value: amount}("");
        require(ok, "NILDealEscrow: transfer failed");
        emit ForceReleased(dealId, msg.sender, amount);
    }

    /// @notice Either party flags the deal as disputed.
    function raiseDispute(uint256 dealId) external {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        NILDeal storage d = deals[dealId];
        require(
            msg.sender == d.athlete || msg.sender == d.sponsor,
            "NILDealEscrow: not a party"
        );
        require(
            d.status == EscrowStatus.Pending || d.status == EscrowStatus.Delivered,
            "NILDealEscrow: cannot dispute"
        );
        d.status = EscrowStatus.Disputed;
        disputedDeals[msg.sender] += 1;
        emit DealDisputed(dealId, msg.sender);
    }

    /// @notice Owner resolves a dispute by releasing to athlete or refunding sponsor.
    function resolveDispute(uint256 dealId, bool releaseToAthlete) external onlyOwner nonReentrant {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        NILDeal storage d = deals[dealId];
        require(d.status == EscrowStatus.Disputed,  "NILDealEscrow: not disputed");
        require(d.amount > 0,                       "NILDealEscrow: zero funds");

        uint256 amount = d.amount;
        d.amount = 0;

        if (releaseToAthlete) {
            d.status = EscrowStatus.Completed;
            completedDeals[d.athlete] += 1;
            (bool ok, ) = d.athlete.call{value: amount}("");
            require(ok, "NILDealEscrow: transfer failed");
            emit DealConfirmed(dealId, msg.sender, amount);
        } else {
            d.status = EscrowStatus.Refunded;
            (bool ok, ) = d.sponsor.call{value: amount}("");
            require(ok, "NILDealEscrow: refund failed");
            emit DealRefunded(dealId, d.sponsor, amount);
        }
    }

    // -------- View Helpers --------

    function dealsCount() external view returns (uint256) {
        return deals.length;
    }

    function getDeal(uint256 dealId) external view returns (NILDeal memory) {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        return deals[dealId];
    }

    function getReputation(address user) external view returns (uint256 completed, uint256 disputed) {
        completed = completedDeals[user];
        disputed  = disputedDeals[user];
    }
}
