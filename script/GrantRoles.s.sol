// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {DealEngine}    from "../src/core/DealEngine.sol";
import {DeferredVault} from "../src/core/DeferredVault.sol";
import {PayoutRouter}  from "../src/core/PayoutRouter.sol";
import {ReceiptNFT}    from "../src/modules/ReceiptNFT.sol";

/// @notice Post-deployment role setup script.
/// Run AFTER DeployCore.s.sol has been executed and the four contract
/// addresses have been written into the environment.
///
/// Required env vars (set in .env or exported before running):
///   DEPLOYER_PRIVATE_KEY        -- deployer / DEFAULT_ADMIN wallet
///   DEAL_ENGINE_ADDRESS
///   VAULT_ADDRESS
///   ROUTER_ADDRESS
///   RECEIPT_NFT_ADDRESS
///
/// Optional role-holder addresses (leave blank to skip):
///   ORACLE_ADDRESS              -- wallet that attests grants / resolves oracles
///   JUDGE_ADDRESS               -- wallet that resolves disputes in DealEngine
///   OPERATOR_ADDRESS            -- wallet that defines splits / manages router
///
/// Usage:
///   # Local Anvil
///   forge script script/GrantRoles.s.sol --rpc-url localhost --broadcast
///
///   # Sepolia
///   forge script script/GrantRoles.s.sol \
///       --rpc-url sepolia --broadcast --verify
contract GrantRoles is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        DealEngine    engine  = DealEngine(payable(vm.envAddress("DEAL_ENGINE_ADDRESS")));
        DeferredVault vault   = DeferredVault(payable(vm.envAddress("VAULT_ADDRESS")));
        PayoutRouter  router  = PayoutRouter(payable(vm.envAddress("ROUTER_ADDRESS")));
        ReceiptNFT    receipt = ReceiptNFT(vm.envAddress("RECEIPT_NFT_ADDRESS"));

        // Optional -- skip if not set
        address oracle   = vm.envOr("ORACLE_ADDRESS",   address(0));
        address judge    = vm.envOr("JUDGE_ADDRESS",    address(0));
        address operator = vm.envOr("OPERATOR_ADDRESS", address(0));

        vm.startBroadcast(pk);

        // Oracle role (DeferredVault + DealEngine + PayoutRouter)
        if (oracle != address(0)) {
            vault.grantRole(vault.ORACLE_ROLE(), oracle);
            engine.grantRole(engine.ORACLE_ROLE(), oracle);
            router.grantRole(router.ORACLE_ROLE(), oracle);
            console2.log("ORACLE_ROLE granted to", oracle);
        }

        // Judge role (DealEngine)
        if (judge != address(0)) {
            engine.grantRole(engine.JUDGE_ROLE(), judge);
            console2.log("JUDGE_ROLE granted to", judge);
        }

        // Operator role (all three core contracts)
        if (operator != address(0)) {
            engine.grantRole(engine.OPERATOR_ROLE(), operator);
            vault.grantRole(vault.OPERATOR_ROLE(), operator);
            router.grantRole(router.OPERATOR_ROLE(), operator);
            console2.log("OPERATOR_ROLE granted to", operator);
        }

        // Ensure router can mint ReceiptNFTs (idempotent)
        receipt.grantRole(receipt.MINTER_ROLE(), address(router));
        console2.log("MINTER_ROLE (re-)granted to router", address(router));

        vm.stopBroadcast();

        console2.log("Role setup complete.");
        console2.log("  DealEngine  ", address(engine));
        console2.log("  Vault       ", address(vault));
        console2.log("  Router      ", address(router));
        console2.log("  ReceiptNFT  ", address(receipt));
    }
}
