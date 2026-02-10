// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AttestationGate
/// @notice Minimal role authority for oracle/judge/verifier attestations.
/// @dev Use roles instead of onlyOwner to reduce "god mode" blast radius.
contract AttestationGate is AccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant JUDGE_ROLE = keccak256("JUDGE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    function isOracle(address a) public view returns (bool) { return hasRole(ORACLE_ROLE, a); }
    function isJudge(address a) public view returns (bool) { return hasRole(JUDGE_ROLE, a); }
    function isOperator(address a) public view returns (bool) { return hasRole(OPERATOR_ROLE, a); }
}
