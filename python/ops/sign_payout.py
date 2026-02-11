import os
from eth_account import Account
from eth_account.messages import encode_typed_data
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

"""Helper to produce EIP-712 signatures for PayoutRouter.defineSplitWithSig and payoutWithSig.

Usage:
  python -m ops.sign_payout

Set env:
  PRIVATE_KEY=...
  CHAIN_ID=11155111
  ROUTER_ADDRESS=0x...
"""

DOMAIN_NAME = "NILPOC-PayoutRouter"
DOMAIN_VERSION = "1"

def domain(chain_id: int, verifying_contract: str):
    return {
        "name": DOMAIN_NAME,
        "version": DOMAIN_VERSION,
        "chainId": chain_id,
        "verifyingContract": Web3.to_checksum_address(verifying_contract),
    }

def sign_define_split(private_key: str, chain_id: int, verifying_contract: str, recipients_hash: bytes, nonce: int, deadline: int):
    typed = {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "DefineSplit": [
                {"name": "recipientsHash", "type": "bytes32"},
                {"name": "nonce", "type": "uint256"},
                {"name": "deadline", "type": "uint256"},
            ],
        },
        "primaryType": "DefineSplit",
        "domain": domain(chain_id, verifying_contract),
        "message": {
            "recipientsHash": recipients_hash,
            "nonce": nonce,
            "deadline": deadline,
        },
    }
    msg = encode_typed_data(full_message=typed)
    acct = Account.from_key(private_key)
    sig = acct.sign_message(msg).signature
    return acct.address, sig.hex()

def sign_payout(private_key: str, chain_id: int, verifying_contract: str, ref: bytes, token: str, amount: int, split_id: int, nonce: int, deadline: int):
    typed = {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "Payout": [
                {"name": "ref", "type": "bytes32"},
                {"name": "token", "type": "address"},
                {"name": "amount", "type": "uint256"},
                {"name": "splitId", "type": "uint256"},
                {"name": "nonce", "type": "uint256"},
                {"name": "deadline", "type": "uint256"},
            ],
        },
        "primaryType": "Payout",
        "domain": domain(chain_id, verifying_contract),
        "message": {
            "ref": ref,
            "token": Web3.to_checksum_address(token),
            "amount": amount,
            "splitId": split_id,
            "nonce": nonce,
            "deadline": deadline,
        },
    }
    msg = encode_typed_data(full_message=typed)
    acct = Account.from_key(private_key)
    sig = acct.sign_message(msg).signature
    return acct.address, sig.hex()

if __name__ == "__main__":
    pk = os.environ["PRIVATE_KEY"]
    chain_id = int(os.environ.get("CHAIN_ID", "11155111"))
    router = os.environ["ROUTER_ADDRESS"]

    # Example only: you still need to compute recipients_hash in your app layer.
    recipients_hash = Web3.keccak(text="example_recipients_hash")
    signer, sig = sign_define_split(pk, chain_id, router, recipients_hash, nonce=0, deadline=2**31-1)
    print("Signer:", signer)
    print("DefineSplit sig:", sig)
