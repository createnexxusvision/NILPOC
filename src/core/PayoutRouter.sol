// SP
    /// @notice Execute a payout using an EIP-712 signature from an authorized operator/admin.
    /// @dev Caller can be any relayer; signer authorization is enforced via signature.
    function payoutWithSig(
        bytes32 ref,
        address token,
        uint256 amount,
        uint256 splitId,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused nonReentrant returns (uint256 payoutId) {
        require(block.timestamp <= deadline, "PAYOUT: sig expired");
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(PAYOUT_TYPEHASH, ref, token, amount, splitId, nonce, deadline))
        );
        address signer = digest.recover(signature);
        require(isOperator(signer) || hasRole(DEFAULT_ADMIN_ROLE, signer), "PAYOUT: bad signer");
        require(nonces[signer] == nonce, "PAYOUT: bad nonce");
        nonces[signer] = nonce + 1;

        // Execute payout using the standard function logic, but attribute to signer for indexing.
        // We inline a minimal copy to preserve correct msg.value semantics.
        Split memory s = splits[splitId];
        require(s.n > 0, "PAYOUT: unknown split");
        require(amount > 0, "PAYOUT: zero amount");

        if (token == NILTypes.NATIVE) {
            require(msg.value == amount, "PAYOUT: bad msg.value");
            for (uint256 i = 0; i < s.n; i++) {
                NILTypes.SplitRecipient memory r = _splitRecipients[splitId][i];
                uint256 share = (amount * r.bps) / BPS_DENOMINATOR;
                (bool ok, ) = r.recipient.call{value: share}("");
                require(ok, "PAYOUT: eth send failed");
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            for (uint256 i = 0; i < s.n; i++) {
                NILTypes.SplitRecipient memory r = _splitRecipients[splitId][i];
                uint256 share = (amount * r.bps) / BPS_DENOMINATOR;
                IERC20(token).safeTransfer(r.recipient, share);
            }
        }

        payoutId = payoutCount++;
        emit NILEvents.PayoutExecuted(payoutId, ref, msg.sender, signer, token, amount, splitId, uint64(block.timestamp));
    }

DX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NILTypes} from "./NILTypes.sol";
import {NILEvents} from "./NILEvents.sol";
import {ProtocolPausable} from "./ProtocolPausable.sol";

/// @title PayoutRouter
/// @notice Deterministic payout splitting for ETH and ERC20 (USDC default).
/// @dev Unbounded recipient lists are dangerous; enforce an upper bound.
contract PayoutRouter is ReentrancyGuard, EIP712, ProtocolPausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_RECIPIENTS = 50;

    // EIP-712 typed data (allows permissionless relayers while preserving authorization)
    bytes32 public constant SPLIT_TYPEHASH = keccak256("DefineSplit(bytes32 recipientsHash,uint256 nonce,uint256 deadline)");
    bytes32 public constant PAYOUT_TYPEHASH = keccak256("Payout(bytes32 ref,address token,uint256 amount,uint256 splitId,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public nonces;

    struct Split {
        bytes32 splitHash; // hash of recipients array
        uint8 n; // number of recipients
        // packed recipients stored separately
    }

    uint256 public splitCount;
    mapping(uint256 => Split) public splits;
    mapping(uint256 => mapping(uint256 => NILTypes.SplitRecipient)) private _splitRecipients; // splitId => index => recipient

    uint256 public payoutCount;

    constructor(address admin)
        AttestationGate(admin)
        EIP712("NILPOC-PayoutRouter","1")
    {}

    /// @notice Define a split. Default authorization: OPERATOR or ADMIN.
    function defineSplit(NILTypes.SplitRecipient[] calldata recipients) external whenNotPaused returns (uint256 splitId) {
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

    /// @notice Define a split using an EIP-712 signature from an authorized operator/admin.
    /// @dev Enables permissionless relaying while keeping authorization in signatures.
    function defineSplitWithSig(
        NILTypes.SplitRecipient[] calldata recipients,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused returns (uint256 splitId) {
        require(block.timestamp <= deadline, "PAYOUT: sig expired");
        uint256 n = recipients.length;
        require(n > 0 && n <= MAX_RECIPIENTS, "PAYOUT: bad recipients len");

        bytes32 recipientsHash = keccak256(abi.encode(recipients));
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(SPLIT_TYPEHASH, recipientsHash, nonce, deadline)));
        address signer = digest.recover(signature);
        require(isOperator(signer) || hasRole(DEFAULT_ADMIN_ROLE, signer), "PAYOUT: bad signer");
        require(nonces[signer] == nonce, "PAYOUT: bad nonce");
        nonces[signer] = nonce + 1;

        uint256 sum;
        bytes32 h = recipientsHash;
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

        emit NILEvents.SplitDefined(splitId, h, signer);
    }


    function getSplitRecipient(uint256 splitId, uint256 index) external view returns (NILTypes.SplitRecipient memory) {
        return _splitRecipients[splitId][index];
    }

    /// @notice Execute a payout according to a split. Uses ref for app-level correlation.
    /// @param ref Arbitrary reference (e.g., orderHash, dealHash) for indexing.
    /// @param token address(0) for ETH, else ERC20.
    /// @param amount total amount to distribute.
    /// @param splitId previously defined split id.
    function payout(bytes32 ref, address token, uint256 amount, uint256 splitId) external payable whenNotPaused nonReentrant returns (uint256 payoutId) {
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
        emit NILEvents.PayoutExecuted(payoutId, ref, msg.sender, msg.sender, token, amount, splitId, uint64(block.timestamp));
    }
}
