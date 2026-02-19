# NILPOC - Name, Image & Likeness Protocol

A Foundry-based suite of smart contracts for athlete NIL (Name, Image, Likeness)
sponsorship deals, timelocked grants, payout splitting, and NFT receipt issuance.

## Contracts

| Contract | Description |
|---|---|
| `DealEngine` | Escrow + dispute resolution for bilateral NIL deals |
| `DeferredVault` | Attested, timelocked grant escrow |
| `PayoutRouter` | Deterministic ERC20/ETH split router |
| `ReceiptNFT` | ERC-721 receipt minted on each settlement |
| `AttestationGate` | Shared ORACLE / JUDGE / OPERATOR role base |
| `ProtocolPausable` | Shared pause controls |
| `SportsRadarVerifier` | Chainlink Functions oracle adapter |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) >= 1.5
- A funded deployer wallet (ETH for gas)
- RPC endpoints and block-explorer API keys (see `.env`)

## Quick Start (local Anvil)

```shell
# 1. Start a local node
anvil

# 2. Fill environment file (edit .env with your keys)

# 3. Deploy
forge script script/DeployCore.s.sol --rpc-url localhost --broadcast

# 4. Grant roles (optional -- admin already holds all roles after deploy)
forge script script/GrantRoles.s.sol --rpc-url localhost --broadcast
```

## Testnet Deployment

```shell
# Fill SEPOLIA_RPC_URL, ETHERSCAN_API_KEY, etc. in .env first, then:

forge script script/DeployTestnet.s.sol \
    --rpc-url sepolia \
    --broadcast \
    --verify

# Base Sepolia
forge script script/DeployTestnet.s.sol \
    --rpc-url base_sepolia \
    --broadcast \
    --verify
```

## Build & Test

```shell
forge build
forge test
forge test --match-contract Invariant   # invariant tests only
forge coverage                          # coverage report
```

## Other Commands

```shell
forge fmt            # format Solidity files
forge snapshot       # gas snapshots
cast <subcommand>    # interact with deployed contracts
anvil                # local node
```

## Environment Variables

See `.env` for a fully documented template. Key variables:

| Variable | Purpose |
|---|---|
| `DEPLOYER_PRIVATE_KEY` | Deployer / admin wallet private key |
| `FEE_RECIPIENT` | Address that receives the platform fee |
| `PLATFORM_FEE_BPS` | Platform fee in basis points (200 = 2%) |
| `SEPOLIA_RPC_URL` | Alchemy / Infura Sepolia endpoint |
| `ETHERSCAN_API_KEY` | For contract verification on Etherscan |
| `USDC_SEPOLIA` | USDC token address on Sepolia |

## Architecture Notes

- All core contracts inherit `AttestationGate` (OpenZeppelin `AccessControl` base).
- `DEFAULT_ADMIN_ROLE` is held by the deployer. Roles can be transferred or renounced
  after deployment via `GrantRoles.s.sol`.
- `PayoutRouter` enforces that split recipients cannot be the router itself,
  preventing permanent ERC-20 lockup.
- `via_ir = true` is required in `foundry.toml` to avoid stack-too-deep in
  `PayoutRouter`.

## Foundry Documentation

https://book.getfoundry.sh/
