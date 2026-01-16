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

## Minting Tokens

After deploying your token, you can mint new tokens up to the mint limit (`lim` parameter).

### Quick Start: Mint to Yourself

```bash
# Mint tokens to the canister's address (default)
dfx canister call krc20_example mintTokenWithBroadcast '("ICWIN", null)'
```

This will:
1. Create a commit transaction with 1 KAS fee
2. Broadcast it to the network
3. Store the redeem script for reveal
4. Return the commit TX ID

### Wait and Reveal

Wait ~10 seconds for commit confirmation, then reveal:

```bash
dfx canister call krc20_example revealOperation '("COMMIT_TX_ID", "YOUR_KASPA_ADDRESS")'
```

### Mint to Another Address

```bash
# Mint tokens to a specific recipient
dfx canister call krc20_example mintTokenWithBroadcast '("ICWIN", opt "kaspatest:recipient_address_here")'
```

### Check Token Status

Before minting, verify the token is still mintable:

```bash
# Get token info (max supply, current minted, mint limit, etc.)
dfx canister call krc20_example getTokenInfo '("ICWIN")'

# Check mint status
dfx canister call krc20_example checkMintStatus '("ICWIN")'

# Check specific token balance
dfx canister call krc20_example getKRC20TokenBalance '("kaspatest:YOUR_ADDRESS", "ICWIN")'

# OR check all tokens you hold
dfx canister call krc20_example getKRC20TokenList '("kaspatest:YOUR_ADDRESS")'
```

### Verify Mint on Explorer

After reveal, check your mint operation:

```bash
# Get operation status (look for "opAccept": "1")
dfx canister call krc20_example getOperationStatus '("REVEAL_TX_ID")'
```

Or visit:
- **Operation status:** https://tn10api.kasplex.org/v1/krc20/op/REVEAL_TX_ID
- **Token info:** https://tn10api.kasplex.org/v1/krc20/token/ICWIN
- **Your token balance:** https://tn10api.kasplex.org/v1/krc20/address/kaspatest:YOUR_ADDRESS/token/ICWIN
- **All your tokens:** https://tn10api.kasplex.org/v1/krc20/address/kaspatest:YOUR_ADDRESS/tokenlist

### Mint Limits

Each mint operation mints the `lim` amount specified during deployment:
- **ICWIN** example: `lim = "100000000000"` (1,000 ICWIN with 8 decimals)
- You can mint multiple times until reaching `max` supply
- Fee: 1 KAS per mint operation

### Complete Mint Example

```bash
# 1. Check if token is mintable
dfx canister call krc20_example getTokenInfo '("ICWIN")'

# 2. Mint tokens (commit transaction)
dfx canister call krc20_example mintTokenWithBroadcast '("ICWIN", null)'
# Output: (variant { ok = record { commit_tx_id = "abc123..."; ... }})

# 3. Wait 10 seconds...

# 4. Reveal the mint
dfx canister call krc20_example revealOperation '("abc123...", "kaspatest:YOUR_ADDRESS")'
# Output: (variant { ok = record { reveal_tx_id = "xyz789..."; ... }})

# 5. Check operation status
dfx canister call krc20_example getOperationStatus '("xyz789...")'
# Look for: "opAccept": "1"

# 6. Verify your balance
dfx canister call krc20_example getKRC20TokenBalance '("kaspatest:YOUR_ADDRESS", "ICWIN")'

# OR see all your tokens
dfx canister call krc20_example getKRC20TokenList '("kaspatest:YOUR_ADDRESS")'
```

## Helper Functions

### Check Token Balances

**Get balance for a specific token:**
```bash
dfx canister call krc20_example getKRC20TokenBalance '("kaspatest:YOUR_ADDRESS", "ICWIN")'
```

**Example response:**
```json
{
  "tick": "ICWIN",
  "balance": "100000000000",
  "locked": "0",
  "dec": "8"
}
```

**Get all tokens you hold:**
```bash
dfx canister call krc20_example getKRC20TokenList '("kaspatest:YOUR_ADDRESS")'
```

**Example response:**
```json
{
  "message": "successful",
  "result": [
    {
      "tick": "ICWIN",
      "balance": "100000000000",
      "locked": "0",
      "dec": "8"
    }
  ]
}
```

### Check Token Info

**Get token metadata (max supply, minted, etc.):**
```bash
dfx canister call krc20_example getTokenInfo '("ICWIN")'
```

### Check Operation Status

**Verify if your mint/transfer/burn succeeded:**
```bash
dfx canister call krc20_example getOperationStatus '("REVEAL_TX_ID")'
```

Look for `"opAccept": "1"` to confirm success! ✅

### Web API Endpoints

**Token information:**
```
https://tn10api.kasplex.org/v1/krc20/token/ICWIN
```

**Operation status:**
```
https://tn10api.kasplex.org/v1/krc20/op/REVEAL_TX_ID
```

**Your token balance (specific):**
```
https://tn10api.kasplex.org/v1/krc20/address/kaspatest:YOUR_ADDRESS/token/ICWIN
```

**All your tokens (list):**
```
https://tn10api.kasplex.org/v1/krc20/address/kaspatest:YOUR_ADDRESS/tokenlist
```

## Other Operations

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
