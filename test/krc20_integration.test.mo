import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Array "mo:base/Array";

import KRC20Types "../src/krc20/types";
import KRC20Operations "../src/krc20/operations";
import KRC20Builder "../src/krc20/builder";
import ScriptBuilder "../src/script_builder";
import Address "../src/address";
import Types "../src/types";

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
            Debug.print("❌ FAIL: " # message);
            Debug.print("  Expected: " # toText(expected));
            Debug.print("  Actual:   " # toText(actual));
            false
        }
    };

    private func textEq(a: Text, b: Text) : Bool { a == b };
    private func textToText(t: Text) : Text { t };
    private func natEq(a: Nat, b: Nat) : Bool { a == b };
    private func natToText(n: Nat) : Text { Nat.toText(n) };

    public func runTests() : async Text {
        Debug.print("🧪 Running KRC20 Integration Tests...");

        var passed : Nat = 0;
        var total : Nat = 0;

        // Test 1: Generate valid address first
        total += 1;
        Debug.print("\n🔧 Test 1: Generate valid Kaspa address");

        let test_pubkey = Array.freeze(Array.init<Nat8>(32, 0xAA));  // 32-byte Schnorr pubkey
        let test_addr_result = Address.generateAddress(Blob.fromArray(test_pubkey), 0);  // Schnorr

        var test_address = "";
        switch (test_addr_result) {
            case (#ok(info)) {
                test_address := info.address;
                Debug.print("  ✓ Generated address: " # test_address);
                passed += 1;
            };
            case (#err(e)) {
                Debug.print("  ✗ Failed to generate address: " # debug_show(e));
            };
        };

        // Test 2: Build data envelope
        total += 1;
        Debug.print("\n🔧 Test 2: Build data envelope");

        let deploy_params : KRC20Types.DeployMintParams = {
            tick = "TEST";
            max = "1000000000000000";
            lim = "10000000000";
            to = ?test_address;
            dec = ?8;
            pre = null;
        };

        let operation_json = KRC20Operations.formatDeployMint(deploy_params);
        let json_bytes = Blob.toArray(Text.encodeUtf8(operation_json));
        let envelope = ScriptBuilder.buildDataEnvelope("kasplex", json_bytes, []);

        // Check envelope contains the protocol identifier
        let envelope_hex = ScriptBuilder.bytesToHex(envelope);
        let contains_kasplex = Text.contains(envelope_hex, #text "6b617370");  // "kasp" in hex

        if (contains_kasplex) {
            Debug.print("  ✓ Envelope contains protocol identifier");
            passed += 1;
        } else {
            Debug.print("  ✗ Envelope missing protocol identifier");
        };

        // Test 3: Fee estimation
        total += 1;
        Debug.print("\n🔧 Test 3: Fee estimation");

        let (commit_fee, reveal_fee) = KRC20Builder.estimateFees(operation_json);

        if (commit_fee > 0 and reveal_fee > 0) {
            Debug.print("  ✓ Commit fee: " # debug_show(commit_fee) # " sompi");
            Debug.print("  ✓ Reveal fee: " # debug_show(reveal_fee) # " sompi");
            passed += 1;
        } else {
            Debug.print("  ✗ Invalid fee estimates");
        };

        // Test 5: P2SH address generation
        total += 1;
        Debug.print("\n🔧 Test 5: P2SH address generation");

        let script_hash = Array.freeze(Array.init<Nat8>(32, 0xAA));
        let p2sh_address = KRC20Builder.getP2SHAddress(2, script_hash, "kaspa");

        switch (p2sh_address) {
            case (#ok(addr)) {
                let has_prefix = Text.startsWith(addr, #text "kaspa:");
                if (has_prefix) {
                    Debug.print("  ✓ P2SH address generated: " # addr);
                    passed += 1;
                } else {
                    Debug.print("  ✗ Address missing kaspa: prefix");
                };
            };
            case (#err(e)) {
                Debug.print("  ✗ Failed to generate address: " # debug_show(e));
            };
        };

        // Test 6: Reveal outputs builder
        total += 1;
        Debug.print("\n🔧 Test 6: Build reveal outputs");

        let reveal_outputs = KRC20Builder.buildRevealOutputs(
            test_address,
            9000  // Amount after fees
        );

        switch (reveal_outputs) {
            case (#ok(outputs)) {
                if (outputs.size() == 1 and outputs[0].amount == 9000) {
                    Debug.print("  ✓ Reveal output built correctly");
                    passed += 1;
                } else {
                    Debug.print("  ✗ Incorrect reveal outputs");
                };
            };
            case (#err(e)) {
                Debug.print("  ✗ Failed to build reveal outputs: " # debug_show(e));
            };
        };

        // Test 7: Mint operation format
        total += 1;
        Debug.print("\n🔧 Test 7: Format mint operation");

        let mint_params : KRC20Types.MintParams = {
            tick = "TEST";
            to = null;
        };
        let mint_json = KRC20Operations.formatMint(mint_params);

        let valid_mint = Text.contains(mint_json, #text "\"op\":\"mint\"");
        if (valid_mint) {
            Debug.print("  ✓ Mint JSON: " # mint_json);
            passed += 1;
        } else {
            Debug.print("  ✗ Invalid mint JSON");
        };

        // Test 8: Transfer operation format
        total += 1;
        Debug.print("\n🔧 Test 8: Format transfer operation");

        let transfer_params : KRC20Types.TransferMintParams = {
            tick = "TEST";
            amt = "50000000000";
            to = test_address;
        };
        let transfer_json = KRC20Operations.formatTransferMint(transfer_params);

        let valid_transfer = Text.contains(transfer_json, #text "\"op\":\"transfer\"");
        if (valid_transfer) {
            Debug.print("  ✓ Transfer JSON: " # transfer_json);
            passed += 1;
        } else {
            Debug.print("  ✗ Invalid transfer JSON");
        };

        // Print summary
        Debug.print("\n📊 Test Summary:");
        Debug.print("Passed: " # Nat.toText(passed) # "/" # Nat.toText(total));

        if (passed == total) {
            Debug.print("🎉 All KRC20 integration tests passed!");
            "All tests passed ✅"
        } else {
            Debug.print("⚠️  Some tests failed");
            "Some tests failed ❌"
        }
    };
};
