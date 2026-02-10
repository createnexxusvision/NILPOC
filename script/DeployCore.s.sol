// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {DealEngine} from "../src/core/DealEngine.sol";
import {DeferredVault} from "../src/core/DeferredVault.sol";
import {PayoutRouter} from "../src/core/PayoutRouter.sol";
import {ReceiptNFT} from "../src/modules/ReceiptNFT.sol";

/// @notice Foundry deployment script.
/// Env vars:
/// - DEPLOYER_PRIVATE_KEY
/// - FEE_RECIPIENT
/// - PLATFORM_FEE_BPS (e.g. 200 == 2%)
contract DeployCore is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint16 feeBps = uint16(vm.envUint("PLATFORM_FEE_BPS"));

        vm.startBroadcast(pk);
        address admin = vm.addr(pk);

        DealEngine engine = new DealEngine(admin, feeRecipient, feeBps);
        DeferredVault vault = new DeferredVault(admin, true);
        PayoutRouter router = new PayoutRouter(admin);
        ReceiptNFT receipt = new ReceiptNFT(admin);

        // grant router permission to mint receipts by default
        receipt.grantRole(receipt.MINTER_ROLE(), address(router));

        vm.stopBroadcast();

        console2.log("DealEngine", address(engine));
        console2.log("DeferredVault", address(vault));
        console2.log("PayoutRouter", address(router));
        console2.log("ReceiptNFT", address(receipt));
    }
}
