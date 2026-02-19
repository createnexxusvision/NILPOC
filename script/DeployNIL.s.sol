// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {NILDealEscrow}        from "../src/NILDealEscrow.sol";
import {TexasNILDeferredVault} from "../src/TexasNILDeferredVault.sol";
import {ClipRevenueSplitter}  from "../src/ClipRevenueSplitter.sol";

/// @notice Deploy the three NIL demo contracts (NILDealEscrow,
///         TexasNILDeferredVault, ClipRevenueSplitter) to any EVM testnet.
///
/// Required env vars:
///   Wallet_Private_Key   -- funded deployer key
///   USDC_SEPOLIA         -- USDC token address on the target network
///
/// Usage (Sepolia, broadcast + verify):
///   forge script script/DeployNIL.s.sol \
///       --rpc-url sepolia --broadcast --verify
contract DeployNIL is Script {
    function run() external {
        uint256 pk = vm.envUint("Wallet_Private_Key");
        address usdc = vm.envAddress("USDC_SEPOLIA");

        vm.startBroadcast(pk);
        address deployer = vm.addr(pk);

        // Deploy NILDealEscrow -- owner = deployer
        NILDealEscrow escrow = new NILDealEscrow();

        // Deploy TexasNILDeferredVault -- deployer is the initial verifier
        address[] memory verifiers = new address[](1);
        verifiers[0] = deployer;
        TexasNILDeferredVault vault = new TexasNILDeferredVault(verifiers);

        // Deploy ClipRevenueSplitter -- token = USDC
        ClipRevenueSplitter splitter = new ClipRevenueSplitter(usdc);

        vm.stopBroadcast();

        // Print .env-ready output
        console2.log("# -- NIL Demo Contracts (paste into .env) --");
        console2.log("SEPOLIA_ESCROW=%s",    address(escrow));
        console2.log("SEPOLIA_VAULT_NIL=%s", address(vault));
        console2.log("SEPOLIA_SPLITTER=%s",  address(splitter));
    }
}
