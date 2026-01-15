import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat16 "mo:base/Nat16";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Iter "mo:base/Iter";

import Address "address";
import Types "types";
import ScriptBuilder "script_builder";

module {

    // secp256k1 curve order / 2 for low-S normalization
    private let curve_n_half : [Nat8] = [
        0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D,
        0xDF, 0xE9, 0x2F, 0x46, 0x68, 0x1B, 0x20, 0xA0
    ];


    // Helper to encode (r,s) signature to DER format for Kaspa with low-S normalization
    public func encode_der_signature(sig : [Nat8]) : [Nat8] {
        if (sig.size() != 64) {
            Debug.print("Invalid signature length: " # Nat.toText(sig.size()) # ", expected 64 bytes");
            return [];
        };
        let r = Array.subArray(sig, 0, 32);
        let s = Array.subArray(sig, 32, 32);
        // Normalize s to low-S (s <= n/2)
        let s_normalized = if (compare_bytes(s, curve_n_half) > 0) {
            subtract_bytes(curve_n_half, s)
        } else {
            s
        };
        // Add leading zeros if high bit is set
        let r_prefix = if (r[0] >= 0x80) { [0x00 : Nat8] } else { [] };
        let s_prefix = if (s_normalized[0] >= 0x80) { [0x00 : Nat8] } else { [] };
        let r_der = Array.append([0x02 : Nat8, Nat8.fromNat(r_prefix.size() + r.size())], Array.append(r_prefix, r));
        let s_der = Array.append([0x02 : Nat8, Nat8.fromNat(s_prefix.size() + s_normalized.size())], Array.append(s_prefix, s_normalized));
        let seq = Array.append(r_der, s_der);
        Array.append([0x30 : Nat8, Nat8.fromNat(seq.size())], seq)
    };

    // Compare two 32-byte arrays (returns 1 if a > b, 0 if equal, -1 if a < b)
    private func compare_bytes(a : [Nat8], b : [Nat8]) : Int {
        if (a.size() != b.size()) {
            Debug.print("Cannot compare arrays of different lengths");
            return 0;
        };
        for (i in Iter.range(0, a.size() - 1)) {
            if (a[i] > b[i]) return 1;
            if (a[i] < b[i]) return -1;
        };
        0
    };

    // Subtract b from a (a - b) for 32-byte arrays (for low-S normalization)
    private func subtract_bytes(a : [Nat8], b : [Nat8]) : [Nat8] {
        if (a.size() != 32 or b.size() != 32) {
            Debug.print("Invalid array lengths for subtraction: a=" # Nat.toText(a.size()) # ", b=" # Nat.toText(b.size()));
            return [];
        };
        let result = Buffer.Buffer<Nat8>(32);
        var borrow : Nat = 0;
        for (i in Iter.range(0, 31)) {
            let ai = Nat8.toNat(a[31 - i]);
            let bi = Nat8.toNat(b[31 - i]);
            let diff = ai - bi - borrow;
            if (diff < 0) {
                result.add(Nat8.fromNat(diff + 256));
                borrow := 1;
            } else {
                result.add(Nat8.fromNat(diff));
                borrow := 0;
            };
        };
        Array.reverse(Buffer.toArray(result))
    };

    // Convert DER signature to hex for testing
    public func signature_to_hex(sig : [Nat8]) : Text {
        Address.hex_from_array(sig)
    };

    // Helper to convert hex to bytes
    public func array_from_hex(hex: Text) : [Nat8] {
        let chars = Text.toIter(hex);
        let result = Buffer.Buffer<Nat8>(hex.size() / 2);
        var byte: Nat = 0;
        var is_high = true;
        for (c in chars) {
            let val = if (c >= '0' and c <= '9') {
                Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'))
            } else if (c >= 'a' and c <= 'f') {
                Nat32.toNat(Char.toNat32(c) - Char.toNat32('a') + 10)
            } else if (c >= 'A' and c <= 'F') {
                Nat32.toNat(Char.toNat32(c) - Char.toNat32('A') + 10)
            } else {
                return [];
            };
            if (is_high) {
                byte := val * 16;
                is_high := false;
            } else {
                byte += val;
                result.add(Nat8.fromNat(byte));
                is_high := true;
            }
        };
        Buffer.toArray(result)
    };

    // Placeholder for Schnorr signing
    public func sign_schnorr(sighash: [Nat8], private_key: [Nat8]) : [Nat8] {
        // TODO: Implement Schnorr signing (e.g., using secp256k1 library or external canister)
        // Input: 32-byte sighash, 32-byte private key
        // Output: 64-byte Schnorr signature
        let dummy_signature : [Nat8] = Array.freeze(Array.init<Nat8>(64, 0));
        dummy_signature
    };


    // Build a transaction with one input and one or two outputs (recipient + optional change)
    public func build_transaction(
        utxo: Types.UTXO,
        recipient_script: Text, // scriptPublicKey of recipient (hex)
        output_amount: Nat64,  // Amount to send (in sompi)
        fee: Nat64,            // Transaction fee (in sompi)
        change_script: Text    // scriptPublicKey for change (sender's address)
    ) : Types.KaspaTransaction {
        let total_input = utxo.amount;
        if (total_input < output_amount + fee) {
            Debug.print("🚨 Insufficient UTXO amount for transaction");
            return {
                version = 0;
                inputs = [];
                outputs = [];
                lockTime = 0;
                subnetworkId = "0000000000000000000000000000000000000000";
                gas = 0;
                payload = "";
            };
        };

        let change_amount = total_input - output_amount - fee;
        let outputs : [Types.TransactionOutput] = if (change_amount >= 1000) { // Dust threshold
            [
                {
                    amount = output_amount;
                    scriptPublicKey = {
                        version = 0;
                        scriptPublicKey = recipient_script;
                    };
                },
                {
                    amount = change_amount;
                    scriptPublicKey = {
                        version = 0;
                        scriptPublicKey = change_script;
                    };
                }
            ]
        } else {
            [
                {
                    amount = output_amount;
                    scriptPublicKey = {
                        version = 0;
                        scriptPublicKey = recipient_script;
                    };
                }
            ]
        };

        {
            version = 0;
            inputs = [
                {
                    previousOutpoint = {
                        transactionId = utxo.transactionId;
                        index = utxo.index;
                    };
                    signatureScript = ""; // To be set after signing
                    sequence = 0;
                    sigOpCount = 1;
                }
            ];
            outputs = outputs;
            lockTime = 0;
            subnetworkId = "0000000000000000000000000000000000000000";
            gas = 0;
            payload = "";
        }
    };

    // Serialize transaction to JSON for Kaspa REST API
    public func serialize_transaction(tx: Types.KaspaTransaction) : Text {
        let inputs_json = Array.foldLeft<Types.TransactionInput, Text>(
            tx.inputs,
            "[",
            func (acc: Text, input: Types.TransactionInput) : Text {
                acc # (if (acc != "[") { "," } else { "" }) #
                "{\"previousOutpoint\":{\"transactionId\":\"" # input.previousOutpoint.transactionId #
                "\",\"index\":" # Nat.toText(Nat32.toNat(input.previousOutpoint.index)) #
                "},\"signatureScript\":\"" # input.signatureScript #
                "\",\"sequence\":" # Nat64.toText(input.sequence) #
                ",\"sigOpCount\":" # Nat.toText(Nat8.toNat(input.sigOpCount)) # "}"
            }
        ) # "]";

        let outputs_json = Array.foldLeft<Types.TransactionOutput, Text>(
            tx.outputs,
            "[",
            func (acc: Text, output: Types.TransactionOutput) : Text {
                acc # (if (acc != "[") { "," } else { "" }) #
                "{\"amount\":" # Nat64.toText(output.amount) #
                ",\"scriptPublicKey\":{\"version\":" # Nat.toText(Nat16.toNat(output.scriptPublicKey.version)) #
                ",\"scriptPublicKey\":\"" # output.scriptPublicKey.scriptPublicKey # "\"}}"
            }
        ) # "]";

        "{\"transaction\":{" #
        "\"version\":" # Nat.toText(Nat16.toNat(tx.version)) # "," #
        "\"inputs\":" # inputs_json # "," #
        "\"outputs\":" # outputs_json # "," #
        "\"lockTime\":" # Nat64.toText(tx.lockTime) # "," #
        "\"subnetworkId\":\"" # tx.subnetworkId # "\"," #
        "\"gas\":" # Nat64.toText(tx.gas) # "," #
        "\"payload\":\"" # tx.payload # "\"" #
        "}}"
    };

    /// Build a P2SH commit transaction
    /// Creates a transaction that outputs to a P2SH address
    ///
    /// @param utxo - Input UTXO to spend
    /// @param p2sh_script - The P2SH scriptPublicKey (hex) from ScriptBuilder.buildP2SHCommit
    /// @param output_amount - Amount to send to P2SH (in sompi)
    /// @param fee - Transaction fee (in sompi)
    /// @param change_script - scriptPublicKey for change (sender's address)
    /// @return Kaspa transaction
    public func build_p2sh_commit_transaction(
        utxo: Types.UTXO,
        p2sh_script: Text,
        output_amount: Nat64,
        fee: Nat64,
        change_script: Text
    ) : Types.KaspaTransaction {
        build_transaction(utxo, p2sh_script, output_amount, fee, change_script)
    };

    /// Build a P2SH reveal (spending) transaction
    /// Spends from a P2SH output by providing the redeem script
    ///
    /// @param p2sh_input - P2SH input containing UTXO, redeem script, and signature
    /// @param outputs - Transaction outputs
    /// @return Kaspa transaction with P2SH signature script
    public func build_p2sh_reveal_transaction(
        p2sh_input: Types.P2SHInput,
        outputs: [Types.TransactionOutput]
    ) : Types.KaspaTransaction {
        // Build the signature script: <signature> <redeemScript>
        let sigScript = ScriptBuilder.buildP2SHSignatureScript(
            p2sh_input.signature,
            p2sh_input.redeemScript
        );

        let sigScriptHex = ScriptBuilder.bytesToHex(sigScript);

        {
            version = 0;
            inputs = [
                {
                    previousOutpoint = {
                        transactionId = p2sh_input.utxo.transactionId;
                        index = p2sh_input.utxo.index;
                    };
                    signatureScript = sigScriptHex;
                    sequence = 0;
                    sigOpCount = 1;
                }
            ];
            outputs = outputs;
            lockTime = 0;
            subnetworkId = "0000000000000000000000000000000000000000";
            gas = 0;
            payload = "";
        }
    };

    /// Helper to update a transaction's signature script
    /// Used after signing to add the signature to the transaction
    ///
    /// @param tx - Transaction to update
    /// @param signatureScript - Hex-encoded signature script
    /// @return Updated transaction
    public func set_signature_script(
        tx: Types.KaspaTransaction,
        signatureScript: Text
    ) : Types.KaspaTransaction {
        if (tx.inputs.size() == 0) {
            return tx;
        };

        let updated_input = {
            previousOutpoint = tx.inputs[0].previousOutpoint;
            signatureScript = signatureScript;
            sequence = tx.inputs[0].sequence;
            sigOpCount = tx.inputs[0].sigOpCount;
        };

        {
            version = tx.version;
            inputs = [updated_input];
            outputs = tx.outputs;
            lockTime = tx.lockTime;
            subnetworkId = tx.subnetworkId;
            gas = tx.gas;
            payload = tx.payload;
        }
    };
};