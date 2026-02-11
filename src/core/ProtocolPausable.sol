// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {AttestationGate} from "./AttestationGate.sol";

/// @title ProtocolPausable
/// @notice Shared pause controls gated by OPERATOR_ROLE or DEFAULT_ADMIN_ROLE.
/// @dev Keep pause scope per-contract. Do NOT use a single global pause unless you truly want global kill-switch semantics.
abstract contract ProtocolPausable is Pausable, AttestationGate {
    event ProtocolPaused(address indexed by);
    event ProtocolUnpaused(address indexed by);

    modifier onlyOperatorOrAdmin() {
        require(isOperator(msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "PAUSE: not authorized");
        _;
    }

    function pause() external onlyOperatorOrAdmin {
        _pause();
        emit ProtocolPaused(msg.sender);
    }

    function unpause() external onlyOperatorOrAdmin {
        _unpause();
        emit ProtocolUnpaused(msg.sender);
    }
}
