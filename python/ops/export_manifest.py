import json
import os
from pathlib import Path
import shutil

"""Export deployment manifests + ABIs for TS/Python/Indexer consumers.

This script expects Foundry broadcast artifacts like:
  broadcast/DeployCore.s.sol/<chainId>/run-latest.json

It will:
  - write deployments/manifests/<chainId>.json
  - copy ABI JSON from out/ to deployments/abis/
"""

ROOT = Path(__file__).resolve().parents[2]  # repo root
OUT_DIR = ROOT / "out"
BROADCAST_DIR = ROOT / "broadcast"
MANIFEST_DIR = ROOT / "deployments" / "manifests"
ABIS_DIR = ROOT / "deployments" / "abis"

def load_run(chain_id: str):
    run_path = BROADCAST_DIR / "DeployCore.s.sol" / chain_id / "run-latest.json"
    if not run_path.exists():
        raise FileNotFoundError(f"Missing Foundry broadcast: {run_path}")
    return json.loads(run_path.read_text())

def extract_deployed_addresses(run_json):
    addrs = {}
    txs = run_json.get("transactions", [])
    for tx in txs:
        if tx.get("transactionType") == "CREATE":
            name = tx.get("contractName") or tx.get("contract")
            addr = tx.get("contractAddress")
            if name and addr:
                addrs[name] = addr
    return addrs

def copy_abis():
    ABIS_DIR.mkdir(parents=True, exist_ok=True)
    if not OUT_DIR.exists():
        print("No out/ directory found; run `forge build` first.")
        return
    # Copy all ABI JSON artifacts (keep filename stable)
    for p in OUT_DIR.rglob("*.json"):
        # Foundry artifact json contains abi + bytecode; keep only those for contracts
        try:
            data = json.loads(p.read_text())
        except Exception:
            continue
        if "abi" in data and isinstance(data["abi"], list):
            dst = ABIS_DIR / p.name
            dst.write_text(json.dumps({"contractName": data.get("contractName"), "abi": data["abi"]}, indent=2))

def main():
    chain_id = os.environ.get("CHAIN_ID")
    if not chain_id:
        raise SystemExit("Set CHAIN_ID env var, e.g. CHAIN_ID=8453")

    run = load_run(chain_id)
    addrs = extract_deployed_addresses(run)

    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path = MANIFEST_DIR / f"{chain_id}.json"
    manifest = {
        "chainId": int(chain_id),
        "generatedAt": run.get("timestamp"),
        "contracts": addrs,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print("Wrote manifest:", manifest_path)

    copy_abis()
    print("ABIs exported to:", ABIS_DIR)

if __name__ == "__main__":
    main()
