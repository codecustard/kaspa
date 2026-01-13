import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

import KRC20Operations "../src/krc20/operations";
import KRC20Types "../src/krc20/types";

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

    public func runTests() : async Text {
        Debug.print("🧪 Running KRC20 Operations Tests...");

        var passed : Nat = 0;
        var total : Nat = 0;

        // Test 1: formatDeployMint - basic fields
        total += 1;
        let deploy_params : KRC20Types.DeployMintParams = {
            tick = "KASP";
            max = "2100000000000000";
            lim = "100000000000";
            to = null;
            dec = null;
            pre = null;
        };
        let deploy_json = KRC20Operations.formatDeployMint(deploy_params);
        let expected_deploy = "{\"p\":\"krc-20\",\"op\":\"deploy\",\"tick\":\"KASP\",\"max\":\"2100000000000000\",\"lim\":\"100000000000\"}";

        if (assertEqual(
            deploy_json,
            expected_deploy,
            "formatDeployMint basic fields",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 2: formatDeployMint - with optional fields
        total += 1;
        let deploy_params_full : KRC20Types.DeployMintParams = {
            tick = "TEST";
            max = "1000000";
            lim = "1000";
            to = ?"kaspa:qz0000000000000000000000000000000000000000000000000000000000000000";
            dec = ?8;
            pre = ?"500000";
        };
        let deploy_json_full = KRC20Operations.formatDeployMint(deploy_params_full);

        // Check it includes all fields
        let includes_to = Text.contains(deploy_json_full, #text "\"to\":\"kaspa:");
        let includes_dec = Text.contains(deploy_json_full, #text "\"dec\":8");
        let includes_pre = Text.contains(deploy_json_full, #text "\"pre\":\"500000\"");
        let all_optional_fields = includes_to and includes_dec and includes_pre;

        if (all_optional_fields) {
            Debug.print("✅ PASS: formatDeployMint includes all optional fields");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: formatDeployMint should include all optional fields");
        };

        // Test 3: formatMint
        total += 1;
        let mint_params : KRC20Types.MintParams = {
            tick = "KASP";
            to = null;
        };
        let mint_json = KRC20Operations.formatMint(mint_params);
        let expected_mint = "{\"p\":\"krc-20\",\"op\":\"mint\",\"tick\":\"KASP\"}";

        if (assertEqual(
            mint_json,
            expected_mint,
            "formatMint basic",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 4: formatMint with recipient
        total += 1;
        let mint_params_to : KRC20Types.MintParams = {
            tick = "KASP";
            to = ?"kaspa:qz0000000000000000000000000000000000000000000000000000000000000000";
        };
        let mint_json_to = KRC20Operations.formatMint(mint_params_to);

        let mint_includes_to = Text.contains(mint_json_to, #text "\"to\":\"kaspa:");
        if (mint_includes_to) {
            Debug.print("✅ PASS: formatMint includes recipient");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: formatMint should include recipient");
        };

        // Test 5: formatTransferMint
        total += 1;
        let transfer_params : KRC20Types.TransferMintParams = {
            tick = "KASP";
            amt = "100000000";
            to = "kaspa:qz0000000000000000000000000000000000000000000000000000000000000000";
        };
        let transfer_json = KRC20Operations.formatTransferMint(transfer_params);
        let expected_transfer = "{\"p\":\"krc-20\",\"op\":\"transfer\",\"tick\":\"KASP\",\"amt\":\"100000000\",\"to\":\"kaspa:qz0000000000000000000000000000000000000000000000000000000000000000\"}";

        if (assertEqual(
            transfer_json,
            expected_transfer,
            "formatTransferMint",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 6: formatBurnMint
        total += 1;
        let burn_params : KRC20Types.BurnMintParams = {
            tick = "KASP";
            amt = "6600000000";
        };
        let burn_json = KRC20Operations.formatBurnMint(burn_params);
        let expected_burn = "{\"p\":\"krc-20\",\"op\":\"burn\",\"tick\":\"KASP\",\"amt\":\"6600000000\"}";

        if (assertEqual(
            burn_json,
            expected_burn,
            "formatBurnMint",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 7: formatList
        total += 1;
        let list_params : KRC20Types.ListParams = {
            tick = "TEST";  // Mixed case
            amt = "292960000000";
        };
        let list_json = KRC20Operations.formatList(list_params);
        let expected_list = "{\"p\":\"krc-20\",\"op\":\"list\",\"tick\":\"test\",\"amt\":\"292960000000\"}";

        if (assertEqual(
            list_json,
            expected_list,
            "formatList converts tick to lowercase",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 8: formatSend
        total += 1;
        let send_params : KRC20Types.SendParams = {
            tick = "TEST";  // Mixed case
        };
        let send_json = KRC20Operations.formatSend(send_params);
        let expected_send = "{\"p\":\"krc-20\",\"op\":\"send\",\"tick\":\"test\"}";

        if (assertEqual(
            send_json,
            expected_send,
            "formatSend converts tick to lowercase",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 9: No spaces in JSON
        total += 1;
        let deploy_no_spaces = not Text.contains(deploy_json, #text " ");
        let mint_no_spaces = not Text.contains(mint_json, #text " ");
        let transfer_no_spaces = not Text.contains(transfer_json, #text " ");

        if (deploy_no_spaces and mint_no_spaces and transfer_no_spaces) {
            Debug.print("✅ PASS: JSON outputs contain no spaces");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: JSON outputs should not contain spaces");
        };

        // Test 10: formatDeployIssue
        total += 1;
        let deploy_issue_params : KRC20Types.DeployIssueParams = {
            name = "MYTOKEN";
            max = "1000000000";
            mod = "issue";
            to = null;
            dec = null;
            pre = null;
        };
        let deploy_issue_json = KRC20Operations.formatDeployIssue(deploy_issue_params);

        let includes_mod = Text.contains(deploy_issue_json, #text "\"mod\":\"issue\"");
        let includes_name = Text.contains(deploy_issue_json, #text "\"name\":\"MYTOKEN\"");

        if (includes_mod and includes_name) {
            Debug.print("✅ PASS: formatDeployIssue includes mod and name");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: formatDeployIssue should include mod and name fields");
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
