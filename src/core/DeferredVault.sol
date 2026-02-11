// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NILTypes} from "./NILTypes.sol";
import {NILEvents} from "./NILEvents.sol";
import {ProtocolPausable} from "./ProtocolPausable.sol";

/// @title DeferredVault
/// @notice Timelocked escrow vault for NIL funds (ETH or ERC20), optionally gated by attestations.
contract DeferredVault is ReentrancyGuard, ProtocolPausable {
    using SafeERC20 for IERC20;

    uint256 public grantCount;
    mapping(uint256 => NILTypes.Grant) private _grants;

    bool public requireAttestation;

    constructor(address admin, bool requireAttestation_) AttestationGate(admin) {
        requireAttestation = requireAttestation_;
    }

    function setRequireAttestation(bool v) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VAULT: admin");
        requireAttestation = v;
    }

    /// @notice Sponsor creates and funds a grant.
    function createGrant(
        address beneficiary,
        address token,
        uint256 amount,
        uint64 unlockTime,
        bytes32 termsHash
    ) external payable nonReentrant returns (uint256 grantId)  whenNotPaused {
        require(beneficiary != address(0), "VAULT: zero beneficiary");
        require(amount > 0, "VAULT: zero amount");
        require(unlockTime > block.timestamp, "VAULT: bad unlock");

        if (token == NILTypes.NATIVE) {
            require(msg.value == amount, "VAULT: bad msg.value");
        } else {
            require(msg.value == 0, "VAULT: no eth");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        grantId = grantCount++;
        NILTypes.Grant storage g = _grants[grantId];
        g.sponsor = msg.sender;
        g.beneficiary = beneficiary;
        g.token = token;
        g.amount = amount;
        g.unlockTime = unlockTime;
        g.termsHash = termsHash;

        emit NILEvents.GrantCreated(grantId, msg.sender, beneficiary, token, amount, unlockTime, termsHash);
    }

    /// @notice Attester (oracle/judge) attests that off-chain conditions are satisfied.
    function attestGrant(uint256 grantId, bytes32 attestationHash) external  whenNotPaused {
        require(isOracle(msg.sender) || isJudge(msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VAULT: not attester");
        NILTypes.Grant storage g = _grants[grantId];
        require(!g.attested, "VAULT: already attested");
        require(!g.withdrawn && !g.refunded, "VAULT: closed");

        g.attested = true;
        g.attestationHash = attestationHash;

        emit NILEvents.GrantAttested(grantId, msg.sender, attestationHash, uint64(block.timestamp));
    }

    /// @notice Beneficiary withdraws after unlock (and optional attestation).
    function withdraw(uint256 grantId) external nonReentrant {
        NILTypes.Grant storage g = _grants[grantId];
        require(msg.sender == g.beneficiary, "VAULT: not beneficiary");
        require(!g.withdrawn && !g.refunded, "VAULT: closed");
        require(block.timestamp >= g.unlockTime, "VAULT: locked");
        if (requireAttestation) {
            require(g.attested, "VAULT: needs attestation");
        }

        uint256 amount = g.amount;
        g.amount = 0;
        g.withdrawn = true;

        _send(g.token, g.beneficiary, amount);
        emit NILEvents.GrantWithdrawn(grantId, g.beneficiary, g.token, amount, uint64(block.timestamp));
    }

    /// @notice Sponsor can refund before unlock, if not withdrawn.
    function refund(uint256 grantId) external nonReentrant {
        NILTypes.Grant storage g = _grants[grantId];
        require(msg.sender == g.sponsor || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VAULT: not sponsor/admin");
        require(!g.withdrawn && !g.refunded, "VAULT: closed");
        require(block.timestamp < g.unlockTime, "VAULT: after unlock");

        uint256 amount = g.amount;
        g.amount = 0;
        g.refunded = true;

        _send(g.token, g.sponsor, amount);
        emit NILEvents.GrantRefunded(grantId, g.sponsor, g.token, amount, uint64(block.timestamp));
    }

    function getGrant(uint256 grantId) external view returns (NILTypes.Grant memory) {
        return _grants[grantId];
    }

    function _send(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        require(to != address(0), "VAULT: zero to");
        if (token == NILTypes.NATIVE) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "VAULT: eth send failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    receive() external payable {}
}
