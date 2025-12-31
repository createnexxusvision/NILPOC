# Texas HS Deferred NIL Vault (UIL Demo) — NextPlay Nexus

This repo contains a working Proof-of-Concept (POC) smart contract + demo app for **deferred NIL earnings** for Texas high school student-athletes under UIL-style constraints.

## Problem
Texas high school athletes may be able to **sign NIL agreements**, but in many UIL-governed scenarios the **receipt of funds** can create eligibility, recruiting, or compliance issues.

Today, deferred earnings are handled informally:
- money “promised later”
- delayed payments
- disputes between families, brands, and schools
- eligibility risk due to inconsistent enforcement

## Solution (What this POC does)
A **Deferred NIL Vault** that:
- allows a sponsor/brand to deposit funds upfront (escrow)
- records deal terms as a hash (IPFS CID or keccak256)
- prevents withdrawals until:
  - a minimum timestamp (unlockTime) is reached AND/OR
  - an authorized verifier (e.g., UIL/school compliance role) approves payout
- provides an immutable audit trail of every state transition

This does **not** encode UIL law in Solidity.
It enforces conservative release conditions and supports off-chain compliance guidance.

---

## Core Roles
- **Sponsor**: creates and funds the deal
- **Athlete**: beneficiary; cannot access funds until conditions are met
- **Verifier (Demo = UIL Eligibility Verifier)**: authorized address that approves release once conditions are satisfied

---

## Smart Contract Overview

### Deal lifecycle
1. Sponsor calls `createDeal(...)` and deposits token funds into the vault.
2. Athlete can view the deal on-chain but cannot withdraw.
3. Verifier calls `approvePayout(dealId)` when eligibility conditions are satisfied.
4. Athlete calls `withdraw(dealId)` to receive funds.

### Key functions
- `createDeal(athlete, token, amount, unlockTime, metadataHash)`
- `approvePayout(dealId)` (verifier-only)
- `withdraw(dealId)` (athlete-only; requires conditions)
- `refund(dealId)` (optional admin path if deal is voided)

### Events (audit trail)
- `DealCreated`
- `PayoutApproved`
- `Withdrawn`
- `Refunded`

---

## Why this matters (UIL-first value)
- **Eligibility protection**: prevents early payment while allowing agreements to be signed
- **Transparency**: schools/families/sponsors can verify what happened without trusting a spreadsheet
- **Reduced disputes**: money is committed up front, terms are referenced immutably
- **Scalable**: can be standardized across districts and expanded beyond Texas

---

## Demo App
A minimal DApp with three pages:
- `/sponsor` – create & fund a deal
- `/verifier` – approve payout
- `/athlete` – view locked funds and withdraw when eligible

## Local Dev (Foundry)

### Install
- Foundry: https://book.getfoundry.sh/

### Commands
```bash
forge install
forge test
