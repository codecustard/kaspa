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
import Array "mo:base/Array";

import Wallet "../src/wallet";
import Errors "../src/errors";
import Types "../src/types";
import Address "../src/address";

import KRC20Types "../src/krc20/types";
import KRC20Operations "../src/krc20/operations";
import KRC20Builder "../src/krc20/builder";

persistent actor KRC20Example {

    // Initialize a mainnet wallet
    transient let wallet = Wallet.createMainnetWallet("dfx_test_key");

    // Store pending reveals (survives upgrades)
    private stable var pendingReveals : [(Text, [Nat8])] = [];  // (commit_tx_id, redeem_script)

    /// Get the canister's Kaspa address
    public func getAddress() : async Result.Result<Wallet.AddressInfo, Errors.KaspaError> {
        await wallet.generateAddress(null, null)
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

    // System functions
    system func preupgrade() {
        Debug.print("💾 Saving " # debug_show(pendingReveals.size()) # " pending reveals");
    };

    system func postupgrade() {
        Debug.print("♻️ Restored " # debug_show(pendingReveals.size()) # " pending reveals");
    };
};
