// spdx-license-identifier: MIT
pragma solidity ^0.8.19;

/*
    VerifierRole

    Drop-in module for "certain addresses are allowed to attest or approve stuff".

    Example use cases:
    - UIL / college compliance marking "enrollment confirmed".
    - Trusted oracle relayers marking "conditions met".
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract VerifierRole is Ownable {
    mapping(address => bool) public isVerifier;

    event VerifierUpdated(address indexed verifier, bool allowed);

    modifier onlyVerifier() {
        require(
            isVerifier[msg.sender],
            "VerifierRole: not an authorized verifier"
        );
        _;
    }

    function _setVerifier(address verifier, bool allowed) internal {
        isVerifier[verifier] = allowed;
        emit VerifierUpdated(verifier, allowed);
    }

    /**
     * @dev Public function for owner (admin) to manage verifiers.
     *  Can be UIL, protocol owner, etc.
     */
    function setVerifier(address verifier, bool allowed) external onlyOwner {
        _setVerifier(verifier, allowed);
    }
}
