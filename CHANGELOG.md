# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.3.2 (2026-02-11)

* Updated `sha2` dependency from `0.1.6` to `0.1.9`
  * Fixes compatibility with moc 0.16.2
  * All 11 test files pass with the updated dependency

## 0.3.0 (2026-01-14)

* **KRC20 Token Support**: Full support for KRC20 token operations on Kaspa
  * Deploy tokens using commit-reveal pattern (tested on Kaspa Testnet 10)
  * Mint, transfer, and burn operations
  * Both Deploy-Mint (fair launch) and Deploy-Issue (controlled) modes
  * Working example: ICWIN token deployed on testnet
* **Script Builder Module** (`src/script_builder.mo`): Low-level script construction
  * Data envelope building for KRC20 inscriptions
  * Redeem script construction for P2SH
  * Multi-push support for >520 byte payloads
* **KRC20 Modules** (`src/krc20/`): Complete KRC20 implementation
  * `types.mo` - Type definitions for all KRC20 operations
  * `operations.mo` - JSON formatters for deploy, mint, transfer, burn, list, send
  * `builder.mo` - High-level transaction builders for commit-reveal workflow
* **Opcodes Module** (`src/opcodes.mo`): Kaspa opcode constants
* **KRC20 Example** (`examples/krc20_example/`): Working example canister
  * Step-by-step deployment guide
  * Testnet faucet integration (https://faucet-tn10.kaspanet.io/)
  * API endpoints for token verification
* **KRC20 Operations Tests** (`test/krc20_operations.test.mo`): Test coverage for JSON formatting
* Changed **Data Envelope Format**: Use `OP_1` (0x51) and `OP_0` (0x00) opcodes for metadata/content markers instead of push operations
* Changed **P2SH Sighash Calculation**: Fixed to use actual P2SH scriptPubKey, not redeem script
* Changed **Fee Structure**: Updated for KRC20 protocol requirements
  * Deploy: 1000 KAS commit + 1000 KAS reveal fee
  * Mint: 1 KAS fee
  * Transfer/Burn: Network fee only
* Changed **Validation**: Added zero amount validation in `validateAmount()`
* Fixed **Reveal Transaction Signing**: Corrected sighash calculation for P2SH spending
* Fixed **Kasplex Indexer Recognition**: Fixed envelope format to match protocol specification
* Fixed **Test Assertions**: Updated decimal format expectation (string vs number)
* Tested on Kaspa Testnet 10: Successfully deployed ICWIN token
  * Commit TX: `bb376669116b98f3c6d625aad054a7552c7c06eb40eb9907f90ddc2d622b3f6b`
  * Reveal TX: `f418464bdd8001655b320f3605f007d4fa2a5297d3dfe9f6a96e0155c60c679f`
  * Token API: https://tn10api.kasplex.org/v1/krc20/token/ICWIN
* Commit-Reveal Pattern: Two transactions per KRC20 operation
  * Commit creates P2SH output with BLAKE2B hash of redeem script
  * Reveal spends P2SH output, exposing redeem script with embedded data

## 0.2.0 (2025-09-17)

* **Transaction Broadcasting System**: End-to-end transaction lifecycle support
  * `sendTransaction()` function for complete build → sign → broadcast flow
  * `buildTransaction()` function for building transactions without broadcasting
  * `broadcastSerializedTransaction()` function for broadcasting pre-built transactions
  * `getTransactionStatus()` function for monitoring transaction confirmations
* **Wallet Module** (`src/wallet.mo`): Comprehensive wallet implementation
  * Mainnet and testnet support with factory functions
  * Structured error handling with detailed error types
  * UTXO management with automatic coin selection
  * Balance tracking with confirmed/unconfirmed/immature categorization
  * Address generation with derivation path support
  * Fee estimation and validation
* **Enhanced Error Handling** (`src/errors.mo`): Structured error system
  * `ValidationError` for input validation failures
  * `NetworkError` for API communication issues
  * `CryptographicError` for signing and key generation failures
  * `InsufficientFunds` for transaction funding issues
  * `InternalError` for unexpected system states
* **Input Validation System** (`src/validation.mo`): Comprehensive validation utilities
  * Address format validation with checksum verification
  * Amount validation with dust threshold checking
  * Fee validation with minimum requirements
  * Derivation path validation for BIP44 compliance
  * Hex string validation for script data
* **Enhanced Address Operations** (`src/address_v2.mo`): Improved address handling
  * Better error reporting and validation
  * Enhanced hex encoding/decoding utilities
  * Script generation improvements
* **HTTP Integration**: Direct Kaspa API communication
  * UTXO fetching from `api.kaspa.org` and `api-testnet.kaspa.org`
  * Transaction broadcasting with JSON formatting
  * Transaction status monitoring
  * Error handling for network failures
* **Example Implementation** (`examples/wallet_broadcast_example.mo`): Usage demonstration
  * Shows wallet functionality in action
  * Ready-to-deploy canister example
  * Transaction testing capability
* Changed **Modern Motoko Syntax**: Updated to use `(with cycles = amount)` syntax instead of deprecated `Cycles.add()`
* Changed **UTXO Parsing**: Enhanced to handle Kaspa API response format with nested `outpoint` and `utxoEntry` structures
* Changed **Signature Script Formatting**: Bitcoin-style script encoding with length prefixes and sighash types
* Changed **JSON Structure**: Corrected transaction broadcast format to match Kaspa node expectations
* Changed **Cycle Management**: Optimized cycle usage for HTTP outcalls and ECDSA operations
* Fixed **Transaction Broadcasting**: Resolved JSON formatting issues for successful network submission
* Fixed **Signature Validation**: Fixed "signature script is not push only" errors with proper script encoding
* Fixed **UTXO Amount Parsing**: Corrected parsing of amount arrays in API responses
* Fixed **Error Messages**: Enhanced debugging information for failed operations
* Fixed **HTTP Request Format**: Fixed missing/incorrect fields in IC HTTP outcall requests

[unreleased]: https://github.com/codecustard/kaspa/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/codecustard/kaspa/compare/v0.3.0...v0.3.2
[0.3.0]: https://github.com/codecustard/kaspa/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/codecustard/kaspa/releases/tag/v0.2.0
