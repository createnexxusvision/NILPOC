// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title NILEvents
/// @notice Unified protocol event schema for bulletproof indexing.
/// @dev All core contracts should emit these events when applicable.
library NILEvents {
    // --- DealEngine ---
    event DealCreated(
        uint256 indexed dealId,
        address indexed sponsor,
        address indexed athlete,
        address token,
        uint256 amount,
        uint64 deadline,
        bytes32 termsHash
    );

    event DealFunded(uint256 indexed dealId, address indexed funder, address token, uint256 amount);

    event DealDelivered(uint256 indexed dealId, address indexed athlete, bytes32 evidenceHash, uint64 deliveredAt);

    event DealDisputed(uint256 indexed dealId, address indexed by, uint32 reasonCode, bytes32 evidenceHash, uint64 at);

    event DealSettled(
        uint256 indexed dealId,
        address indexed token,
        uint256 gross,
        uint256 platformFee,
        uint256 netToAthlete,
        address feeRecipient,
        uint64 at
    );

    event DealRefunded(uint256 indexed dealId, address indexed token, uint256 amount, address indexed sponsor, uint64 at);

    // --- PayoutRouter ---
    event SplitDefined(uint256 indexed splitId, bytes32 splitHash, address indexed creator);

    // FIX: PayoutExecuted had 4 indexed params — EVM max is 3 for non-anonymous events.
    // Removed 'indexed' from 'payer' (least query-critical; derivable from context).
    event PayoutExecuted(
        uint256 indexed payoutId,
        bytes32 indexed ref,
        address payer,
        address indexed authorizer,
        address token,
        uint256 amount,
        uint256 splitId,
        uint64 at
    );

    // --- Vault ---
    event GrantCreated(
        uint256 indexed grantId,
        address indexed sponsor,
        address indexed beneficiary,
        address token,
        uint256 amount,
        uint64 unlockTime,
        bytes32 termsHash
    );

    event GrantAttested(uint256 indexed grantId, address indexed attester, bytes32 attestationHash, uint64 at);

    event GrantWithdrawn(uint256 indexed grantId, address indexed beneficiary, address token, uint256 amount, uint64 at);

    event GrantRefunded(uint256 indexed grantId, address indexed sponsor, address token, uint256 amount, uint64 at);

    // --- Receipts ---
    event ReceiptMinted(
        uint256 indexed tokenId,
        bytes32 indexed orderHash,
        address indexed buyer,
        address seller,
        address token,
        uint256 price,
        uint256 platformFee,
        string tokenURI
    );

    /// @notice Normalized attestation record (oracle / judge / verifier).
    event AttestationRecorded(bytes32 indexed ref, address indexed attester, bool ok, bytes32 attestationHash);
}
