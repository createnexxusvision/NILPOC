// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Backwards-compatible name for earlier NILPOC experiments.
/// @dev The canonical implementation now lives in `src/core/DealEngine.sol`.

import {DealEngine} from "./core/DealEngine.sol";

contract NILDealEscrow is DealEngine {
    constructor(address admin, address feeRecipient, uint16 feeBps)
        DealEngine(admin, feeRecipient, feeBps)
    {}
}
