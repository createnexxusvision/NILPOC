-- NILPOC / NextPlay Nexus: Event-sourced indexing schema (Postgres)
-- Source of truth: on-chain logs decoded by the indexer.

-- 1) Raw logs (append-only)
CREATE TABLE IF NOT EXISTS chain_events (
  id BIGSERIAL PRIMARY KEY,
  chain_id INTEGER NOT NULL,
  block_number BIGINT NOT NULL,
  block_hash TEXT NOT NULL,
  tx_hash TEXT NOT NULL,
  tx_index INTEGER,
  log_index INTEGER NOT NULL,
  contract_address TEXT NOT NULL,
  event_sig TEXT NOT NULL,
  event_name TEXT NOT NULL,
  topics JSONB NOT NULL,
  data JSONB NOT NULL,
  decoded JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(chain_id, tx_hash, log_index)
);

-- 2) Deal current state (materialized by upserts from events)
CREATE TABLE IF NOT EXISTS deals_current (
  chain_id INTEGER NOT NULL,
  deal_id BIGINT NOT NULL,
  sponsor TEXT NOT NULL,
  athlete TEXT NOT NULL,
  token TEXT NOT NULL,
  amount NUMERIC(78,0) NOT NULL,
  deadline BIGINT NOT NULL,
  terms_hash TEXT NOT NULL,
  evidence_hash TEXT,
  delivered_at BIGINT,
  status TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(chain_id, deal_id)
);

CREATE TABLE IF NOT EXISTS grants_current (
  chain_id INTEGER NOT NULL,
  grant_id BIGINT NOT NULL,
  sponsor TEXT NOT NULL,
  beneficiary TEXT NOT NULL,
  token TEXT NOT NULL,
  amount NUMERIC(78,0) NOT NULL,
  unlock_time BIGINT NOT NULL,
  terms_hash TEXT NOT NULL,
  attested BOOLEAN NOT NULL DEFAULT FALSE,
  attestation_hash TEXT,
  withdrawn BOOLEAN NOT NULL DEFAULT FALSE,
  refunded BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(chain_id, grant_id)
);

CREATE TABLE IF NOT EXISTS payouts_current (
  chain_id INTEGER NOT NULL,
  payout_id BIGINT NOT NULL,
  ref TEXT NOT NULL,
  payer TEXT NOT NULL,
  token TEXT NOT NULL,
  amount NUMERIC(78,0) NOT NULL,
  split_id BIGINT NOT NULL,
  executed_at BIGINT NOT NULL,
  PRIMARY KEY(chain_id, payout_id)
);

CREATE TABLE IF NOT EXISTS receipts_current (
  chain_id INTEGER NOT NULL,
  token_id BIGINT NOT NULL,
  order_hash TEXT NOT NULL,
  buyer TEXT NOT NULL,
  seller TEXT NOT NULL,
  token TEXT NOT NULL,
  price NUMERIC(78,0) NOT NULL,
  platform_fee NUMERIC(78,0) NOT NULL,
  token_uri TEXT NOT NULL,
  minted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(chain_id, token_id)
);

-- Helpful indices
CREATE INDEX IF NOT EXISTS idx_chain_events_tx ON chain_events(chain_id, tx_hash);
CREATE INDEX IF NOT EXISTS idx_chain_events_name ON chain_events(chain_id, event_name);
CREATE INDEX IF NOT EXISTS idx_deals_party ON deals_current(sponsor, athlete);
