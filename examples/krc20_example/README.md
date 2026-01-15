# KRC20 Token Example - Deploy KRC20 tokens on Kaspa from ICP

This example demonstrates deploying KRC20 tokens on Kaspa using the commit-reveal pattern from an ICP canister. Successfully tested on Kaspa Testnet 10.

## Quick Start

### 1. Deploy the canister

```bash
dfx start --background
dfx deploy krc20_example
```

### 2. Get your canister's Kaspa testnet address

```bash
dfx canister call krc20_example getAddress
```

### 3. Fund your address

Get testnet KAS from the faucet (need ~2100+ KAS for deploy):

**Faucet:** https://faucet-tn10.kaspanet.io/

### 4. Deploy a token (commit transaction)

```bash
dfx canister call krc20_example deployTokenWithBroadcast '("MYTOKEN", "21000000000000000", "100000000000", opt 8, "YOUR_KASPA_ADDRESS")'
```

Parameters:
- `"MYTOKEN"` - Token ticker (4-6 characters)
- `"21000000000000000"` - Max supply (with decimals)
- `"100000000000"` - Mint limit per operation (with decimals)
- `opt 8` - Decimals (optional, default 8)
- `"YOUR_KASPA_ADDRESS"` - Your kaspatest: address

### 5. Wait and reveal

Wait ~10 seconds for commit to confirm, then reveal:

```bash
dfx canister call krc20_example revealOperation '("COMMIT_TX_ID", "YOUR_KASPA_ADDRESS")'
```

### 6. Check your token

- **Token info:** https://tn10api.kasplex.org/v1/krc20/token/MYTOKEN
- **Operation status:** https://tn10api.kasplex.org/v1/krc20/op/REVEAL_TX_ID
- Look for `"opAccept": "1"` to confirm success

## Fee Structure

| Operation | Commit Fee | Reveal Fee | Total |
|-----------|-----------|------------|-------|
| Deploy | 1,000 KAS | 1,000 KAS | ~2,000 KAS |
| Mint | 1 KAS | Network fee | ~1 KAS |
| Transfer | Network fee | Network fee | Minimal |

## Working Example

Successfully deployed **ICWIN** token on Kaspa Testnet 10:

- **Commit TX:** `bb376669116b98f3c6d625aad054a7552c7c06eb40eb9907f90ddc2d622b3f6b`
- **Reveal TX:** `f418464bdd8001655b320f3605f007d4fa2a5297d3dfe9f6a96e0155c60c679f`
- **Token API:** https://tn10api.kasplex.org/v1/krc20/token/ICWIN

## How It Works

### Commit-Reveal Pattern

Every KRC20 operation requires **two transactions**:

1. **Commit Transaction**
   - Creates a P2SH output with BLAKE2B hash of redeem script
   - Locks funds that will be spent in reveal
   - Pays commit fee (1000 KAS for deploy)

2. **Reveal Transaction**
   - Spends the P2SH output
   - Provides the redeem script containing the KRC20 data
   - Pays reveal fee (burned as protocol fee)

### Data Envelope Format

```
<pubkey>
OP_CHECKSIG_ECDSA
OP_FALSE
OP_IF
  OP_PUSH "kasplex"
  OP_1                    // Metadata marker
  OP_0                    // Empty metadata
  OP_0                    // Content marker
  OP_PUSH <json_data>     // KRC20 JSON
OP_ENDIF
```

### Threshold ECDSA

Uses ICP's threshold ECDSA for signing - no private keys stored in the canister!

## Other Operations

### Mint Tokens

```bash
dfx canister call krc20_example buildMintCommit '("MYTOKEN", opt "recipient_address", "funding_address")'
```

### Transfer Tokens

```bash
dfx canister call krc20_example buildTransferCommit '("MYTOKEN", "50000000000", "recipient_address")'
```

### Burn Tokens

```bash
dfx canister call krc20_example buildBurnCommit '("MYTOKEN", "10000000000")'
```

## Helper Functions

```bash
# Check balance
dfx canister call krc20_example getBalance '("kaspatest:...")'

# Get pending reveals
dfx canister call krc20_example getPendingReveals

# Consolidate UTXOs
dfx canister call krc20_example consolidateUTXOs '("kaspatest:...")'
```

## Resources

- [KRC20 Specification](https://docs-kasplex.gitbook.io/krc20/)
- [Kasplex API Docs](https://tn10api.kasplex.org/v1)
- [Kaspa Testnet Explorer](https://explorer-tn10.kaspa.org)
- [Testnet Faucet](https://faucet-tn10.kaspanet.io/)
