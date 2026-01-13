import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Array "mo:base/Array";

import ScriptBuilder "../src/script_builder";
import Opcodes "../src/opcodes";

persistent actor {

    private func assertEqual<T>(
        actual: T,
        expected: T,
        message: Text,
        eq: (T, T) -> Bool,
        toText: T -> Text
    ) : Bool {
        if (eq(actual, expected)) {
            Debug.print("✅ PASS: " # message);
            true
        } else {
            Debug.print("❌ FAIL: " # message # " (expected: " # toText(expected) # ", actual: " # toText(actual) # ")");
            false
        }
    };

    private func textEq(a: Text, b: Text) : Bool { a == b };
    private func textToText(t: Text) : Text { t };
    private func natEq(a: Nat, b: Nat) : Bool { a == b };
    private func natToText(n: Nat) : Text { Nat.toText(n) };

    public func runTests() : async Text {
        Debug.print("🧪 Running ScriptBuilder Tests...");

        var passed : Nat = 0;
        var total : Nat = 0;

        // Test 1: opPush with small data (< 75 bytes)
        total += 1;
        let small_data : [Nat8] = [0x01, 0x02, 0x03];
        let push_result = ScriptBuilder.opPush(small_data);
        // Expected: <3> <0x01> <0x02> <0x03>
        let expected_push = [0x03, 0x01, 0x02, 0x03];
        if (Array.equal(push_result, expected_push, func(a, b) { a == b })) {
            Debug.print("✅ PASS: opPush with small data");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: opPush with small data");
        };

        // Test 2: bytesToHex conversion
        total += 1;
        let test_bytes : [Nat8] = [0xDE, 0xAD, 0xBE, 0xEF];
        let hex_result = ScriptBuilder.bytesToHex(test_bytes);
        if (assertEqual(
            hex_result,
            "deadbeef",
            "bytesToHex conversion",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 3: buildDataEnvelope basic structure
        total += 1;
        let test_content : [Nat8] = [0x68, 0x65, 0x6C, 0x6C, 0x6F]; // "hello"
        let envelope = ScriptBuilder.buildDataEnvelope(
            "kasplex",
            test_content,
            []  // No metadata
        );

        // Check envelope starts with OP_FALSE and OP_IF
        let envelope_starts_correctly =
            envelope.size() > 2 and
            envelope[0] == Opcodes.OP_FALSE and
            envelope[1] == Opcodes.OP_IF;

        if (envelope_starts_correctly) {
            Debug.print("✅ PASS: buildDataEnvelope starts with OP_FALSE OP_IF");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: buildDataEnvelope structure");
        };

        // Test 4: buildDataEnvelope ends with OP_ENDIF
        total += 1;
        let envelope_ends_correctly = envelope[envelope.size() - 1] == Opcodes.OP_ENDIF;
        if (envelope_ends_correctly) {
            Debug.print("✅ PASS: buildDataEnvelope ends with OP_ENDIF");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: buildDataEnvelope should end with OP_ENDIF");
        };

        // Test 5: hashRedeemScript produces 32 bytes
        total += 1;
        let test_script : [Nat8] = [0x01, 0x02, 0x03, 0x04];
        let hash = ScriptBuilder.hashRedeemScript(test_script);
        if (assertEqual(
            hash.size(),
            32,
            "hashRedeemScript produces 32-byte hash",
            natEq,
            natToText
        )) {
            passed += 1;
        };

        // Test 6: buildP2SHCommit structure
        total += 1;
        let script_hash : [Nat8] = Array.freeze(Array.init<Nat8>(32, 0));
        let p2sh_commit = ScriptBuilder.buildP2SHCommit(script_hash);

        // Should be: OP_BLAKE2B (1) + OP_DATA_32 (1) + hash (32) + OP_EQUAL (1) = 35 bytes
        if (assertEqual(
            p2sh_commit.size(),
            35,
            "buildP2SHCommit produces 35-byte script",
            natEq,
            natToText
        )) {
            passed += 1;
        };

        // Test 7: buildRedeemScript includes pubkey and checksig
        total += 1;
        let test_pubkey : [Nat8] = Array.freeze(Array.init<Nat8>(32, 0xAA));
        let test_envelope_for_redeem : [Nat8] = [0x00, 0x63, 0x68]; // OP_FALSE OP_IF OP_ENDIF
        let redeem_script = ScriptBuilder.buildRedeemScript(
            test_pubkey,
            test_envelope_for_redeem,
            false  // Use Schnorr
        );

        // Should include the pubkey push + OP_CHECKSIG + envelope
        let redeem_includes_checksig = Array.find<Nat8>(
            redeem_script,
            func(b) { b == Opcodes.OP_CHECKSIG }
        ) != null;

        if (redeem_includes_checksig) {
            Debug.print("✅ PASS: buildRedeemScript includes OP_CHECKSIG");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: buildRedeemScript should include OP_CHECKSIG");
        };

        // Test 8: chunkData splits correctly
        total += 1;
        let large_data = Array.freeze(Array.init<Nat8>(1000, 0xFF));
        let chunks = ScriptBuilder.chunkData(large_data, 520);

        // Should produce 2 chunks (520 + 480)
        let chunk_count_correct = chunks.size() == 2;
        if (chunk_count_correct) {
            Debug.print("✅ PASS: chunkData splits 1000 bytes into 2 chunks");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: chunkData should split 1000 bytes into 2 chunks, got " # Nat.toText(chunks.size()));
        };

        // Test 9: buildP2SHSignatureScript format
        total += 1;
        let test_sig : [Nat8] = Array.freeze(Array.init<Nat8>(64, 0xBB));
        let test_redeem : [Nat8] = [0x01, 0x02, 0x03];
        let sig_script = ScriptBuilder.buildP2SHSignatureScript(test_sig, test_redeem);

        // Should be: push(64-byte sig) + push(3-byte redeem)
        // Format: <65 (push op)> <64 bytes sig> <3 (push op)> <3 bytes redeem>
        // Total: 1 + 64 + 1 + 3 = 69 bytes
        if (assertEqual(
            sig_script.size(),
            69,
            "buildP2SHSignatureScript format",
            natEq,
            natToText
        )) {
            passed += 1;
        };

        // Print summary
        Debug.print("\n📊 Test Summary:");
        Debug.print("Passed: " # Nat.toText(passed) # "/" # Nat.toText(total));

        if (passed == total) {
            Debug.print("🎉 All tests passed!");
            "All tests passed ✅"
        } else {
            Debug.print("⚠️  Some tests failed");
            "Some tests failed ❌"
        }
    };
};
