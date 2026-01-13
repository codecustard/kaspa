/// Kaspa Script Opcodes
///
/// This module defines the opcodes used in Kaspa scripts.
/// Most opcodes are compatible with Bitcoin Script, but Kaspa includes
/// additional opcodes like OP_BLAKE2B for BLAKE2B hashing.
///
/// References:
/// - Bitcoin Script opcodes: https://en.bitcoin.it/wiki/Script
/// - Kaspa-specific extensions for BLAKE2B support

import Nat8 "mo:base/Nat8";

module {
  // Constants
  public let OP_FALSE : Nat8 = 0x00;
  public let OP_0 : Nat8 = 0x00;  // Alias for OP_FALSE

  // Push value
  public let OP_PUSHDATA1 : Nat8 = 0x4C;  // Next byte contains number of bytes to push
  public let OP_PUSHDATA2 : Nat8 = 0x4D;  // Next 2 bytes contain number of bytes to push
  public let OP_PUSHDATA4 : Nat8 = 0x4E;  // Next 4 bytes contain number of bytes to push

  // Small integers (1-16)
  public let OP_1 : Nat8 = 0x51;
  public let OP_TRUE : Nat8 = 0x51;  // Alias for OP_1

  // Flow control
  public let OP_IF : Nat8 = 0x63;
  public let OP_NOTIF : Nat8 = 0x64;
  public let OP_ELSE : Nat8 = 0x67;
  public let OP_ENDIF : Nat8 = 0x68;
  public let OP_VERIFY : Nat8 = 0x69;
  public let OP_RETURN : Nat8 = 0x6A;

  // Stack operations
  public let OP_DROP : Nat8 = 0x75;
  public let OP_DUP : Nat8 = 0x76;

  // Equality
  public let OP_EQUAL : Nat8 = 0x87;
  public let OP_EQUALVERIFY : Nat8 = 0x88;

  // Crypto - SHA family
  public let OP_SHA256 : Nat8 = 0xA8;

  // Crypto - BLAKE2B (Kaspa-specific)
  // NOTE: This opcode value needs verification from Kaspa source code
  // Bitcoin doesn't have BLAKE2B, so this is a Kaspa extension
  public let OP_BLAKE2B : Nat8 = 0xB3;

  // Crypto - Hash operations
  public let OP_HASH256 : Nat8 = 0xAA;  // SHA256(SHA256(x))

  // Signature verification
  public let OP_CHECKSIG : Nat8 = 0xAC;
  public let OP_CHECKSIG_ECDSA : Nat8 = 0xAB;
  public let OP_CHECKSIGVERIFY : Nat8 = 0xAD;
  public let OP_CHECKMULTISIG : Nat8 = 0xAE;

  // Data size opcodes (1-75 bytes can be pushed directly)
  public let OP_DATA_1 : Nat8 = 0x01;
  public let OP_DATA_20 : Nat8 = 0x14;  // 20 bytes (common for hashes)
  public let OP_DATA_32 : Nat8 = 0x20;  // 32 bytes (Schnorr pubkeys, hashes)
  public let OP_DATA_33 : Nat8 = 0x21;  // 33 bytes (ECDSA compressed pubkeys)

  /// Helper function to create a data push opcode for sizes 1-75
  /// For data larger than 75 bytes, use OP_PUSHDATA1/2/4
  public func opData(size : Nat8) : Nat8 {
    assert(size >= 1 and size <= 75);
    size
  };

  /// Determine the appropriate push opcode for given data size
  public func getPushOpcode(dataSize : Nat) : Nat8 {
    if (dataSize <= 75) {
      return Nat8.fromNat(dataSize);
    } else if (dataSize <= 255) {
      return OP_PUSHDATA1;
    } else if (dataSize <= 65535) {
      return OP_PUSHDATA2;
    } else {
      return OP_PUSHDATA4;
    };
  };

  /// Maximum size for a single OP_PUSH operation in Kaspa (520 bytes)
  public let MAX_PUSH_SIZE : Nat = 520;
};
