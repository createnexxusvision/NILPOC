// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NILTypes} from "./NILTypes.sol";
import {NILEvents} from "./NILEvents.sol";
import {AttestationGate} from "./AttestationGate.sol";

/// @title PayoutRouter
/// @notice Deterministic payout splitting for ETH and ERC20 (USDC default).
/// @dev Unbounded recipient lists are dangerous; enforce an upper bound.
contract PayoutRouter is ReentrancyGuard, AttestationGate {
    using SafeERC20 for IERC20;

    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_RECIPIENTS = 50;

    struct Split {
        bytes32 splitHash; // hash of recipients array
        uint8 n; // number of recipients
        // packed recipients stored separately
    }

    uint256 public splitCount;
    mapping(uint256 => Split) public splits;
    mapping(uint256 => mapping(uint256 => NILTypes.SplitRecipient)) private _splitRecipients; // splitId => index => recipient

    uint256 public payoutCount;

    constructor(address admin) AttestationGate(admin) {}

    /// @notice Define a split. Default authorization: OPERATOR or ADMIN.
    function defineSplit(NILTypes.SplitRecipient[] calldata recipients) external returns (uint256 splitId) {
        require(isOperator(msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "PAYOUT: not authorized");
        uint256 n = recipients.length;
        require(n > 0 && n <= MAX_RECIPIENTS, "PAYOUT: bad recipients len");

        uint256 sum;
        bytes32 h = keccak256(abi.encode(recipients));
        for (uint256 i = 0; i < n; i++) {
            address r = recipients[i].recipient;
            uint16 b = recipients[i].bps;
            require(r != address(0), "PAYOUT: zero recipient");
            require(b > 0, "PAYOUT: zero bps");
            sum += b;
            _splitRecipients[splitCount][i] = recipients[i];
        }
        require(sum == BPS_DENOMINATOR, "PAYOUT: bps must sum 10000");

        splitId = splitCount;
        splits[splitId] = Split({splitHash: h, n: uint8(n)});
        splitCount++;

        emit NILEvents.SplitDefined(splitId, h, msg.sender);
    }

    function getSplitRecipient(uint256 splitId, uint256 index) external view returns (NILTypes.SplitRecipient memory) {
        return _splitRecipients[splitId][index];
    }

    /// @notice Execute a payout according to a split. Uses ref for app-level correlation.
    /// @param ref Arbitrary reference (e.g., orderHash, dealHash) for indexing.
    /// @param token address(0) for ETH, else ERC20.
    /// @param amount total amount to distribute.
    /// @param splitId previously defined split id.
    function payout(bytes32 ref, address token, uint256 amount, uint256 splitId) external payable nonReentrant returns (uint256 payoutId) {
        Split memory s = splits[splitId];
        require(s.n > 0, "PAYOUT: unknown split");
        require(amount > 0, "PAYOUT: zero amount");

        // Funds in
        if (token == NILTypes.NATIVE) {
            require(msg.value == amount, "PAYOUT: bad msg.value");
        } else {
            require(msg.value == 0, "PAYOUT: no eth");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Distribute
        uint256 remaining = amount;
        for (uint256 i = 0; i < s.n; i++) {
            NILTypes.SplitRecipient memory r = _splitRecipients[splitId][i];
            uint256 part = (amount * uint256(r.bps)) / BPS_DENOMINATOR;
            if (i == s.n - 1) {
                // dust to last recipient
                part = remaining;
            } else {
                remaining -= part;
            }

            if (token == NILTypes.NATIVE) {
                (bool ok, ) = r.recipient.call{value: part}("");
                require(ok, "PAYOUT: eth send failed");
            } else {
                IERC20(token).safeTransfer(r.recipient, part);
            }
        }

        payoutId = payoutCount++;
        emit NILEvents.PayoutExecuted(payoutId, ref, msg.sender, token, amount, splitId, uint64(block.timestamp));
    }
}
