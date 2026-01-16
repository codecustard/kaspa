/// Test file for KRC20 mint operations
///
/// Run with: mops test krc20_mint.test.mo
///
/// These tests verify:
/// - Mint JSON formatting
/// - Mint parameter validation
/// - Commit transaction structure
/// - Fee calculations

import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Char "mo:base/Char";

import KRC20Types "../src/krc20/types";
import KRC20Operations "../src/krc20/operations";
import KRC20Builder "../src/krc20/builder";

// Simple test helpers
func assertEqual<T>(actual: T, expected: T, toString: (T) -> Text, testName: Text) {
    let actualStr = toString(actual);
    let expectedStr = toString(expected);
    if (actualStr == expectedStr) {
        Debug.print("✅ " # testName);
    } else {
        Debug.print("❌ " # testName);
        Debug.print("   Expected: " # expectedStr);
        Debug.print("   Got: " # actualStr);
    };
};

func assertTextEqual(actual: Text, expected: Text, testName: Text) {
    assertEqual<Text>(actual, expected, func(t) { t }, testName);
};

func assertContains(text: Text, substring: Text, testName: Text) {
    if (Text.contains(text, #text(substring))) {
        Debug.print("✅ " # testName);
    } else {
        Debug.print("❌ " # testName);
        Debug.print("   Expected to contain: " # substring);
        Debug.print("   In text: " # text);
    };
};

// Test 1: Format mint operation with recipient
Debug.print("\n🧪 Test: Format mint operation with recipient");
let mint_params_1 : KRC20Types.MintParams = {
    tick = "ICWIN";
    to = ?"kaspatest:qzk3xkr8mhgf7kd5x9p2ycv8w4h6n5j7m8l9k0p1q2r3s4t5u6v7w8x9y0z1a2b3";
};
let mint_json_1 = KRC20Operations.formatMint(mint_params_1);
assertContains(mint_json_1, "\"p\":\"krc-20\"", "Contains protocol");
assertContains(mint_json_1, "\"op\":\"mint\"", "Contains operation");
assertContains(mint_json_1, "\"tick\":\"ICWIN\"", "Contains tick (case preserved)");
assertContains(mint_json_1, "\"to\":\"kaspatest:", "Contains recipient address");
Debug.print("   JSON: " # mint_json_1);

// Test 2: Format mint operation without recipient (to deployer)
Debug.print("\n🧪 Test: Format mint operation without recipient");
let mint_params_2 : KRC20Types.MintParams = {
    tick = "TEST";
    to = null;
};
let mint_json_2 = KRC20Operations.formatMint(mint_params_2);
assertContains(mint_json_2, "\"op\":\"mint\"", "Contains operation");
assertContains(mint_json_2, "\"tick\":\"TEST\"", "Contains tick (case preserved)");
// When 'to' is null, it should not be in the JSON (mints to deployer)
if (not Text.contains(mint_json_2, #text("\"to\":"))) {
    Debug.print("✅ No 'to' field when recipient is null");
} else {
    Debug.print("❌ Should not have 'to' field when recipient is null");
    Debug.print("   JSON: " # mint_json_2);
};
Debug.print("   JSON: " # mint_json_2);

// Test 3: Verify mint fee estimation
Debug.print("\n🧪 Test: Estimate mint fees");
let (commit_fee, reveal_fee) = KRC20Builder.estimateFees(mint_json_1);
Debug.print("   Commit fee: " # debug_show(commit_fee) # " sompi");
Debug.print("   Reveal fee: " # debug_show(reveal_fee) # " sompi");
// Mint should be 1 KAS (100,000,000 sompi)
if (commit_fee == 100_000_000 or commit_fee == 0) {
    Debug.print("✅ Mint commit fee is reasonable (1 KAS or estimated)");
} else {
    Debug.print("⚠️  Unexpected commit fee: " # debug_show(commit_fee));
};

// Test 4: Format different tickers
Debug.print("\n🧪 Test: Format mint with various tickers");
let tickers = ["ABCD", "ABCDE", "ABCDEF", "KASPA"];
for (tick in tickers.vals()) {
    let params : KRC20Types.MintParams = {
        tick = tick;
        to = null;
    };
    let json = KRC20Operations.formatMint(params);
    // Mint operations preserve case (only list/send operations lowercase)
    assertContains(json, "\"tick\":\"" # tick # "\"", "Ticker " # tick # " formatted correctly");
};

// Test 5: Verify minimum commit amount
Debug.print("\n🧪 Test: Minimum commit amount constant");
let min_commit = KRC20Builder.MIN_COMMIT_AMOUNT;
Debug.print("   MIN_COMMIT_AMOUNT: " # debug_show(min_commit) # " sompi");
if (min_commit >= 1000) {  // Should be at least dust threshold
    Debug.print("✅ MIN_COMMIT_AMOUNT is above dust threshold");
} else {
    Debug.print("❌ MIN_COMMIT_AMOUNT is too low: " # debug_show(min_commit));
};

// Test 6: Verify recommended commit amount
Debug.print("\n🧪 Test: Recommended commit amount constant");
let rec_commit = KRC20Builder.RECOMMENDED_COMMIT_AMOUNT;
Debug.print("   RECOMMENDED_COMMIT_AMOUNT: " # debug_show(rec_commit) # " sompi");
if (rec_commit >= min_commit) {
    Debug.print("✅ RECOMMENDED_COMMIT_AMOUNT >= MIN_COMMIT_AMOUNT");
} else {
    Debug.print("❌ RECOMMENDED_COMMIT_AMOUNT is less than MIN_COMMIT_AMOUNT");
};

Debug.print("\n✨ Mint operation tests complete!\n");
Debug.print("📝 Note: To test actual commit/reveal transactions, use:");
Debug.print("   dfx canister call krc20_example mintTokenWithBroadcast '(\"TICKER\", null)'");
Debug.print("   dfx canister call krc20_example revealOperation '(\"commit_tx_id\", \"address\")'");
Debug.print("\n📝 Note: API helper functions have been updated:");
Debug.print("   - OLD: getAddressKRC20Balance() → NEW: getKRC20TokenBalance()");
Debug.print("   - NEW: getKRC20TokenList() for all tokens");
Debug.print("\n📝 To test balances:");
Debug.print("   dfx canister call krc20_example getKRC20TokenBalance '(\"ADDRESS\", \"ICWIN\")'");
Debug.print("   dfx canister call krc20_example getKRC20TokenList '(\"ADDRESS\")'");
