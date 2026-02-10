import json
import os
from dataclasses import dataclass
from typing import Dict, Any, Iterable, List

import psycopg2
from dotenv import load_dotenv
from web3 import Web3
from web3._utils.events import get_event_data

from ops.contracts import load_abi

load_dotenv()

@dataclass
class ContractEventDef:
    name: str
    abi: Dict[str, Any]


def load_event_abis(contract_name: str) -> Dict[str, Dict[str, Any]]:
    """Return mapping event_signature_hex -> event_abi"""
    abis = load_abi(contract_name)
    events = {}
    w3 = Web3()
    for item in abis:
        if item.get("type") != "event":
            continue
        sig = w3.keccak(text=f"{item['name']}({','.join([i['type'] for i in item['inputs']])})").hex()
        events[sig] = item
    return events


EVENT_ABIS: Dict[str, Dict[str, Dict[str, Any]]] = {
    "DealEngine": load_event_abis("DealEngine"),
    "DeferredVault": load_event_abis("DeferredVault"),
    "PayoutRouter": load_event_abis("PayoutRouter"),
    "ReceiptNFT": load_event_abis("ReceiptNFT"),
}


def connect_db():
    return psycopg2.connect(os.environ["POSTGRES_DSN"])


def upsert_current(cur, chain_id: int, event_name: str, args: Dict[str, Any]):
    """Apply deterministic upserts for current-state tables."""
    if event_name == "DealCreated":
        cur.execute(
            """
            INSERT INTO deals_current(chain_id, deal_id, sponsor, athlete, token, amount, deadline, terms_hash, status)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (chain_id, deal_id) DO UPDATE SET
              sponsor=EXCLUDED.sponsor,
              athlete=EXCLUDED.athlete,
              token=EXCLUDED.token,
              amount=EXCLUDED.amount,
              deadline=EXCLUDED.deadline,
              terms_hash=EXCLUDED.terms_hash,
              status=EXCLUDED.status,
              updated_at=NOW();
            """,
            (
                chain_id,
                int(args["dealId"]),
                args["sponsor"],
                args["athlete"],
                args["token"],
                int(args["amount"]),
                int(args["deadline"]),
                args["termsHash"].hex() if hasattr(args["termsHash"], "hex") else str(args["termsHash"]),
                "FUNDED",
            ),
        )
    elif event_name == "DealDelivered":
        cur.execute(
            """
            UPDATE deals_current SET evidence_hash=%s, delivered_at=%s, status=%s, updated_at=NOW()
            WHERE chain_id=%s AND deal_id=%s;
            """,
            (
                args["evidenceHash"].hex() if hasattr(args["evidenceHash"], "hex") else str(args["evidenceHash"]),
                int(args["deliveredAt"]),
                "DELIVERED",
                chain_id,
                int(args["dealId"]),
            ),
        )
    elif event_name == "DealSettled":
        cur.execute(
            """
            UPDATE deals_current SET amount=0, status=%s, updated_at=NOW()
            WHERE chain_id=%s AND deal_id=%s;
            """,
            ("SETTLED", chain_id, int(args["dealId"])),
        )
    elif event_name == "DealRefunded":
        cur.execute(
            """
            UPDATE deals_current SET amount=0, status=%s, updated_at=NOW()
            WHERE chain_id=%s AND deal_id=%s;
            """,
            ("REFUNDED", chain_id, int(args["dealId"])),
        )
    elif event_name == "GrantCreated":
        cur.execute(
            """
            INSERT INTO grants_current(chain_id, grant_id, sponsor, beneficiary, token, amount, unlock_time, terms_hash)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (chain_id, grant_id) DO UPDATE SET updated_at=NOW();
            """,
            (
                chain_id,
                int(args["grantId"]),
                args["sponsor"],
                args["beneficiary"],
                args["token"],
                int(args["amount"]),
                int(args["unlockTime"]),
                args["termsHash"].hex() if hasattr(args["termsHash"], "hex") else str(args["termsHash"]),
            ),
        )
    elif event_name == "GrantAttested":
        cur.execute(
            """
            UPDATE grants_current SET attested=TRUE, attestation_hash=%s, updated_at=NOW()
            WHERE chain_id=%s AND grant_id=%s;
            """,
            (
                args["attestationHash"].hex() if hasattr(args["attestationHash"], "hex") else str(args["attestationHash"]),
                chain_id,
                int(args["grantId"]),
            ),
        )
    elif event_name == "GrantWithdrawn":
        cur.execute(
            """
            UPDATE grants_current SET withdrawn=TRUE, amount=0, updated_at=NOW()
            WHERE chain_id=%s AND grant_id=%s;
            """,
            (chain_id, int(args["grantId"])),
        )
    elif event_name == "GrantRefunded":
        cur.execute(
            """
            UPDATE grants_current SET refunded=TRUE, amount=0, updated_at=NOW()
            WHERE chain_id=%s AND grant_id=%s;
            """,
            (chain_id, int(args["grantId"])),
        )
    elif event_name == "PayoutExecuted":
        cur.execute(
            """
            INSERT INTO payouts_current(chain_id, payout_id, ref, payer, token, amount, split_id, executed_at)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (chain_id, payout_id) DO NOTHING;
            """,
            (
                chain_id,
                int(args["payoutId"]),
                args["ref"].hex() if hasattr(args["ref"], "hex") else str(args["ref"]),
                args["payer"],
                args["token"],
                int(args["amount"]),
                int(args["splitId"]),
                int(args["at"]),
            ),
        )
    elif event_name == "ReceiptMinted":
        cur.execute(
            """
            INSERT INTO receipts_current(chain_id, token_id, order_hash, buyer, seller, token, price, platform_fee, token_uri)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (chain_id, token_id) DO NOTHING;
            """,
            (
                chain_id,
                int(args["tokenId"]),
                args["orderHash"].hex() if hasattr(args["orderHash"], "hex") else str(args["orderHash"]),
                args["buyer"],
                args["seller"],
                args["token"],
                int(args["price"]),
                int(args["platformFee"]),
                args["tokenURI"],
            ),
        )


def index_once(from_block: int, to_block: int, contracts: Dict[str, str]):
    rpc = os.environ["RPC_URL"]
    chain_id = int(os.environ.get("CHAIN_ID", "0"))
    w3 = Web3(Web3.HTTPProvider(rpc))

    db = connect_db()
    db.autocommit = False
    cur = db.cursor()

    for contract_name, addr in contracts.items():
        addr = Web3.to_checksum_address(addr)
        evmap = EVENT_ABIS[contract_name]
        logs = w3.eth.get_logs({"fromBlock": from_block, "toBlock": to_block, "address": addr})
        for log in logs:
            if not log["topics"]:
                continue
            sig = log["topics"][0].hex()
            if sig not in evmap:
                continue
            abi = evmap[sig]
            decoded = get_event_data(w3.codec, abi, log)
            args = decoded["args"]

            cur.execute(
                """
                INSERT INTO chain_events(chain_id, block_number, block_hash, tx_hash, tx_index, log_index,
                  contract_address, event_sig, event_name, topics, data, decoded)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (chain_id, tx_hash, log_index) DO NOTHING;
                """,
                (
                    chain_id,
                    int(log["blockNumber"]),
                    log["blockHash"].hex(),
                    log["transactionHash"].hex(),
                    int(log.get("transactionIndex", 0)),
                    int(log["logIndex"]),
                    addr,
                    sig,
                    abi["name"],
                    json.dumps([t.hex() for t in log["topics"]]),
                    json.dumps({"data": log["data"]}),
                    json.dumps({k: (v.hex() if hasattr(v, "hex") else str(v)) for k, v in dict(args).items()}),
                ),
            )

            upsert_current(cur, chain_id, abi["name"], args)

    db.commit()
    cur.close()
    db.close()


if __name__ == "__main__":
    # Addresses must be filled in .env
    contracts = {
        "DealEngine": os.environ["DEAL_ENGINE_ADDRESS"],
        "DeferredVault": os.environ["VAULT_ADDRESS"],
        "PayoutRouter": os.environ["ROUTER_ADDRESS"],
        "ReceiptNFT": os.environ["RECEIPT_NFT_ADDRESS"],
    }
    fb = int(os.environ.get("FROM_BLOCK", "0"))
    tb_raw = os.environ.get("TO_BLOCK", "latest")
    if tb_raw == "latest":
        # resolved inside the node
        tb = "latest"
    else:
        tb = int(tb_raw)
    # web3 accepts "latest" for toBlock
    index_once(fb, tb, contracts)
