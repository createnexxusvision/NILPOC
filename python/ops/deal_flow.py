"""Example: create -> deliver -> settle a deal using DealEngine.

Run on Anvil or Sepolia/Base/Polygon.

Requirements:
- .env filled
- ABIs exported into deployments/abis
"""

import os
from dotenv import load_dotenv
from web3 import Web3
from eth_account import Account
from ops.contracts import contract

load_dotenv()

RPC_URL = os.environ["RPC_URL"]
PK = os.environ["PRIVATE_KEY"]
ENGINE = os.environ["DEAL_ENGINE_ADDRESS"]

w3 = Web3(Web3.HTTPProvider(RPC_URL))
acct = Account.from_key(PK)

engine = contract(w3, "DealEngine", ENGINE)

# TODO: replace with real addresses
ATHLETE = acct.address
TOKEN = "0x0000000000000000000000000000000000000000"  # ETH
AMOUNT = w3.to_wei(0.01, "ether")
DEADLINE = int(w3.eth.get_block("latest")["timestamp"]) + 3600
TERMS_HASH = w3.keccak(text="terms-v1")
EVIDENCE_HASH = w3.keccak(text="delivered")


def send(tx):
    tx.update(
        {
            "from": acct.address,
            "nonce": w3.eth.get_transaction_count(acct.address),
            "chainId": int(os.environ.get("CHAIN_ID", w3.eth.chain_id)),
            "gas": tx.get("gas", 600_000),
            "maxFeePerGas": tx.get("maxFeePerGas", w3.to_wei(2, "gwei")),
            "maxPriorityFeePerGas": tx.get("maxPriorityFeePerGas", w3.to_wei(1, "gwei")),
        }
    )
    signed = acct.sign_transaction(tx)
    h = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(h)
    return receipt


def main():
    # create deal
    call = engine.functions.createDeal(ATHLETE, TOKEN, AMOUNT, DEADLINE, TERMS_HASH)
    tx = call.build_transaction({"value": AMOUNT})
    r = send(tx)
    print("createDeal tx", r.transactionHash.hex())

    # extract dealId from logs (DealCreated)
    ev = engine.events.DealCreated().process_receipt(r)[0]["args"]
    deal_id = ev["dealId"]
    print("dealId", deal_id)

    # deliver
    call2 = engine.functions.markDelivered(deal_id, EVIDENCE_HASH)
    r2 = send(call2.build_transaction({}))
    print("markDelivered tx", r2.transactionHash.hex())

    # settle
    call3 = engine.functions.approveAndSettle(deal_id)
    r3 = send(call3.build_transaction({}))
    print("approveAndSettle tx", r3.transactionHash.hex())


if __name__ == "__main__":
    main()
