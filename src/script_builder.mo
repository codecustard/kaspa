/// Script Builder for Kaspa P2SH and KRC20
///
/// This module provides utilities for constructing Kaspa scripts,
/// particularly for KRC20 token operations using the commit-reveal pattern.
///
/// Key functionality:
/// - Data envelope construction (OP_FALSE OP_IF ... OP_ENDIF)
/// - Redeem script building (pubkey + signature check + data)
/// - P2SH commit script generation
/// - Multi-push chunking for data >520 bytes

import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Blake2B "mo:blake2b/lib";

import Opcodes "opcodes";

module {
  /// Convert text to UTF-8 bytes
  private func textToBytes(text : Text) : [Nat8] {
    Blob.toArray(Text.encodeUtf8(text))
  };

  /// Create an OP_PUSH operation for the given data
  /// Handles automatic selection of OP_DATA_X, OP_PUSHDATA1/2/4
  public func opPush(data : [Nat8]) : [Nat8] {
    let size = data.size();
    let buf = Buffer.Buffer<Nat8>(size + 5);  // Max overhead: 1 + 4 bytes

    if (size == 0) {
      // Empty data pushes OP_0
      buf.add(Opcodes.OP_0);
    } else if (size <= 75) {
      // Direct push: <size> <data>
      buf.add(Nat8.fromNat(size));
      buf.append(Buffer.fromArray(data));
    } else if (size <= 255) {
      // OP_PUSHDATA1: 0x4C <1-byte-size> <data>
      buf.add(Opcodes.OP_PUSHDATA1);
      buf.add(Nat8.fromNat(size));
      buf.append(Buffer.fromArray(data));
    } else if (size <= 65535) {
      // OP_PUSHDATA2: 0x4D <2-byte-size-LE> <data>
      buf.add(Opcodes.OP_PUSHDATA2);
      buf.add(Nat8.fromNat(size % 256));
      buf.add(Nat8.fromNat(size / 256));
      buf.append(Buffer.fromArray(data));
    } else {
      // OP_PUSHDATA4: 0x4E <4-byte-size-LE> <data>
      buf.add(Opcodes.OP_PUSHDATA4);
      buf.add(Nat8.fromNat(size % 256));
      buf.add(Nat8.fromNat((size / 256) % 256));
      buf.add(Nat8.fromNat((size / 65536) % 256));
      buf.add(Nat8.fromNat(size / 16777216));
      buf.append(Buffer.fromArray(data));
    };

    Buffer.toArray(buf)
  };

  /// Split data into chunks of maximum size (default: 520 bytes)
  /// Used for data that exceeds the maximum OP_PUSH size
  public func chunkData(data : [Nat8], maxSize : Nat) : [[Nat8]] {
    assert(maxSize > 0);
    let chunks = Buffer.Buffer<[Nat8]>(data.size() / maxSize + 1);
    var i = 0;

    while (i < data.size()) {
      let remainingSize = data.size() - i;
      let chunkSize = if (remainingSize < maxSize) remainingSize else maxSize;

      let chunk = Array.tabulate<Nat8>(chunkSize, func(j) {
        data[i + j]
      });

      chunks.add(chunk);
      i += chunkSize;
    };

    Buffer.toArray(chunks)
  };

  /// Build a Kasplex data envelope
  ///
  /// Structure:
  /// OP_FALSE
  /// OP_IF
  ///   OP_PUSH "kasplex"       # Protocol identifier
  ///   OP_PUSH 1               # Metadata marker (reserved)
  ///   OP_PUSH metadata        # Optional metadata (can be empty)
  ///   OP_PUSH 0               # Content marker
  ///   OP_PUSH content         # Actual data (may span multiple pushes if >520 bytes)
  /// OP_ENDIF
  ///
  /// @param protocol - Protocol identifier (e.g., "kasplex")
  /// @param content - The actual data to embed (e.g., KRC20 JSON)
  /// @param metadata - Optional metadata (pass empty array if none)
  /// @return Serialized envelope bytes
  public func buildDataEnvelope(
    protocol : Text,
    content : [Nat8],
    metadata : [Nat8]
  ) : [Nat8] {
    let buf = Buffer.Buffer<Nat8>(content.size() + 100);

    // OP_FALSE OP_IF wrapper start
    buf.add(Opcodes.OP_FALSE);
    buf.add(Opcodes.OP_IF);

    // Protocol identifier
    buf.append(Buffer.fromArray(opPush(textToBytes(protocol))));

    // Metadata marker: OP_1 (0x51) pushes number 1
    buf.add(Opcodes.OP_1);

    // Metadata (can be empty)
    buf.append(Buffer.fromArray(opPush(metadata)));

    // Content marker: OP_0 (0x00) pushes empty/0
    buf.add(Opcodes.OP_0);

    // Content data - may need chunking if >520 bytes
    if (content.size() <= Opcodes.MAX_PUSH_SIZE) {
      // Single push
      buf.append(Buffer.fromArray(opPush(content)));
    } else {
      // Multiple pushes for large content
      let chunks = chunkData(content, Opcodes.MAX_PUSH_SIZE);
      for (chunk in chunks.vals()) {
        buf.append(Buffer.fromArray(opPush(chunk)));
      };
    };

    // OP_ENDIF to close the envelope
    buf.add(Opcodes.OP_ENDIF);

    Buffer.toArray(buf)
  };

  /// Build a redeem script for P2SH
  ///
  /// Structure:
  /// <pubkey>
  /// OP_CHECKSIG or OP_CHECKSIG_ECDSA
  /// <data_envelope>
  ///
  /// @param pubkey - Public key bytes (32 for Schnorr, 33 for ECDSA)
  /// @param dataEnvelope - The data envelope to append
  /// @param useECDSA - If true, use OP_CHECKSIG_ECDSA; else use OP_CHECKSIG (Schnorr)
  /// @return Complete redeem script bytes
  public func buildRedeemScript(
    pubkey : [Nat8],
    dataEnvelope : [Nat8],
    useECDSA : Bool
  ) : [Nat8] {
    let buf = Buffer.Buffer<Nat8>(pubkey.size() + dataEnvelope.size() + 10);

    // Push public key
    buf.append(Buffer.fromArray(opPush(pubkey)));

    // Signature check opcode
    if (useECDSA) {
      buf.add(Opcodes.OP_CHECKSIG_ECDSA);
    } else {
      buf.add(Opcodes.OP_CHECKSIG);
    };

    // Append data envelope
    buf.append(Buffer.fromArray(dataEnvelope));

    Buffer.toArray(buf)
  };

  /// Hash a redeem script using BLAKE2B-256
  ///
  /// @param redeemScript - The redeem script to hash
  /// @return 32-byte BLAKE2B hash
  public func hashRedeemScript(redeemScript : [Nat8]) : [Nat8] {
    let config : Blake2B.Blake2bConfig = {
      digest_length = 32;  // 256 bits = 32 bytes
      key = null;
      salt = null;
      personal = null;
    };
    let hash = Blake2B.hash(Blob.fromArray(redeemScript), ?config);
    Blob.toArray(hash)
  };

  /// Build a P2SH commit script
  ///
  /// Structure:
  /// OP_BLAKE2B
  /// OP_DATA_32
  /// <32-byte script hash>
  /// OP_EQUAL
  ///
  /// @param scriptHash - BLAKE2B hash of the redeem script (32 bytes)
  /// @return P2SH commit script bytes
  public func buildP2SHCommit(scriptHash : [Nat8]) : [Nat8] {
    assert(scriptHash.size() == 32);

    let buf = Buffer.Buffer<Nat8>(35);

    buf.add(Opcodes.OP_BLAKE2B);
    buf.add(Opcodes.OP_DATA_32);
    buf.append(Buffer.fromArray(scriptHash));
    buf.add(Opcodes.OP_EQUAL);

    Buffer.toArray(buf)
  };

  /// Build a complete P2SH script from redeem script
  ///
  /// This is a convenience function that:
  /// 1. Hashes the redeem script with BLAKE2B
  /// 2. Builds the P2SH commit script
  ///
  /// @param redeemScript - The redeem script
  /// @return P2SH commit script bytes
  public func buildP2SHFromRedeem(redeemScript : [Nat8]) : [Nat8] {
    let scriptHash = hashRedeemScript(redeemScript);
    buildP2SHCommit(scriptHash)
  };

  /// Convert bytes to hexadecimal string
  ///
  /// @param bytes - Input bytes
  /// @return Hexadecimal string (lowercase)
  public func bytesToHex(bytes : [Nat8]) : Text {
    let hexChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"];
    var hex = "";
    for (b in bytes.vals()) {
      let hi = Nat8.toNat(b / 16);
      let lo = Nat8.toNat(b % 16);
      hex #= hexChars[hi] # hexChars[lo];
    };
    hex
  };

  /// Build signature script for spending P2SH output
  ///
  /// Structure:
  /// <signature>
  /// <redeem script>
  ///
  /// @param signature - Signature bytes
  /// @param redeemScript - The redeem script that hashes to the P2SH address
  /// @return Signature script bytes
  public func buildP2SHSignatureScript(
    signature : [Nat8],
    redeemScript : [Nat8]
  ) : [Nat8] {
    let buf = Buffer.Buffer<Nat8>(signature.size() + redeemScript.size() + 10);

    // Push signature
    buf.append(Buffer.fromArray(opPush(signature)));

    // Push redeem script
    buf.append(Buffer.fromArray(opPush(redeemScript)));

    Buffer.toArray(buf)
  };
};
