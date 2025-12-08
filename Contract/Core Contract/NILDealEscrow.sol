// SPDX-license-Identifier: MIT
pragma solidity ^0.8.19;

/*
    NILDealEscrow

    IRL problem:
    - Non-revenue and small-program athletes get ghosted by small businesses.
    - Businesses fear paying first and then getting gosted by the athlete.

    Solution:
    - Sponsor deposits funds UPFRONT into escrow.
    - Deal terms (IPFS CID) are stored on-chain.
    - Athlete marks "delivered".
    - Sponsor confirms -> funds released to athlete.
    - If sponsor ghosts past the deadline, athlete can force release (auto-release mode).
    - Either side can trigger a dispute, and we track reputation (completed vs disputed) per address.

    This contract is designed for cheap L2s like Polygon or Base
    so that $100-$1,000 NIL deals are still viable.
*/

import {BaseNIL} from "./BaseNIL.sol";

contract NILDealEscrow is BaseNIL {
    // Status of each NIL deal is escrow
    enum EscrowStatus {
        Pending,    // Funded, waiting for athlete delivery
        Delivered,  // Athlete marked as delivered, waiting for sponsor approval
        Completed,  // Sponsor approved, funds released to athlete. If they delay pass deadline, auto-release.
        Disputed,   // Either party raised a dispute, needs manual resolution
        Refunded    // Sponsor refunded, either via cancellation or dispute resolution
    }
    struct NILDeal {
        address athlete;
        address sponsor;
        uint256 amount;     // in native currency (e.g. ETH on BAse/Polygon)
        uint64 deadline;   // timestamp after which athlete can force release if sponsor is unresponsive
        bytes32 metadataHash;   // IPFS CID or hash of the NIL deal terms
        uint64 deliveredAt;   // when athlete marked as delivered (0 if not yet)
        EscrowStatus status;
    }

    deal[] public deals;
    // Simple reputation tracking:
    // how many deals each address (athlete or sponsor) has completed vs disputed.
    mapping(address => uint256) public completedDeals;
    mapping(address => uint256) public disputedDeals;

    // Events to watch on-chain / in graph indexers
    event DealCreated(
        uint256 indexed dealId,
        address indexed sponsor,
        address indexed athlete,
        uint256 amount,
        uint64 deadline,
        bytes32 metadataHash
    );

    event DealDelivered(uint256 indexed dealId, address indexed athlete, uint64 timestamp);
    event DealConfirmed(uint256 indexed dealId, address indexed sponsor, uint256 amount);
    event ForceReleased(uint256 indexed dealId, address indexed athlete, uint256 amount);
    event DealDisputed(uint256 indexed dealId, address indexed by);
    event DealRefunded(uint256 indexed dealId, address indexed sponsor, uint256 amount);

    --------- Core USER FLOWS ---------

    /**
     * @notice Sponsor creates and funds a new NIL deal escrow for an athlete.
     * @param athlete The athlete wallet that should eventually receive the funds.
     * @param deadline Unix timestamp after which athlete can force release if sponsor is unresponsive.
     * @param metadataHash IPFS CID or hash of off-chain NIL deal terms.
     *
     * Flow:
     * - Sponsor calls this function with 'msg.value' > 0'.
     * - Funds are held in contract until deal is completed, refunded, or disputed.
     * - Everyone can see the basic deal info + metadataHash on-chain.
     */
    function createDeal(
        address athlete,
        uint64 deadline,
        bytes32 metadataHash
    ) external payable returns (uint256 dealId) {
        require(msg.value > 0, "NILDealEscrow: zero funding");
        require(athlete != address(0), "NILDealEscrow: zero athlete");
        require(deadline > block.timestamp, "NILDealEscrow: invalid deadline");

        Deal memory newdeal = Deal({
            athlete: athlete,
            sponsor: msg.sender,
            amount: msg.value,
            deadline: deadline,
            metadataHash: metadataHash,
            deliveredAt: 0,
            status: EscrowStatus.Pending
        });

        deals.push(newdeal);
        dealId = deals.length - 1;

        _onReceieveETH(msg.sender, msg.value);

        emit DealCreated(
            dealId,
            msg.sender,
            athlete,
            msg.value,
            deadline,
            metadataHash
        );
    }
    /**
     * @notice Athlete marks the work/content/deal as delivered.
     * @dev Can only be called by the athlete for this deal, once, while in Pending status.     
     */
    function markDelivered(uint256 dealId) external {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        Deal storage deal = deals[dealId];

        require(msg.sender == deal.athlete, "NILDealEscrow: not athlete");
        require(deal.status == EscrowStatus.Pending, "NILDealEscrow: invalid status");
        require(deal.amount > 0, "NILDealEscrow: zero funds");

        uint256 amount = deal.amount;
        deal.amount = 0; // prevent re-entrancy
        deal.status = EscrowStatus.Delivered;

        // Reputation bump
        completedDeal[deal.athlete] += 1;
        completedDeal[deal.sponsor] += 1;

        _sendETH(deal.athlete, amount);

        emit ForceReleased(dealId, msg.sender, amount);
    }

    /**
     * @notice Either party can flag the deal as disputed.
     * @dev This does NOT move funds. It just changes status and bumps dispute counters.
     *      You (or an off-chain system) can then mediate and decide what to do with funds.
     */
    function raiseDispute(uint256 dealId) external {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        Deal storage deal = deals[dealId];

        require(
            deal.status == EscrowStatus.Pending ||
            deal.status == EscrowStatus.Delivered ||
            deal.status == EscrowStatus.Disputed,
            "NILDealEscrow: cannot refunded"
        );
        require(deal.amount > 0, "NILDealEscrow: zero funds");

        uint256 amount = deal.amount;
        deal.amount = 0; // prevent re-entrancy
        deal.status = EscrowStatus.Refunded;

        _sendETH(deal.sponsor, amount);

        emit Refunded(dealId, deal.sponsor, amount);
    }

    // --------- VIEW HELPERS ---------

    function dealsCount() external view returns (uint256) {
        return deals.length;
    }

    function getDeal(uint256 dealId) external view returns (Deal memory) {
        require(dealId < deals.length, "NILDealEscrow: invalid dealId");
        return deals[dealId];
    }

    function getReputation(address user) external view returns (uint256 completed, uint256 disputed) {
        completed = completedDeals[user];
        disputed = disputedDeals[user];
    }
}
