import json
from pathlib import Path
from web3 import Web3

ABI_DIR = Path(__file__).resolve().parents[2] / "deployments" / "abis"


def load_abi(name: str):
    p = ABI_DIR / f"{name}.abi.json"
    return json.loads(p.read_text())


def contract(w3: Web3, name: str, address: str):
    return w3.eth.contract(address=Web3.to_checksum_address(address), abi=load_abi(name))
