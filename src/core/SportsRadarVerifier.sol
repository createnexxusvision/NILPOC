// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AttestationGate} from "./AttestationGate.sol";
import {NILEvents} from "./NILEvents.sol";

/// @title SportsRadarVerifier
/// @notice Chainlink Functions-friendly verification adapter for SportsRadar (or any stats API).
/// @dev This contract intentionally avoids importing Chainlink libs to keep the repo lightweight.
///      A Chainlink Functions "fulfiller" (or your oracle relayer) should call `fulfill` with an attestation hash.
///      Use the emitted RequestVerification event as the off-chain trigger.
contract SportsRadarVerifier is AttestationGate {
    struct Request {
        bytes32 ref;          // dealId / grantId / orderId hash - app-defined correlation
        bytes32 queryHash;    // hash of off-chain query params (gameId, playerId, stat thresholds, etc.)
        address requester;    // who requested verification
        bool fulfilled;
        bytes32 attestationHash; // hash pointer to off-chain proof bundle (IPFS/Arweave/DB)
        bool ok;
    }

    uint256 public requestCount;
    mapping(uint256 => Request) public requests;

    event RequestVerification(uint256 indexed requestId, bytes32 indexed ref, bytes32 queryHash, address requester);
    event VerificationFulfilled(uint256 indexed requestId, bytes32 indexed ref, bool ok, bytes32 attestationHash, address fulfiller);

    constructor(address admin) AttestationGate(admin) {}

    /// @notice Create a verification request. Anyone may request; apps can restrict at higher layer.
    function requestVerification(bytes32 ref, bytes32 queryHash) external returns (uint256 requestId) {
        requestId = requestCount++;
        requests[requestId] = Request({
            ref: ref,
            queryHash: queryHash,
            requester: msg.sender,
            fulfilled: false,
            attestationHash: bytes32(0),
            ok: false
        });

        emit RequestVerification(requestId, ref, queryHash, msg.sender);
    }

    /// @notice Fulfill a request. Restricted to ORACLE_ROLE.
    /// @dev For Chainlink Functions, your Functions consumer/relayer would hold ORACLE_ROLE and call this with results.
    function fulfill(uint256 requestId, bool ok, bytes32 attestationHash) external {
        require(isOracle(msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VERIFY: not oracle");
        Request storage r = requests[requestId];
        require(!r.fulfilled, "VERIFY: already fulfilled");

        r.fulfilled = true;
        r.ok = ok;
        r.attestationHash = attestationHash;

        emit VerificationFulfilled(requestId, r.ref, ok, attestationHash, msg.sender);

        // Optional: also emit a normalized attestation event for your indexer.
        emit NILEvents.AttestationRecorded(r.ref, msg.sender, ok, attestationHash);
    }
}
