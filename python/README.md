# NILPOC Python Tooling

This folder is a thin Python layer that:
- Calls deployed contracts (DealEngine, DeferredVault, PayoutRouter, ReceiptNFT)
- Indexes unified events into Postgres (event-sourced)
- Runs security-style property tests (Hypothesis) against a local Anvil fork

## Quickstart

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r python/requirements.txt
cp python/.env.example .env
```

## Compile ABIs

Use Foundry to export ABIs:

```bash
forge build
mkdir -p deployments/abis
jq '.abi' out/DealEngine.sol/DealEngine.json > deployments/abis/DealEngine.abi.json
jq '.abi' out/DeferredVault.sol/DeferredVault.json > deployments/abis/DeferredVault.abi.json
jq '.abi' out/PayoutRouter.sol/PayoutRouter.json > deployments/abis/PayoutRouter.abi.json
jq '.abi' out/ReceiptNFT.sol/ReceiptNFT.json > deployments/abis/ReceiptNFT.abi.json
```

(If `jq` is not installed, you can copy ABIs manually from the `out/` json artifacts.)

## Local testing (Anvil)

```bash
anvil
# in another terminal
pytest -q python/security
```
