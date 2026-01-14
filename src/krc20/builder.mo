/// KRC20 Transaction Builder
///
/// This module provides high-level functions for building KRC20 commit-reveal
/// transaction pairs. It combines the script building, JSON formatting, and
/// transaction construction components.

import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";

import ScriptBuilder "../script_builder";
import Transaction "../transaction";
import Address "../address";
import Types "../types";
import Errors "../errors";
import KRC20Types "types";

module {
  /// Result of building a commit-reveal transaction pair
  /// Contains the commit transaction and the data needed for the reveal
  public type CommitRevealPair = {
    commitTx: Types.KaspaTransaction;       // Transaction to broadcast first
    redeemScript: [Nat8];                   // Redeem script for reveal (save this!)
    p2shScriptPubKey: Text;                 // P2SH scriptPublicKey (hex)
    p2shScriptHash: [Nat8];                 // BLAKE2B hash of redeem script
  };

  /// Build a commit transaction for a KRC20 operation
  ///
  /// This creates the first transaction of the commit-reveal pair.
  /// The transaction outputs to a P2SH address that commits to the
  /// KRC20 operation data.
  ///
  /// @param pubkey - Public key bytes (32 for Schnorr, 33 for ECDSA)
  /// @param operation_json - JSON string of the KRC20 operation
  /// @param utxo - UTXO to spend for funding the commit
  /// @param commit_amount - Amount to send to P2SH output (minimum: dust threshold)
  /// @param fee - Transaction fee
  /// @param change_address - Address for change output
  /// @param use_ecdsa - If true, use ECDSA; else use Schnorr
  /// @return Result containing CommitRevealPair or error
  public func buildCommit(
    pubkey: [Nat8],
    operation_json: Text,
    utxo: Types.UTXO,
    commit_amount: Nat64,
    fee: Nat64,
    change_address: Text,
    use_ecdsa: Bool
  ) : Result.Result<CommitRevealPair, Errors.KaspaError> {
    // 1. Build data envelope
    let json_bytes = Blob.toArray(Text.encodeUtf8(operation_json));
    let envelope = ScriptBuilder.buildDataEnvelope(
      "kasplex",  // Protocol identifier
      json_bytes,
      []          // No metadata
    );

    // 2. Build redeem script (pubkey + OP_CHECKSIG + envelope)
    let redeemScript = ScriptBuilder.buildRedeemScript(
      pubkey,
      envelope,
      use_ecdsa
    );

    // 3. Hash redeem script with BLAKE2B
    let scriptHash = ScriptBuilder.hashRedeemScript(redeemScript);

    // 4. Build P2SH commit script
    let p2shScript = ScriptBuilder.buildP2SHCommit(scriptHash);
    let p2shScriptHex = ScriptBuilder.bytesToHex(p2shScript);

    // 5. Get change script from address
    let changeScriptResult = Address.decodeAddress(change_address);
    let changeScript = switch (changeScriptResult) {
      case (#ok(decoded)) { decoded.script_public_key };
      case (#err(e)) { return #err(e) };
    };

    // 6. Build commit transaction
    let commitTx = Transaction.build_p2sh_commit_transaction(
      utxo,
      p2shScriptHex,
      commit_amount,
      fee,
      changeScript
    );

    #ok({
      commitTx = commitTx;
      redeemScript = redeemScript;
      p2shScriptPubKey = p2shScriptHex;
      p2shScriptHash = scriptHash;
    })
  };

  /// Build a reveal transaction that spends the commit output
  ///
  /// This creates the second transaction that reveals the KRC20 operation
  /// by spending the P2SH output and including the redeem script.
  ///
  /// @param commit_tx_id - Transaction ID of the commit transaction
  /// @param commit_output_index - Index of the P2SH output in commit tx
  /// @param commit_amount - Amount in the P2SH output
  /// @param redeem_script - Redeem script from buildCommit
  /// @param signature - Signature over the reveal transaction
  /// @param outputs - Outputs for the reveal transaction
  /// @param p2sh_address - P2SH address (for UTXO construction)
  /// @return Reveal transaction
  public func buildReveal(
    commit_tx_id: Text,
    commit_output_index: Nat32,
    commit_amount: Nat64,
    redeem_script: [Nat8],
    signature: [Nat8],
    outputs: [Types.TransactionOutput],
    p2sh_address: Text
  ) : Types.KaspaTransaction {
    // Build P2SH input
    let p2shInput: Types.P2SHInput = {
      utxo = {
        transactionId = commit_tx_id;
        index = commit_output_index;
        amount = commit_amount;
        scriptPublicKey = ScriptBuilder.bytesToHex(
          ScriptBuilder.buildP2SHFromRedeem(redeem_script)
        );
        scriptVersion = 0;
        address = p2sh_address;
      };
      redeemScript = redeem_script;
      signature = signature;
    };

    // Build reveal transaction
    Transaction.build_p2sh_reveal_transaction(p2shInput, outputs)
  };

  /// Helper to build standard reveal outputs (send remaining amount to address)
  ///
  /// @param recipient_address - Where to send the funds
  /// @param amount - Amount to send (after fees)
  /// @return Output array
  public func buildRevealOutputs(
    recipient_address: Text,
    amount: Nat64
  ) : Result.Result<[Types.TransactionOutput], Errors.KaspaError> {
    // Decode recipient address to get scriptPublicKey
    let decoded = Address.decodeAddress(recipient_address);
    let recipientScript = switch (decoded) {
      case (#ok(addr)) { addr.script_public_key };
      case (#err(e)) { return #err(e) };
    };

    #ok([{
      amount = amount;
      scriptPublicKey = {
        version = 0;
        scriptPublicKey = recipientScript;
      };
    }])
  };

  /// Calculate the P2SH address from a commit pair
  ///
  /// @param addressType - Address type (0 = Schnorr, 1 = ECDSA, 2 = P2SH)
  /// @param scriptHash - Script hash from CommitRevealPair
  /// @param prefix - Address prefix (e.g., "kaspa" for mainnet)
  /// @return Kaspa address or error
  public func getP2SHAddress(
    addressType: Nat,
    scriptHash: [Nat8],
    prefix: Text
  ) : Result.Result<Text, Errors.KaspaError> {
    // For P2SH, addressType should be 2
    assert(addressType == 2);

    // generateAddressWithPrefix takes (pubkey: Blob, addr_type: Nat, prefix: Text)
    let result = Address.generateAddressWithPrefix(Blob.fromArray(scriptHash), addressType, prefix);
    switch (result) {
      case (#ok(info)) { #ok(info.address) };
      case (#err(e)) { #err(e) };
    }
  };

  /// Estimate fee for a KRC20 operation
  ///
  /// Returns a conservative estimate based on transaction size.
  /// Commit-reveal requires TWO transactions, so total fee = commit_fee + reveal_fee
  ///
  /// @param operation_json - The KRC20 operation JSON
  /// @return Estimated fees (commit_fee, reveal_fee)
  public func estimateFees(operation_json: Text) : (Nat64, Nat64) {
    // Conservative estimates (actual fees depend on UTXO structure)
    // Commit TX: Standard transaction (normal fee)
    // Reveal TX: Larger due to redeem script in signature script (higher fee)

    // Base fee per transaction (adjust based on network conditions)
    let base_fee: Nat64 = 1000;  // 1000 sompi base

    // Additional fee for reveal due to larger signature script
    let json_size = operation_json.size();
    let reveal_extra: Nat64 = Nat64.fromNat(json_size / 100 + 1000);

    let commit_fee = base_fee;
    let reveal_fee = base_fee + reveal_extra;

    (commit_fee, reveal_fee)
  };

  /// Minimum amount for KRC20 operations
  /// The P2SH output must be above the dust threshold
  public let MIN_COMMIT_AMOUNT: Nat64 = 1000;  // 1000 sompi

  /// Recommended commit amount for KRC20 operations
  /// This ensures the output is well above dust threshold
  public let RECOMMENDED_COMMIT_AMOUNT: Nat64 = 10000;  // 10000 sompi
};
