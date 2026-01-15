/// KRC20 Token Example
///
/// This example demonstrates how to use the KRC20 library to deploy,
/// mint, and transfer tokens using the commit-reveal pattern.
///
/// Key concepts:
/// - Commit-Reveal: Each KRC20 operation requires 2 transactions
/// - P2SH Scripts: Data is embedded in Pay-to-Script-Hash outputs
/// - Threshold ECDSA: Uses IC's ECDSA for signing transactions
///
/// NOTE: This is a demonstration. For production use, you'll need to:
/// - Implement actual signing with IC ECDSA
/// - Add transaction broadcasting
/// - Handle confirmations properly
/// - Implement the complete reveal workflow

import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Error "mo:base/Error";

import Wallet "../src/wallet";
import Errors "../src/errors";
import Types "../src/types";
import Address "../src/address";
import ScriptBuilder "../src/script_builder";
import Sighash "../src/sighash";
import Transaction "../src/transaction";
import IC "mo:ic";

import KRC20Types "../src/krc20/types";
import KRC20Operations "../src/krc20/operations";
import KRC20Builder "../src/krc20/builder";

persistent actor KRC20Example {

    // Initialize a testnet wallet
    transient let wallet = Wallet.createTestnetWallet("dfx_test_key");

    // Store pending reveals (survives upgrades)
    private stable var pendingReveals : [(Text, [Nat8])] = [];  // (commit_tx_id, redeem_script)

    /// Get the canister's Kaspa address
    public func getAddress() : async Result.Result<Wallet.AddressInfo, Errors.KaspaError> {
        await wallet.generateAddress(null, null)
    };

    /// Consolidate UTXOs by sending all funds to self
    /// This is necessary when you have multiple small UTXOs and need one large one
    public func consolidateUTXOs(from_address: Text) : async Result.Result<Text, Errors.KaspaError> {
        // Send almost all funds to self (leaving enough for fee)
        let balance = switch (await wallet.getBalance(from_address)) {
            case (#ok(bal)) { bal.confirmed };
            case (#err(e)) { return #err(e) };
        };

        if (balance == 0) {
            return #err(#InsufficientFunds({ required = 1000; available = 0 }));
        };

        // Leave 1,000,000 sompi (0.01 KAS) for fees
        let fee_buffer: Nat64 = 1_000_000;
        let amount_to_send = if (balance > fee_buffer) { balance - fee_buffer } else { return #err(#InsufficientFunds({ required = fee_buffer; available = balance })) };

        switch (await wallet.sendTransaction(
            from_address,
            from_address,  // Send to self
            amount_to_send,
            null,  // Use default fee
            null   // Use default derivation path
        )) {
            case (#ok(result)) { #ok(result.transaction_id) };
            case (#err(e)) { #err(e) };
        }
    };

    /// Get balance of an address
    public func getBalance(address: Text) : async Result.Result<Wallet.Balance, Errors.KaspaError> {
        await wallet.getBalance(address)
    };

    /// Example 1: Build a KRC20 deploy operation
    ///
    /// This creates the commit transaction for deploying a token.
    /// After broadcasting, you must call revealOperation() to complete it.
    ///
    /// @param tick - Token ticker (4-6 letters)
    /// @param max_supply - Maximum supply as string
    /// @param mint_limit - Amount per mint as string
    /// @param decimals - Number of decimals (default: 8)
    /// @param from_address - Address to use for funding
    /// @return Commit transaction details and instructions
    public func buildDeployCommit(
        tick: Text,
        max_supply: Text,
        mint_limit: Text,
        decimals: ?Nat8,
        from_address: Text
    ) : async Result.Result<{
        operation_json: Text;
        commit_tx: Types.KaspaTransaction;
        redeem_script_hex: Text;
        instructions: Text;
    }, Errors.KaspaError> {

        Debug.print("🚀 Building deploy commit for: " # tick);

        // 1. Create deployment parameters
        let deploy_params : KRC20Types.DeployMintParams = {
            tick = tick;
            max = max_supply;
            lim = mint_limit;
            to = ?from_address;
            dec = decimals;
            pre = null;
        };

        // 2. Format the KRC20 operation JSON
        let operation_json = KRC20Operations.formatDeployMint(deploy_params);

        // 3. Get address info for public key
        let addressInfo = switch (await wallet.generateAddress(null, null)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        // 4. Get UTXO to fund the transaction
        let utxos = switch (await wallet.getUTXOs(from_address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 100000000000;  // 1000 KAS
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        let utxo = utxos[0];

        // 5. Build commit transaction
        let commit_result = KRC20Builder.buildCommit(
            addressInfo.public_key,
            operation_json,
            utxo,
            KRC20Builder.RECOMMENDED_COMMIT_AMOUNT,
            100000000000,  // 1000 KAS deploy fee
            from_address,
            true  // Use ECDSA
        );

        let commit_pair = switch (commit_result) {
            case (#ok(pair)) { pair };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("✅ Commit transaction built");
        Debug.print("📝 Operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            commit_tx = commit_pair.commitTx;
            redeem_script_hex = Address.hexFromArray(commit_pair.redeemScript);
            instructions = "1. Sign and broadcast the commit_tx\n2. Wait for confirmation\n3. Call revealOperation() with the commit TX ID";
        })
    };

    /// Example 2: Build a mint operation
    ///
    /// @param tick - Token ticker
    /// @param recipient - Optional recipient address
    /// @param from_address - Address to fund the mint
    public func buildMintCommit(
        tick: Text,
        recipient: ?Text,
        from_address: Text
    ) : async Result.Result<{
        operation_json: Text;
        instructions: Text;
    }, Errors.KaspaError> {

        let mint_params : KRC20Types.MintParams = {
            tick = tick;
            to = recipient;
        };

        let operation_json = KRC20Operations.formatMint(mint_params);

        Debug.print("💰 Mint operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            instructions = "Follow same commit-reveal pattern as deploy. Fee: 1 KAS";
        })
    };

    /// Example 3: Build a transfer operation
    ///
    /// @param tick - Token ticker
    /// @param amount - Amount to transfer (with decimals)
    /// @param to_address - Recipient address
    public func buildTransferCommit(
        tick: Text,
        amount: Text,
        to_address: Text
    ) : async Result.Result<{
        operation_json: Text;
        instructions: Text;
    }, Errors.KaspaError> {

        let transfer_params : KRC20Types.TransferMintParams = {
            tick = tick;
            amt = amount;
            to = to_address;
        };

        let operation_json = KRC20Operations.formatTransferMint(transfer_params);

        Debug.print("📤 Transfer operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            instructions = "Follow commit-reveal pattern. Fee: Network fees only";
        })
    };

    /// Example 4: Build a burn operation
    ///
    /// @param tick - Token ticker
    /// @param amount - Amount to burn (with decimals)
    public func buildBurnCommit(
        tick: Text,
        amount: Text
    ) : async Result.Result<{
        operation_json: Text;
        instructions: Text;
    }, Errors.KaspaError> {

        let burn_params : KRC20Types.BurnMintParams = {
            tick = tick;
            amt = amount;
        };

        let operation_json = KRC20Operations.formatBurnMint(burn_params);

        Debug.print("🔥 Burn operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            instructions = "Follow commit-reveal pattern. Fee: Network fees only";
        })
    };

    /// Example 5: Format a list (sell) operation
    ///
    /// @param tick - Token ticker (will be converted to lowercase)
    /// @param amount - Amount to list
    public func formatListOperation(
        tick: Text,
        amount: Text
    ) : async Text {
        let list_params : KRC20Types.ListParams = {
            tick = tick;
            amt = amount;
        };

        KRC20Operations.formatList(list_params)
    };

    /// Example 6: Format a send (buy) operation
    ///
    /// @param tick - Token ticker (will be converted to lowercase)
    public func formatSendOperation(tick: Text) : async Text {
        let send_params : KRC20Types.SendParams = {
            tick = tick;
        };

        KRC20Operations.formatSend(send_params)
    };

    /// Get P2SH address from script hash
    ///
    /// Useful for constructing reveal transactions
    public func getP2SHAddress(scriptHash: [Nat8]) : async Result.Result<Text, Errors.KaspaError> {
        KRC20Builder.getP2SHAddress(2, scriptHash, "kaspa")
    };

    /// Estimate fees for a KRC20 operation
    ///
    /// @param operation_json - The KRC20 operation JSON
    /// @return (commit_fee, reveal_fee) in sompi
    public func estimateFees(operation_json: Text) : async (Nat64, Nat64) {
        KRC20Builder.estimateFees(operation_json)
    };

    /// Store a pending reveal for later
    ///
    /// Call this after successfully broadcasting a commit transaction
    public func storePendingReveal(commit_tx_id: Text, redeem_script_hex: Text) : async () {
        let redeem_script = switch (Address.arrayFromHex(redeem_script_hex)) {
            case (#ok(bytes)) { bytes };
            case (#err(_)) { return };
        };

        pendingReveals := Array.append(
            pendingReveals,
            [(commit_tx_id, redeem_script)]
        );

        Debug.print("💾 Stored pending reveal for: " # commit_tx_id);
    };

    /// Get list of pending reveals
    public query func getPendingReveals() : async [(Text, Nat)] {
        Array.map<(Text, [Nat8]), (Text, Nat)>(
            pendingReveals,
            func(pair) { (pair.0, pair.1.size()) }
        )
    };

    /// Get a specific redeem script by commit TX ID
    public query func getRedeemScript(commit_tx_id: Text) : async ?Text {
        switch (Array.find<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 == commit_tx_id }
        )) {
            case (?pair) { ?Address.hexFromArray(pair.1) };
            case null { null };
        }
    };

    /// Clear a pending reveal after it's been broadcast
    public func clearPendingReveal(commit_tx_id: Text) : async () {
        pendingReveals := Array.filter<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 != commit_tx_id }
        );

        Debug.print("🗑️  Cleared pending reveal: " # commit_tx_id);
    };

    /// Build reveal transaction outputs
    ///
    /// Helper for constructing the reveal transaction
    public func buildRevealOutputs(
        recipient_address: Text,
        amount: Nat64
    ) : async Result.Result<[Types.TransactionOutput], Errors.KaspaError> {
        KRC20Builder.buildRevealOutputs(recipient_address, amount)
    };

    /// FULL BROADCAST: Deploy token with automatic commit transaction broadcast
    ///
    /// This builds the commit transaction, signs it, and broadcasts it to the network.
    /// You must manually call revealDeployOperation() after the commit confirms.
    ///
    /// @param tick - Token ticker (4-6 letters)
    /// @param max_supply - Maximum supply as string
    /// @param mint_limit - Amount per mint as string
    /// @param decimals - Number of decimals (default: 8)
    /// @param from_address - Address to use for funding
    /// @return Commit transaction ID and redeem script
    public func deployTokenWithBroadcast(
        tick: Text,
        max_supply: Text,
        mint_limit: Text,
        decimals: ?Nat8,
        from_address: Text
    ) : async Result.Result<{
        commit_tx_id: Text;
        redeem_script_hex: Text;
        p2sh_address: Text;
        instructions: Text;
    }, Errors.KaspaError> {

        Debug.print("🚀 Deploying token with broadcast: " # tick);

        // 1. Create deployment parameters
        let deploy_params : KRC20Types.DeployMintParams = {
            tick = tick;
            max = max_supply;
            lim = mint_limit;
            to = ?from_address;
            dec = decimals;
            pre = null;
        };

        // 2. Format the KRC20 operation JSON
        let operation_json = KRC20Operations.formatDeployMint(deploy_params);
        Debug.print("📝 Operation: " # operation_json);

        // 3. Get address info for public key (use canister's address, not user's)
        let addressInfo = switch (await wallet.generateAddress(null, null)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        // 4. Get UTXOs to fund the transaction (fetch from canister's address)
        let utxos = switch (await wallet.getUTXOs(addressInfo.address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 100000000000;  // 1000 KAS
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        // 5. Calculate total available
        let total_available = Array.foldLeft<Types.UTXO, Nat64>(
            utxos, 0, func(acc, utxo) { acc + utxo.amount }
        );

        let deploy_fee: Nat64 = 100000000000;  // 1000 KAS
        let commit_amount = KRC20Builder.MIN_COMMIT_AMOUNT;  // Use minimum to save on fees
        let required = deploy_fee + commit_amount;  // Wallet handles the fee internally

        if (total_available < required) {
            return #err(#InsufficientFunds({
                required = required;
                available = total_available;
            }));
        };

        // 6. Select UTXO with enough funds or combine multiple UTXOs
        // Find a UTXO with enough balance, or use the largest one
        var selected_utxo = utxos[0];
        let total_needed = deploy_fee + commit_amount;

        label utxo_loop for (utxo in utxos.vals()) {
            if (utxo.amount >= total_needed) {
                selected_utxo := utxo;
                break utxo_loop;
            };
            // Use the largest UTXO if none are big enough
            if (utxo.amount > selected_utxo.amount) {
                selected_utxo := utxo;
            };
        };

        Debug.print("📊 Selected UTXO amount: " # debug_show(selected_utxo.amount));
        Debug.print("💰 Commit amount: " # debug_show(commit_amount));
        Debug.print("💸 Deploy fee: " # debug_show(deploy_fee));
        Debug.print("📦 Total UTXOs available: " # debug_show(utxos.size()));

        // Check if we need to consolidate UTXOs first
        if (selected_utxo.amount < total_needed) {
            Debug.print("⚠️  Single UTXO insufficient. Please consolidate UTXOs first.");
            return #err(#InsufficientFunds({
                required = total_needed;
                available = selected_utxo.amount;
            }));
        };

        let commit_result = KRC20Builder.buildCommit(
            addressInfo.public_key,
            operation_json,
            selected_utxo,
            commit_amount,
            deploy_fee,
            addressInfo.address,  // Use canister's address for change
            true  // Use ECDSA
        );

        let commit_pair = switch (commit_result) {
            case (#ok(pair)) {
                Debug.print("🔧 Commit TX inputs: " # debug_show(pair.commitTx.inputs.size()));
                Debug.print("🔧 Commit TX outputs: " # debug_show(pair.commitTx.outputs.size()));
                pair
            };
            case (#err(e)) { return #err(e) };
        };

        // 7. Get P2SH address from script hash (use same prefix as canister's address)
        let prefix = if (Text.startsWith(addressInfo.address, #text("kaspatest:"))) {
            "kaspatest"
        } else {
            "kaspa"
        };

        let p2sh_address = switch (KRC20Builder.getP2SHAddress(2, commit_pair.p2shScriptHash, prefix)) {
            case (#ok(addr)) { addr };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("🔐 P2SH Address: " # p2sh_address);

        // 8. Sign and broadcast the commit transaction
        // Use the wallet's signAndBroadcastTransaction for the pre-built P2SH commit
        let commit_tx_id = switch (await wallet.signAndBroadcastTransaction(
            commit_pair.commitTx,
            [selected_utxo],  // Must use the same UTXO we built the transaction with!
            null  // Use default derivation path
        )) {
            case (#ok(tx_id)) { tx_id };
            case (#err(e)) { return #err(e) };
        };

        let redeem_script_hex = Address.hexFromArray(commit_pair.redeemScript);

        // 9. Store pending reveal
        pendingReveals := Array.append(
            pendingReveals,
            [(commit_tx_id, commit_pair.redeemScript)]
        );

        Debug.print("✅ Commit broadcast! TX ID: " # commit_tx_id);
        Debug.print("💾 Stored redeem script for reveal");

        #ok({
            commit_tx_id = commit_tx_id;
            redeem_script_hex = redeem_script_hex;
            p2sh_address = p2sh_address;
            instructions = "Commit TX broadcast! Wait for confirmation, then call revealDeployOperation(\"" # commit_tx_id # "\")";
        })
    };

    /// FULL BROADCAST: Reveal operation after commit confirms
    ///
    /// This builds the reveal transaction, signs it, and broadcasts it.
    /// Call this after the commit transaction has confirmed.
    ///
    /// @param commit_tx_id - Transaction ID of the commit
    /// @param recipient_address - Where to send the remaining funds
    /// @return Reveal transaction ID
    public func revealOperation(
        commit_tx_id: Text,
        recipient_address: Text
    ) : async Result.Result<{
        reveal_tx_id: Text;
        message: Text;
    }, Errors.KaspaError> {

        Debug.print("🔓 Revealing operation for commit: " # commit_tx_id);

        // 1. Get stored redeem script
        let redeem_script = switch (Array.find<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 == commit_tx_id }
        )) {
            case (?pair) { pair.1 };
            case null {
                return #err(#InvalidTransaction({
                    message = "No pending reveal found for commit TX: " # commit_tx_id;
                }));
            };
        };

        Debug.print("📜 Found redeem script, length: " # debug_show(redeem_script.size()));
        Debug.print("📜 Redeem script (hex): " # Address.hexFromArray(redeem_script));
        // Print first few bytes to verify structure
        if (redeem_script.size() >= 3) {
            Debug.print("📜 Redeem script starts with: " # debug_show([redeem_script[0], redeem_script[1], redeem_script[2]]));
        };

        // 2. Get P2SH address from the redeem script hash
        let scriptHash = ScriptBuilder.hashRedeemScript(redeem_script);
        let p2sh_address = switch (KRC20Builder.getP2SHAddress(2, scriptHash, "kaspatest")) {
            case (#ok(addr)) { addr };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("🏠 P2SH Address: " # p2sh_address);

        // 3. Get UTXO from P2SH address
        let p2sh_utxos = switch (await wallet.getUTXOs(p2sh_address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 1;
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        let p2sh_utxo = p2sh_utxos[0];
        Debug.print("💰 P2SH UTXO amount: " # debug_show(p2sh_utxo.amount));
        Debug.print("📍 P2SH UTXO txid: " # p2sh_utxo.transactionId);
        Debug.print("📍 P2SH UTXO index: " # debug_show(p2sh_utxo.index));
        Debug.print("📜 P2SH UTXO scriptPubKey: " # p2sh_utxo.scriptPublicKey);

        // 4. Calculate reveal amount (P2SH amount minus fee)
        // KRC20 deploy requires 1000 KAS protocol fee on reveal
        let reveal_fee: Nat64 = 100_000_000_000;  // 1000 KAS deploy fee
        if (p2sh_utxo.amount <= reveal_fee) {
            return #err(#InsufficientFunds({
                required = reveal_fee + 1;
                available = p2sh_utxo.amount;
            }));
        };
        let reveal_amount = p2sh_utxo.amount - reveal_fee;

        // 5. Build reveal outputs
        let recipient_info = switch (Address.decodeAddress(recipient_address)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        let outputs: [Types.TransactionOutput] = [{
            amount = reveal_amount;
            scriptPublicKey = {
                version = 0 : Nat16;
                scriptPublicKey = recipient_info.script_public_key;
            };
        }];

        // 6. Build the reveal transaction
        // Use the actual UTXO index from what we fetched (not hardcoded)
        let reveal_tx: Types.KaspaTransaction = {
            version = 0;
            inputs = [{
                previousOutpoint = {
                    transactionId = p2sh_utxo.transactionId;  // Use UTXO's txid
                    index = p2sh_utxo.index;  // Use actual index from UTXO
                };
                signatureScript = "";  // Will be filled after signing
                sequence = 0;
                sigOpCount = 1;
            }];
            outputs = outputs;
            lockTime = 0;
            subnetworkId = "0000000000000000000000000000000000000000";
            gas = 0;
            payload = "";
        };

        Debug.print("🔧 Reveal TX input txid: " # p2sh_utxo.transactionId);
        Debug.print("🔧 Reveal TX input index: " # debug_show(p2sh_utxo.index));

        // 7. Sign the reveal transaction (P2SH spending)
        // For P2SH, we need to sign with the redeem script's public key
        // and include the redeem script in the signature script
        let signed_reveal = switch (await signP2SHReveal(reveal_tx, p2sh_utxo, redeem_script)) {
            case (#ok(signed)) { signed };
            case (#err(e)) { return #err(e) };
        };

        // 8. Broadcast the reveal transaction
        let serialized = Transaction.serialize_transaction(signed_reveal);
        Debug.print("📡 Broadcasting reveal: " # serialized);

        let reveal_tx_id = switch (await wallet.broadcastSerializedTransaction(serialized)) {
            case (#ok(tx_id)) { tx_id };
            case (#err(e)) { return #err(e) };
        };

        // 9. Clear the pending reveal
        pendingReveals := Array.filter<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 != commit_tx_id }
        );

        Debug.print("✅ Reveal broadcast! TX ID: " # reveal_tx_id);

        #ok({
            reveal_tx_id = reveal_tx_id;
            message = "Token deployment revealed! Check KRC20 explorer.";
        })
    };

    // Helper function to sign P2SH reveal transaction
    private func signP2SHReveal(
        tx: Types.KaspaTransaction,
        utxo: Types.UTXO,
        redeem_script: [Nat8]
    ) : async Result.Result<Types.KaspaTransaction, Errors.KaspaError> {

        // Calculate sighash for the P2SH input
        let reused_values: Sighash.SighashReusedValues = {
            var previousOutputsHash = null;
            var sequencesHash = null;
            var sigOpCountsHash = null;
            var outputsHash = null;
            var payloadHash = null;
        };

        // Try using the actual P2SH scriptPubKey for sighash (not the redeem script)
        // The P2SH scriptPubKey is: OP_BLAKE2B <hash> OP_EQUAL
        // This is stored in utxo.scriptPublicKey

        Debug.print("🔧 Using P2SH scriptPubKey for sighash: " # utxo.scriptPublicKey);

        let p2sh_utxo_for_sighash: Types.UTXO = {
            transactionId = utxo.transactionId;
            index = utxo.index;
            amount = utxo.amount;
            scriptPublicKey = utxo.scriptPublicKey;  // Use actual P2SH script
            scriptVersion = utxo.scriptVersion;
            address = utxo.address;
        };

        Debug.print("🔢 UTXO for sighash - scriptPublicKey: " # p2sh_utxo_for_sighash.scriptPublicKey);
        Debug.print("🔢 UTXO for sighash - amount: " # debug_show(p2sh_utxo_for_sighash.amount));
        Debug.print("🔢 UTXO for sighash - scriptVersion: " # debug_show(p2sh_utxo_for_sighash.scriptVersion));

        let sighash = switch (Sighash.calculate_sighash_ecdsa(tx, 0, p2sh_utxo_for_sighash, Sighash.SigHashAll, reused_values)) {
            case (null) {
                return #err(#CryptographicError({ message = "Failed to calculate P2SH sighash" }));
            };
            case (?hash) {
                Debug.print("🔏 Sighash (hex): " # Address.hexFromArray(hash));
                hash
            };
        };

        // Sign with IC ECDSA
        try {
            let signature_result = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
                message_hash = Blob.fromArray(sighash);
                derivation_path = [];
                key_id = { name = "dfx_test_key"; curve = #secp256k1 };
            });

            let signature_bytes = Blob.toArray(signature_result.signature);
            Debug.print("✍️ Raw signature length: " # debug_show(signature_bytes.size()));
            Debug.print("✍️ Raw signature (hex): " # Address.hexFromArray(signature_bytes));

            let sighash_type: Nat8 = 0x01;  // SigHashAll

            // Signature with hashtype appended (as required by Bitcoin/Kaspa scripts)
            let sig_with_hashtype = Array.append(signature_bytes, [sighash_type]);

            // Build P2SH signature script using the helper function
            let script_bytes = ScriptBuilder.buildP2SHSignatureScript(
                sig_with_hashtype,
                redeem_script
            );

            Debug.print("🔏 Signature script length: " # debug_show(script_bytes.size()));
            Debug.print("🔏 Signature length: " # debug_show(sig_with_hashtype.size()));
            Debug.print("🔏 Redeem script length: " # debug_show(redeem_script.size()));

            let signature_script = Address.hexFromArray(script_bytes);

            // Update transaction with signature script
            let signed_input: Types.TransactionInput = {
                previousOutpoint = tx.inputs[0].previousOutpoint;
                signatureScript = signature_script;
                sequence = tx.inputs[0].sequence;
                sigOpCount = tx.inputs[0].sigOpCount;
            };

            #ok({
                version = tx.version;
                inputs = [signed_input];
                outputs = tx.outputs;
                lockTime = tx.lockTime;
                subnetworkId = tx.subnetworkId;
                gas = tx.gas;
                payload = tx.payload;
            })
        } catch (e) {
            #err(#CryptographicError({ message = "Failed to sign P2SH reveal: " # Error.message(e) }))
        }
    };

    // System functions
    system func preupgrade() {
        Debug.print("💾 Saving " # debug_show(pendingReveals.size()) # " pending reveals");
    };

    system func postupgrade() {
        Debug.print("♻️ Restored " # debug_show(pendingReveals.size()) # " pending reveals");
    };
};
