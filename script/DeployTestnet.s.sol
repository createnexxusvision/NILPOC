// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {DealEngine}    from "../src/core/DealEngine.sol";
import {DeferredVault} from "../src/core/DeferredVault.sol";
import {PayoutRouter}  from "../src/core/PayoutRouter.sol";
import {ReceiptNFT}    from "../src/modules/ReceiptNFT.sol";

/// @notice Full testnet deployment: deploy all four core contracts, wire roles,
///         and print addresses for .env.
///
/// Required env vars:
///   DEPLOYER_PRIVATE_KEY
///   FEE_RECIPIENT            -- address that receives the platform fee
///   PLATFORM_FEE_BPS         -- e.g. 200 == 2%
///
/// Optional env vars (leave blank to skip role grants):
///   ORACLE_ADDRESS
///   JUDGE_ADDRESS
///   OPERATOR_ADDRESS
///
/// Usage:
///   # Sepolia (dry run)
///   forge script script/DeployTestnet.s.sol --rpc-url sepolia
///
///   # Sepolia (broadcast + verify)
///   forge script script/DeployTestnet.s.sol \
///       --rpc-url sepolia --broadcast --verify
///
///   # Base Sepolia
///   forge script script/DeployTestnet.s.sol \
///       --rpc-url base_sepolia --broadcast --verify
contract DeployTestnet is Script {
    function run() external {
        uint256 pk          = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint16  feeBps       = uint16(vm.envUint("PLATFORM_FEE_BPS"));

        address oracle   = vm.envOr("ORACLE_ADDRESS",   address(0));
        address judge    = vm.envOr("JUDGE_ADDRESS",    address(0));
        address operator = vm.envOr("OPERATOR_ADDRESS", address(0));

        vm.startBroadcast(pk);
        address admin = vm.addr(pk);

        // Deploy core contracts
        DealEngine    engine  = new DealEngine(admin, feeRecipient, feeBps);
        DeferredVault vault   = new DeferredVault(admin, true);
        PayoutRouter  router  = new PayoutRouter(admin);
        ReceiptNFT    receipt = new ReceiptNFT(admin);

        // Wire ReceiptNFT minter to router
        receipt.grantRole(receipt.MINTER_ROLE(), address(router));

        // Optional role grants
        if (oracle != address(0)) {
            vault.grantRole(vault.ORACLE_ROLE(), oracle);
            engine.grantRole(engine.ORACLE_ROLE(), oracle);
            router.grantRole(router.ORACLE_ROLE(), oracle);
        }
        if (judge != address(0)) {
            engine.grantRole(engine.JUDGE_ROLE(), judge);
        }
        if (operator != address(0)) {
            engine.grantRole(engine.OPERATOR_ROLE(), operator);
            vault.grantRole(vault.OPERATOR_ROLE(), operator);
            router.grantRole(router.OPERATOR_ROLE(), operator);
        }

        vm.stopBroadcast();

        // Print addresses (.env friendly)
        console2.log("# Paste these into your .env");
        console2.log("DEAL_ENGINE_ADDRESS=%s",  address(engine));
        console2.log("VAULT_ADDRESS=%s",        address(vault));
        console2.log("ROUTER_ADDRESS=%s",       address(router));
        console2.log("RECEIPT_NFT_ADDRESS=%s",  address(receipt));
    }
}
