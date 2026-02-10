// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library NILTypes {
    address internal constant NATIVE = address(0);
    enum DealStatus { NONE, CREATED, FUNDED, DELIVERED, DISPUTED, SETTLED, REFUNDED }

    struct Deal {
        address sponsor;
        address athlete;
        address token;
        uint256 amount;
        uint64 deadline;
        bytes32 termsHash;
        bytes32 evidenceHash;
        uint64 deliveredAt;
        DealStatus status;
    }

    struct Grant {
        address sponsor;
        address beneficiary;
        address token;
        uint256 amount;
        uint64 unlockTime;
        bytes32 termsHash;
        bytes32 attestationHash;
        bool attested;
        bool withdrawn;
        bool refunded;
    }

    struct SplitRecipient { address recipient; uint16 bps; }
}
