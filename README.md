# Kaspa Motoko Package and Canister

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/kaspa)](https://mops.one/kaspa)

Welcome to the `kaspa` project, which provides a Motoko package (`kaspa-mo`) and a canister implementation for interacting with the Kaspa blockchain on the Internet Computer (IC). The `kaspa-mo` package includes modules for generating and decoding Kaspa addresses, calculating signature hashes, building and serializing transactions, and defining common blockchain data structures. The `kaspa_test_tecdsa.mo` canister demonstrates how to use the package to fetch UTXOs, generate addresses, and sign ECDSA-based transactions.

## Table of Contents
- [Installation](#installation)
  - [For Library Usage (Mops)](#for-library-usage-mops)
  - [For Canister Development (DFX)](#for-canister-development-dfx)
- [Dependencies](#dependencies)
- [Running the Canister Locally](#running-the-canister-locally)
  - [Note on Frontend Environment Variables](#note-on-frontend-environment-variables)
- [Examples](#examples)
  - [Internet Identity + Kaspa Wallet](#internet-identity--kaspa-wallet)
  - [KRC20 Token Deployment](#krc20-token-deployment)
  - [Basic Wallet Broadcasting](#basic-wallet-broadcasting)
- [Usage](#usage)
  - [Example: Generating a Kaspa Address](#example-generating-a-kaspa-address)
  - [Example: Calculating a Schnorr Sighash](#example-calculating-a-schnorr-sighash)
  - [Example: Building a Transaction](#example-building-a-transaction)
- [Example Canister](#example-canister)
  - [Key Functions](#key-functions)
  - [Dependencies](#dependencies-1)
  - [Notes](#notes)
- [Modules](#modules)
  - [KRC20 Modules](#krc20-modules-srckrc20)
  - [script_builder.mo](#script_buildermo)
  - [opcodes.mo](#opcodesmo)
  - [address.mo](#addressmo)
  - [sighash.mo](#sighashmo)
  - [transaction.mo](#transactionmo)
  - [types.mo](#typesmo)
- [Contributing](#contributing)
- [License](#license)
- [Additional Resources](#additional-resources)

## Installation

### For Library Usage (Mops)
To use the `kaspa-mo` package in your Motoko project:

1. **Install Mops** (if not already installed):
   ```bash
   npm i -g ic-mops
   ```

2. **Add the Kaspa package** to your project:
   ```bash
   mops add kaspa
   ```

3. **For DFX projects**:
   Add the following to your `dfx.json` under `defaults.build.packtool`:
   ```json
   "mops sources"
   ```

### For Canister Development (DFX)
To work with the `kaspa` canister project locally:

1. **Install DFX** (if not already installed):
   Follow the [SDK Developer Tools](https://internetcomputer.org/docs/current/developer-docs/setup/install) guide.

2. **Clone the repository**:
   ```bash
   git clone https://github.com/codecustard/kaspa
   cd kaspa
   ```

3. **Install dependencies**:
   ```bash
   mops install
   ```

## Dependencies

The `kaspa-mo` package and `kaspa` canister depend on:
- `mo:blake2b`: For Blake2b-256 hashing in `sighash.mo`.
- `mo:sha2`: For SHA-256 hashing in `sighash.mo`.
- `mo:json`: For parsing JSON responses in `kaspa_test_tecdsa.mo`.

This package can be added via [mops.one](https://mops.one/kaspa):
```bash
mops add kaspa
```

The canister also uses the IC management canister (`ic:aaaaa-aa`) for ECDSA operations, requiring sufficient cycles and permissions.

## Running the Canister Locally

To test the `kaspa` canister locally:

1. **Start the replica**:
   ```bash
   dfx start --background
   ```

2. **Deploy the canister**:
   ```bash
   dfx deploy
   ```
   This deploys the `kaspa_test_tecdsa.mo` canister and generates its Candid interface. The canister will be available at `http://localhost:4943?canisterId=<asset_canister_id>`.

3. **Generate the Candid interface** (if backend changes are made):
   ```bash
   npm run generate
   ```

## Examples

This repository includes several comprehensive examples demonstrating different use cases for the Kaspa Motoko package:

### Internet Identity + Kaspa Wallet

🌟 **Featured Example**: A Kaspa wallet with Internet Identity authentication.

**Location**: [`examples/ii_kaspa_wallet/`](examples/ii_kaspa_wallet/)

**Features**:
- 🔐 Internet Identity passwordless authentication
- 🎨 Modern React frontend with shadcn-inspired dark theme
- 💸 Complete send/receive functionality
- 🔒 Secure SHA256-based derivation paths
- 👤 Per-user wallet sessions with timeout management
- ⚡ Real-time balance checking and transaction status

**Quick Start**:
```bash
cd examples/ii_kaspa_wallet
npm install
dfx start --background
dfx deps deploy internet_identity
dfx deploy
```

**[📖 Full Documentation](examples/ii_kaspa_wallet/README.md)**

### KRC20 Token Deployment

**Location**: [`examples/krc20_example/`](examples/krc20_example/)

Deploy KRC20 tokens on Kaspa using the commit-reveal pattern from ICP. Successfully tested on Kaspa Testnet 10.

**Features**:
- 🪙 Deploy new KRC20 tokens with custom ticker, supply, and mint limits
- 🔄 Commit-reveal pattern for protocol compliance
- 🔐 Threshold ECDSA signing (no private keys in canister)
- ✅ Verified working on Kaspa Testnet 10

**Quick Start**:
```bash
dfx start --background
dfx deploy krc20_example

# Get your testnet address and fund it from faucet
dfx canister call krc20_example getAddress
# Fund with ~2100 KAS from: https://faucet-tn10.kaspanet.io/

# Deploy a token
dfx canister call krc20_example deployTokenWithBroadcast '("MYTOKEN", "21000000000000000", "100000000000", opt 8, "YOUR_KASPA_ADDRESS")'
```

**[📖 Full Documentation](examples/krc20_example/README.md)**

### Basic Wallet Broadcasting

**Location**: [`examples/wallet_broadcast_example.mo`](examples/wallet_broadcast_example.mo)

A simple example demonstrating the core wallet functionality:
- Address generation
- Transaction building and signing
- Broadcasting to Kaspa network
- Basic error handling

Perfect for understanding the fundamental concepts before building more complex applications.

## Usage

Import the `kaspa-mo` modules in your Motoko code:

```motoko
import Address "mo:kaspa/address";
import Wallet "mo:kaspa/wallet";
import Errors "mo:kaspa/errors";
import Validation "mo:kaspa/validation";
```

### Example: Generating a Kaspa Address
Generate a Kaspa address from a public key (Schnorr or ECDSA):

```motoko
import Address "mo:kaspa/address";
import Result "mo:base/Result";
import Blob "mo:base/Blob";

actor {
  public func generateAddress(pubkeyHex : Text, addrType : Nat) : async Text {
    switch (Address.arrayFromHex(pubkeyHex)) {
      case (#ok(pubkey)) {
        switch (Address.generateAddress(Blob.fromArray(pubkey), addrType)) {
          case (#ok(info)) { info.address };
          case (#err(_)) { "" };
        }
      };
      case (#err(_)) { "" };
    }
  };
};
```

Example call:
- Schnorr (32-byte pubkey): `generateAddress("a1b2c3d4e5f6...64chars", Address.SCHNORR)` → `kaspa:qypq...`
- ECDSA (33-byte pubkey): `generateAddress("02a1b2c3d4e5...66chars", Address.ECDSA)` → `kaspa:qypq...`

### Example: Calculating a Schnorr Sighash
Calculate a signature hash for a Kaspa transaction input:

```motoko
import Sighash "mo:codecustard/kaspa/src/sighash";
import Types "mo:codecustard/kaspa/src/types";

actor {
  public func calculateSighash(tx : Types.KaspaTransaction, inputIndex : Nat, utxo : Types.UTXO) : async ?Text {
    let reusedValues : Sighash.SighashReusedValues = {
      var previousOutputsHash = null;
      var sequencesHash = null;
      var sigOpCountsHash = null;
      var outputsHash = null;
      var payloadHash = null;
    };
    switch (Sighash.calculate_sighash_schnorr(tx, inputIndex, utxo, Sighash.SigHashAll, reusedValues)) {
      case (?hash) { ?Sighash.hex_from_array(hash) };
      case (null) { null };
    }
  };
};
```

### Example: Building a Transaction
Build a Kaspa transaction with one input and one or two outputs:

```motoko
import Transaction "mo:codecustard/kaspa/src/transaction";
import Types "mo:codecustard/kaspa/src/types";

actor {
  public func createTransaction(
    utxo : Types.UTXO,
    recipientScript : Text,
    amount : Nat64,
    fee : Nat64,
    changeScript : Text
  ) : async Text {
    let tx = Transaction.build_transaction(utxo, recipientScript, amount, fee, changeScript);
    Transaction.serialize_transaction(tx)
  };
};
```

Example call:
```motoko
let utxo : Types.UTXO = {
  transactionId = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6";
  index = 0;
  amount = 2000000;
  scriptVersion = 0;
  scriptPublicKey = "20a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3ac";
  address = "kaspa:qypq...";
};
let json = await createTransaction(utxo, "20d4e5f6a1b2c3...ac", 1000000, 1000, "20a1b2c3d4e5f6...ac");
// Returns JSON: "{\"transaction\":{\"version\":0,\"inputs\":[...],\"outputs\":[...],...}}"
```

## Example Canister

The `kaspa_test_tecdsa.mo` canister demonstrates how to use the `kaspa-mo` package to interact with the Kaspa blockchain. It fetches UTXOs from the Kaspa mainnet, generates ECDSA-based addresses, builds transactions, and signs them using the Internet Computer’s management canister (`aaaaa-aa`) for ECDSA operations. The canister is configured for ECDSA transactions and uses the `dfx_test_key` for signing.

### Key Functions
- `get_kaspa_address(derivation_path : ?Text) : async Text`
  - Retrieves an ECDSA public key from the IC management canister and converts it to a Kaspa address.
  - Supports optional derivation paths (e.g., `"44'/111111'/0'/0/0"`).
  - Example:
    ```motoko
    let addr = await get_kaspa_address(?"44'/111111'/0'/0/0");
    // Returns: "kaspa:qypq..."
    ```

- `send_kas(recipient_address : Text, amount : Nat64) : async ?Text`
  - Builds, signs, and serializes a transaction to send `amount` sompi to `recipient_address`.
  - Fetches UTXOs from the Kaspa mainnet, selects one with sufficient funds, and creates a transaction with a recipient output and optional change output.
  - Signs the transaction using ECDSA with `SigHashAll`.
  - Returns the serialized transaction JSON or `null` on failure (e.g., invalid address, insufficient funds).
  - Example:
    ```motoko
    let result = await send_kas("kaspa:qypq...", 1000000);
    switch (result) {
      case (?json) { /* JSON-serialized transaction */ };
      case (null) { /* Failed to create transaction */ };
    };
    ```

### Dependencies
- Requires `mo:json` for parsing UTXO responses from the Kaspa API.
- Uses the IC management canister (`ic:aaaaa-aa`) for ECDSA public key retrieval and signing.

### Notes
- The canister requires access to the `dfx_test_key` for ECDSA operations. Ensure the canister has sufficient cycles (e.g., 30B for signing, 230B for HTTP requests) and permissions for `aaaaa-aa`.
- The `submit_transaction` function is a placeholder (commented out). To submit transactions, implement an HTTP request to the Kaspa API (e.g., `https://api.kaspa.org/transactions`).
- The canister fetches UTXOs from `api.kaspa.org`. Handle potential API rate limits or errors (e.g., via retry logic).

## Modules

### KRC20 Modules (`src/krc20/`)

The KRC20 modules provide full support for deploying and managing KRC20 tokens on Kaspa.

#### `krc20/types.mo`
Defines data structures for KRC20 operations:
- `DeployMintParams` - Fair launch token deployment (anyone can mint)
- `DeployIssueParams` - Controlled token deployment (owner issues)
- `MintParams`, `TransferMintParams`, `BurnMintParams` - Token operations
- `ListParams`, `SendParams` - Trading operations

#### `krc20/operations.mo`
JSON formatters for KRC20 protocol messages:
```motoko
import KRC20Ops "mo:kaspa/krc20/operations";

// Deploy a fair-launch token
let json = KRC20Ops.formatDeployMint({
  tick = "MYTOKEN";
  max = "21000000000000000";
  lim = "100000000000";
  to = null; dec = null; pre = null;
});
// Returns: {"p":"krc-20","op":"deploy","tick":"MYTOKEN","max":"21000000000000000","lim":"100000000000"}
```

#### `krc20/builder.mo`
High-level transaction builders for commit-reveal workflow:
- `buildCommitTransaction()` - Creates P2SH commit output
- `buildRevealTransaction()` - Spends commit with redeem script
- Fee constants: `DEPLOY_FEE` (1000 KAS), `MINT_FEE` (1 KAS)

### `script_builder.mo`
Low-level script construction for P2SH and data envelopes:
- `buildDataEnvelope()` - Creates Kasplex data envelope
- `buildRedeemScript()` - Constructs redeem script with pubkey and envelope
- `buildP2SHScriptPubKey()` - Creates P2SH locking script

### `opcodes.mo`
Kaspa opcode constants including `OP_CHECKSIG_ECDSA`, `OP_BLAKE2B`, `OP_IF/ENDIF`, etc.

### `address.mo`
Provides functions for encoding and decoding Kaspa addresses using the CashAddr format, converting public keys to script public keys, and handling hex conversions.

#### Constants
- `SCHNORR : Nat = 0`: Represents Schnorr-based addresses (32-byte payload).
- `ECDSA : Nat = 1`: Represents ECDSA-based addresses (33-byte payload).
- `P2SH : Nat = 2`: Represents Pay-to-Script-Hash addresses (32-byte payload).
- `SCHNORR_PAYLOAD_LEN : Nat = 32`: Expected length for Schnorr/P2SH payloads.
- `ECDSA_PAYLOAD_LEN : Nat = 33`: Expected length for ECDSA payloads.

#### Public Functions
- `address_from_pubkey(pubkey : Blob, addr_type : Nat) : Text`
  - Generates a Kaspa address (`kaspa:...`) from a public key blob for the specified address type (`SCHNORR`, `ECDSA`, or `P2SH`).
  - Returns an empty string if the public key length is invalid or encoding fails.
  - Example:
    ```motoko
    let pubkey = Blob.fromArray([0xa1, 0xb2, ...]); // 32 or 33 bytes
    let address = Address.address_from_pubkey(pubkey, Address.SCHNORR);
    // Returns: "kaspa:qypq..."
    ```

- `pubkey_to_script(pubkey : [Nat8], addr_type : Nat) : Text`
  - Converts a public key to a hex-encoded script public key (e.g., for P2PK Schnorr or ECDSA).
  - Schnorr: `OP_DATA_32 <pubkey> OP_CHECKSIG`.
  - ECDSA: `OP_DATA_33 <pubkey> OP_CHECKSIG`.
  - Returns an empty string if the address type or public key length is invalid.
  - Example:
    ```motoko
    let pubkey = Address.array_from_hex("a1b2c3...");
    let script = Address.pubkey_to_script(pubkey, Address.SCHNORR);
    // Returns: "20<32-byte-pubkey>ac"
    ```

- `decode_address(address : Text) : ?(Nat, [Nat8])`
  - Decodes a Kaspa address (`kaspa:...`) into its address type (`SCHNORR`, `ECDSA`, or `P2SH`) and payload bytes.
  - Validates the address prefix, charset, checksum, and payload length.
  - Returns `null` if the address is invalid.
  - Example:
    ```motoko
    switch (Address.decode_address("kaspa:qypq...")) {
      case (? (addrType, payload)) {
        // addrType: 0 (SCHNORR), payload: [Nat8] of length 32
      };
      case (null) { /* Invalid address */ };
    };
    ```

- `hex_from_array(bytes : [Nat8]) : Text`
  - Converts a byte array to a lowercase hex string.
  - Example: `[0xa1, 0xb2]` → `"a1b2"`.

- `array_from_hex(hex : Text) : [Nat8]`
  - Converts a hex string (lowercase or uppercase) to a byte array.
  - Returns an empty array if the hex string is invalid.
  - Example: `"a1b2"` → `[0xa1, 0xb2]`.

### `sighash.mo`
Provides functions for calculating signature hashes (sighash) for Kaspa transactions, supporting both Schnorr and ECDSA signatures. It includes utilities for handling transaction data and optimizing hash calculations with reused values.

#### Types
- `SigHashType : Nat8`: Represents the sighash type for transaction signing.
- `SighashReusedValues`: A record to cache precomputed hashes for efficiency:
  ```motoko
  {
    var previousOutputsHash: ?[Nat8];
    var sequencesHash: ?[Nat8];
    var sigOpCountsHash: ?[Nat8];
    var outputsHash: ?[Nat8];
    var payloadHash: ?[Nat8];
  }
  ```

#### Constants
- `SigHashAll : Nat8 = 0x01`: Signs all inputs and outputs.
- `SigHashNone : Nat8 = 0x02`: Signs all inputs, no outputs.
- `SigHashSingle : Nat8 = 0x04`: Signs all inputs and one output.
- `SigHashAnyOneCanPay : Nat8 = 0x80`: Signs only the current input.
- `SigHashAll_AnyOneCanPay : Nat8 = 0x81`: Combines `SigHashAll` with `AnyOneCanPay`.
- `SigHashNone_AnyOneCanPay : Nat8 = 0x82`: Combines `SigHashNone` with `AnyOneCanPay`.
- `SigHashSingle_AnyOneCanPay : Nat8 = 0x84`: Combines `SigHashSingle` with `AnyOneCanPay`.
- `SigHashMask : Nat8 = 0x07`: Mask for extracting the base sighash type.

#### Public Functions
- `is_standard_sighash_type(hashType : SigHashType) : Bool`
  - Checks if the provided sighash type is standard (e.g., `SigHashAll`, `SigHashNone`).
  - Example:
    ```motoko
    let isValid = Sighash.is_standard_sighash_type(Sighash.SigHashAll); // true
    ```

- `calculate_sighash_schnorr(tx : Types.KaspaTransaction, input_index : Nat, utxo : Types.UTXO, hashType : SigHashType, reusedValues : SighashReusedValues) : ?[Nat8]`
  - Calculates the Schnorr sighash for a transaction input, using Blake2b-256 with a domain separator.
  - Returns `null` if the sighash type is invalid or input index is out of bounds.
  - Example:
    ```motoko
    let reusedValues : Sighash.SighashReusedValues = { var previousOutputsHash = null; ... };
    switch (Sighash.calculate_sighash_schnorr(tx, 0, utxo, Sighash.SigHashAll, reusedValues)) {
      case (?hash) { Sighash.hex_from_array(hash) }; // Hex-encoded sighash
      case (null) { /* Invalid input */ };
    };
    ```

- `calculate_sighash_ecdsa(tx : Types.KaspaTransaction, input_index : Nat, utxo : Types.UTXO, hashType : SigHashType, reusedValues : SighashReusedValues) : ?[Nat8]`
  - Calculates the ECDSA sighash by hashing the Schnorr sighash with SHA-256 and an ECDSA domain separator.
  - Returns `null` if the Schnorr sighash calculation fails.
  - Example:
    ```motoko
    let reusedValues : Sighash.SighashReusedValues = { var previousOutputsHash = null; ... };
    switch (Sighash.calculate_sighash_ecdsa(tx, 0, utxo, Sighash.SigHashAll, reusedValues)) {
      case (?hash) { Sighash.hex_from_array(hash) }; // Hex-encoded sighash
      case (null) { /* Invalid input */ };
    };
    ```

- `hex_from_array(bytes : [Nat8]) : Text`
  - Converts a byte array to a lowercase hex string.
  - Example: `[0xa1, 0xb2]` → `"a1b2"`.

- `array_from_hex(hex : Text) : [Nat8]`
  - Converts a hex string (lowercase or uppercase) to a byte array.
  - Returns an empty array if the hex string is invalid.
  - Example: `"a1b2"` → `[0xa1, 0xb2]`.

- `nat16_to_bytes(n : Nat16) : [Nat8]`, `nat32_to_bytes(n : Nat32) : [Nat8]`, `nat64_to_le_bytes(n : Nat64) : [Nat8]`
  - Converts numbers to little-endian byte arrays for serialization.
  - Example: `nat32_to_bytes(256)` → `[0x00, 0x01, 0x00, 0x00]`.

- `transaction_signing_ecdsa_domain_hash() : [Nat8]`
  - Returns the SHA-256 hash of the ECDSA domain separator (`"TransactionSigningHashECDSA"`).
  - Example: Returns a 32-byte array.

- `blake2b_256(data : [Nat8], key : ?Text) : [Nat8]`
  - Computes a Blake2b-256 hash of the input data, optionally with a key.
  - Example: `blake2b_256([0xa1, 0xb2], ?"TransactionSigningHash")` → 32-byte hash.

- `zero_hash() : [Nat8]`
  - Returns a 32-byte zero-filled array for sighash calculations.
  - Example: Returns `[0, 0, ..., 0]`.

### `transaction.mo`
Provides functions for building and serializing Kaspa transactions, including utilities for signature encoding and hex conversions. It supports creating transactions with one input and one or two outputs (recipient and optional change).

#### Public Functions
- `build_transaction(utxo : Types.UTXO, recipient_script : Text, output_amount : Nat64, fee : Nat64, change_script : Text) : Types.KaspaTransaction`
  - Builds a transaction with one input (from a UTXO) and one or two outputs (recipient and optional change if the remaining amount is above the dust threshold of 1000 sompi).
  - Returns an empty transaction if the UTXO amount is insufficient.
  - Example:
    ```motoko
    let utxo : Types.UTXO = {
      transactionId = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6";
      index = 0;
      amount = 2000000;
      scriptVersion = 0;
      scriptPublicKey = "20a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3ac";
      address = "kaspa:qypq...";
    };
    let tx = Transaction.build_transaction(utxo, "20d4e5f6a1b2c3...ac", 1000000, 1000, "20a1b2c3d4e5f6...ac");
    // Returns a transaction with one input and two outputs (recipient + change)
    ```

- `serialize_transaction(tx : Types.KaspaTransaction) : Text`
  - Serializes a transaction to JSON format compatible with the Kaspa REST API.
  - Example:
    ```motoko
    let json = Transaction.serialize_transaction(tx);
    // Returns: "{\"transaction\":{\"version\":0,\"inputs\":[...],\"outputs\":[...],...}}"
    ```

- `sign_schnorr(sighash : [Nat8], private_key : [Nat8]) : [Nat8]`
  - Placeholder for Schnorr signing (currently returns a dummy 64-byte signature).
  - Expects a 32-byte sighash and 32-byte private key.
  - TODO: Implement actual Schnorr signing with a secp256k1 library or external canister.
  - Example:
    ```motoko
    let sighash = Sighash.array_from_hex("a1b2c3...");
    let privKey = Transaction.array_from_hex("d4e5f6...");
    let sig = Transaction.sign_schnorr(sighash, privKey); // Placeholder
    ```

- `signature_to_hex(sig : [Nat8]) : Text`
  - Converts a signature (e.g., DER-encoded) to a lowercase hex string.
  - Example: `[0xa1, 0xb2]` → `"a1b2"`.

- `array_from_hex(hex : Text) : [Nat8]`
  - Converts a hex string (lowercase or uppercase) to a byte array.
  - Returns an empty array if the hex string is invalid.
  - Example: `"a1b2"` → `[0xa1, 0xb2]`.

### `types.mo`
Defines data structures for Kaspa transactions and UTXOs, used across the other modules for address handling, sighash calculation, and transaction building.

#### Public Types
- `Outpoint`:
  ```motoko
  {
    transactionId: Text; // Hex-encoded transaction ID (64 chars)
    index: Nat32;       // Output index in the transaction
  }
  ```
  - Represents a transaction outpoint (reference to a previous output).

- `TransactionInput`:
  ```motoko
  {
    previousOutpoint: Outpoint; // Reference to the UTXO being spent
    signatureScript: Text;      // Hex-encoded signature script (empty before signing)
    sequence: Nat64;           // Sequence number for lock time or replacement
    sigOpCount: Nat8;          // Number of signature operations
  }
  ```
  - Represents an input in a Kaspa transaction.

- `ScriptPublicKey`:
  ```motoko
  {
    version: Nat16;          // Script version (e.g., 0)
    scriptPublicKey: Text;   // Hex-encoded script public key (e.g., "20<32-byte-pubkey>ac")
  }
  ```
  - Represents a script public key for an output.

- `TransactionOutput`:
  ```motoko
  {
    amount: Nat64;            // Amount in sompi
    scriptPublicKey: ScriptPublicKey; // Output script
  }
  ```
  - Represents an output in a Kaspa transaction.

- `KaspaTransaction`:
  ```motoko
  {
    version: Nat16;          // Transaction version (e.g., 0)
    inputs: [TransactionInput]; // Array of inputs
    outputs: [TransactionOutput]; // Array of outputs
    lockTime: Nat64;         // Lock time for transaction
    subnetworkId: Text;      // Hex-encoded subnetwork ID (40 chars)
    gas: Nat64;              // Gas for subnetwork transactions
    payload: Text;           // Hex-encoded payload
  }
  ```
  - Represents a complete Kaspa transaction.

- `UTXO`:
  ```motoko
  {
    transactionId: Text;     // Hex-encoded transaction ID (64 chars)
    index: Nat32;           // Output index
    amount: Nat64;          // Amount in sompi
    scriptVersion: Nat16;   // Script version (e.g., 0)
    scriptPublicKey: Text;  // Hex-encoded script public key
    address: Text;          // Kaspa address (e.g., "kaspa:qypq...")
  }
  ```
  - Represents an unspent transaction output.

#### Example
```motoko
let tx : Types.KaspaTransaction = {
  version = 0;
  inputs = [{
    previousOutpoint = { transactionId = "a1b2c3d4e5f6..."; index = 0 };
    signatureScript = "";
    sequence = 0;
    sigOpCount = 1;
  }];
  outputs = [{
    amount = 1000000;
    scriptPublicKey = { version = 0; scriptPublicKey = "20d4e5f6...ac" };
  }];
  lockTime = 0;
  subnetworkId = "0000000000000000000000000000000000000000";
  gas = 0;
  payload = "";
};
```

## Contributing
Contributions are welcome! Please open an issue or pull request on the [GitHub repository](https://github.com/codecustard/kaspa-mo).

## License
[MIT License](LICENSE)

## Additional Resources
- [Quick Start](https://internetcomputer.org/docs/current/developer-docs/setup/deploy-locally)
- [SDK Developer Tools](https://internetcomputer.org/docs/current/developer-docs/setup/install)
- [Motoko Programming Language Guide](https://internetcomputer.org/docs/current/motoko/main/motoko)
- [Motoko Language Quick Reference](https://internetcomputer.org/docs/current/motoko/main/language-manual)
