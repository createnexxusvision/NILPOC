// spdx-license-identifier: MIT
pragma solidity ^0.8.19;

/*
    BaseNIL
     Shared building blocks for all NIL smart contracts.

     Provides:
     - Safe ETH & ERC20 transfers
     - Reentrancy protection
     - Ownership / admin control
     - A generic DealStatus enum & core deal fields you can reuse
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


abstract contract BaseNIL is ownable, ReentrancyGuard {
    // ----- Common statuses for "deal-like" flows -----
    enum DealStatus {
        Pending,   // Created / funded, waiting for conditions (time, verification, etc.)
        Cancellable, // Can be cancelled/refunded under some rules
        Withdrawable,  // Athlete can take the money
        Withdrawn,  // funds claimed by athlete
        Refunded    // funds returned to sponsor
    }

    // ----- Generic core of NIL deal -----
    struct DealCore {
        address athlete;
        address sponsor;
        uint256 amount;       
        uint64 unlockTime;   // Time-Lock for athlete access
        bytes32 metadataHash; // Off-chain metadata/terms (IPFS hash, etc.)
        DealStatus status;
    }

    // Emitted whenever ETH or ERC20 is moved out of a NIL contract
    event FundsSent(address indexed to, uint256 amount, address indexed token);
    event FundsReceived(address indexed from, uint256 amount, address indexed token);

    // --------- Internal money helpers ---------

    /**
     * @dev Safely send native ETH to e receipient.
     * Uses call() and checks return value.     
     */
    function _sendETH(address to, uint256 amount) internal {
        require(to != address(0), "BaseNIL: zero address");
        if (amount == 0) return;

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "BaseNIL: ETH transfer failed");
        emit FundsSent(to, amount, address(0));
}

/**
 * @dev Safely transfer ERC20 tokens to a recipient.
 * Assumes this contract already holds enough balance.      
 */
    function _sendERC20(address token, address to, uint256 amount) internal {
        require(to != address(0), "BaseNIL: zero address");
        if (amount == 0) return;

        IERC20 erc20 = IERC20(token);
        require(erc20.transfer(to, amount), "BaseNIL: ERC20 transfer failed");
        emit FundsSent(to, amount, token);
    }

    /**
     * @dev Internal hook to record incoming ETH.
     * Call in receive() or payuable functions if you want a unified event log.
     */
    function -onReceiveETH(address from, uint256 amount) internal {
        emit FundsReceived(from, amount, address(0));
    }

    /**
     * @dev Internal hook to record incoming ERC20 tokens.
     * You'd call this inside a function where sponsor first approves & then calls deposit.
     */
    function _onReceiveERC20(address from, uint256 amount, address token) internal {
        emit FundsReceived(from, amount, token);
    }
    // --------- Time / status helpers ---------

    /**
     * @dev Simple helper to check if a timelock has passed.
     */
    function _isUnlocked(uint64 unlockTime) internal view returns (bool) {
        return block.timestamp >= unlockTime;
    }
}