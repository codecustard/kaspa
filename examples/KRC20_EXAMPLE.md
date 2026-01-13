# KRC20 Example

This example demonstrates how to create and manage KRC20 tokens on Kaspa using the commit-reveal pattern.

## Quick Start

### 1. Build the example

```bash
# From the root of the kaspa repository
mops test  # Ensure everything compiles
```

### 2. Deploy to local replica

Create a `dfx.json` in the root with:

```json
{
  "canisters": {
    "krc20_example": {
      "main": "examples/krc20_example.mo",
      "type": "motoko"
    }
  }
}
```

Then:

```bash
dfx start --background
dfx deploy krc20_example
```

### 3. Get your Kaspa address

```bash
dfx canister call krc20_example getAddress
```

### 4. Fund your address

Send testnet KAS to the address from step 3. You'll need:
- **1000 KAS** for deploying a token
- **1 KAS** for minting
- Network fees for other operations

## Usage Examples

### Deploy a Token

```bash
# Build the deploy commit transaction
dfx canister call krc20_example buildDeployCommit '(
  "MYTOKEN",              // ticker (4-6 letters)
  "21000000000000000",    // max supply with decimals
  "100000000000",         // mint limit with decimals
  opt 8,                  // decimals (optional)
  "kaspa:qz..."           // your address
)'
```

**Response includes:**
- `operation_json` - The KRC20 operation data
- `commit_tx` - Transaction to sign and broadcast
- `redeem_script_hex` - Save this for the reveal!
- `instructions` - What to do next

**Next steps:**
1. Sign and broadcast the `commit_tx` using the wallet
2. Wait for confirmation
3. Store the redeem script: `dfx canister call krc20_example storePendingReveal '("commit_tx_id", "redeem_script_hex")'`
4. Build and broadcast the reveal transaction

### Mint Tokens

```bash
dfx canister call krc20_example buildMintCommit '(
  "MYTOKEN",
  opt "kaspa:qz...",  // optional recipient
  "kaspa:qz..."       // funding address
)'
```

### Transfer Tokens

```bash
dfx canister call krc20_example buildTransferCommit '(
  "MYTOKEN",
  "50000000000",      // amount with decimals
  "kaspa:qz..."       // recipient
)'
```

### Burn Tokens

```bash
dfx canister call krc20_example buildBurnCommit '(
  "MYTOKEN",
  "10000000000"       // amount with decimals
)'
```

### List Tokens for Sale

```bash
dfx canister call krc20_example formatListOperation '(
  "MYTOKEN",
  "100000000000"      // amount
)'
```

### Buy Listed Tokens

```bash
dfx canister call krc20_example formatSendOperation '("MYTOKEN")'
```

## Helper Functions

### Check pending reveals

```bash
dfx canister call krc20_example getPendingReveals
```

### Get redeem script for a commit

```bash
dfx canister call krc20_example getRedeemScript '("commit_tx_id")'
```

### Estimate fees

```bash
dfx canister call krc20_example estimateFees '("{\"p\":\"krc-20\",\"op\":\"deploy\",...}")'
```

### Clear pending reveal (after broadcasting)

```bash
dfx canister call krc20_example clearPendingReveal '("commit_tx_id")'
```

## Understanding Commit-Reveal

Every KRC20 operation requires **two transactions**:

### 1. Commit Transaction
- Creates a P2SH output
- Commits to the operation data via BLAKE2B hash
- Requires appropriate fee (1000 KAS for deploy, 1 KAS for mint)

### 2. Reveal Transaction
- Spends the P2SH output
- Provides the redeem script (pubkey + signature + data envelope)
- Reveals the operation to Kasplex indexer

**Why?** This prevents frontrunning and ensures atomic operations.

## Operation Fees

| Operation | Commit Fee | Notes |
|-----------|-----------|-------|
| Deploy | 1,000 KAS | One-time deployment |
| Mint | 1 KAS | Per mint operation |
| Transfer | Network fee | No KRC20 fee |
| Burn | Network fee | No KRC20 fee |
| List | Network fee | Trading operation |
| Send | Network fee | Trading operation |

## Integration Example

Here's how to use this in your own canister:

```motoko
import KRC20Types "mo:kaspa/krc20/types";
import KRC20Operations "mo:kaspa/krc20/operations";
import KRC20Builder "mo:kaspa/krc20/builder";

// 1. Format operation
let deploy_params : KRC20Types.DeployMintParams = {
    tick = "MYTOKEN";
    max = "1000000000000000";
    lim = "10000000000";
    to = ?my_address;
    dec = ?8;
    pre = null;
};

let operation_json = KRC20Operations.formatDeployMint(deploy_params);

// 2. Build commit transaction
let commit_result = KRC20Builder.buildCommit(
    pubkey,
    operation_json,
    utxo,
    10000,  // commit amount
    100000000000,  // 1000 KAS fee
    change_address,
    true  // use ECDSA
);

// 3. Sign, broadcast, wait for confirmation, then reveal
```

## Production Considerations

### State Management

The example stores pending reveals in stable storage:
```motoko
private stable var pendingReveals : [(Text, [Nat8])] = [];
```

This allows:
- Resume after canister upgrades
- Track multiple concurrent operations
- Ensure reveals aren't lost

### Error Handling

In production, add:
- Retry logic for failed broadcasts
- Confirmation waiting before reveal
- Timeout handling for pending reveals
- Validation of operation parameters

### Security

- Verify ticker availability before deploy
- Check balances before operations
- Validate addresses and amounts
- Monitor for duplicate operations

## Verification

After operations complete:
1. Check transactions on [Kaspa Explorer](https://explorer.kaspa.org)
2. Verify tokens on [Kasplex.com](https://kasplex.com)
3. Query Kasplex API for balances

## Next Steps

- Add automatic reveal after commit confirmation
- Integrate Kasplex API for balance queries
- Build a frontend UI
- Add multi-signature support
- Implement batch operations

## Resources

- [KRC20 Specification](https://docs-kasplex.gitbook.io/krc20/)
- [Kaspa Documentation](https://kaspa.org)
- [Kasplex Platform](https://kasplex.com)
