import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import Nat16 "mo:base/Nat16";
import Text "mo:base/Text";
import Result "mo:base/Result";

import Json "mo:json";
import IC "mo:ic";

import Errors "errors";
import Validation "validation";
import Address "address";
import Types "types";
import Sighash "sighash";
import Transaction "transaction";
import Constants "constants";

module {

    public type Result<T> = Result.Result<T, Errors.KaspaError>;

    // Wallet configuration
    public type WalletConfig = {
        key_name: Text;
        api_host: Text;
        network: Text; // "mainnet" or "testnet"
        max_fee: Nat64;
        default_fee_rate: Nat64; // sompi per byte
    };

    // UTXO with additional metadata
    public type ExtendedUTXO = {
        utxo: Types.UTXO;
        confirmations: Nat;
        is_coinbase: Bool;
        maturity: ?Nat64; // Block height when UTXO becomes spendable
    };

    // Transaction result
    public type TransactionResult = {
        transaction_id: Text;
        serialized_tx: Text;
        fee_paid: Nat64;
        inputs_used: [Types.UTXO];
        outputs_created: [Types.TransactionOutput];
    };

    // Balance information
    public type Balance = {
        confirmed: Nat64;
        unconfirmed: Nat64;
        immature: Nat64; // Coinbase outputs that haven't matured
        total: Nat64;
    };

    // Address generation info
    public type AddressInfo = {
        address: Text;
        derivation_path: Text;
        addr_type: Nat;
        public_key: [Nat8];
        script_public_key: Text;
    };

    // Production wallet actor
    public class Wallet(config: WalletConfig) {

        // Validate configuration
        private func validateConfig() : Result<()> {
            if (Text.size(config.key_name) == 0) {
                return #err(Errors.internalError("Key name cannot be empty"));
            };
            if (Text.size(config.api_host) == 0) {
                return #err(Errors.internalError("API host cannot be empty"));
            };
            if (config.network != "mainnet" and config.network != "testnet") {
                return #err(Errors.internalError("Network must be 'mainnet' or 'testnet'"));
            };
            #ok(())
        };

        // Generate address with derivation path
        public func generateAddress(derivation_path: ?Text, addr_type: ?Nat) : async Result<AddressInfo> {
            let path = switch (derivation_path) {
                case (null) { "" };
                case (?p) {
                    switch (Validation.validateDerivationPath(p)) {
                        case (#err(error)) { return #err(error) };
                        case (#ok(validated_path)) { validated_path };
                    };
                };
            };

            let address_type = switch (addr_type) {
                case (null) { Constants.ECDSA }; // Default to ECDSA
                case (?t) { t };
            };

            if (address_type != Constants.SCHNORR and address_type != Constants.ECDSA) {
                return #err(Errors.validationError("Unsupported address type: " # debug_show(address_type)));
            };

            try {
                let derivation_blobs = parseDerivationPath(path);
                switch (derivation_blobs) {
                    case (#err(error)) { return #err(error) };
                    case (#ok(blobs)) {

                        let pk_result = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
                            canister_id = null;
                            derivation_path = blobs;
                            key_id = { name = config.key_name; curve = #secp256k1 };
                        });

                        let pubkey_bytes = Blob.toArray(pk_result.public_key);

                        // Use network-specific prefix
                        let prefix = if (config.network == "testnet") {
                            "kaspatest"
                        } else {
                            "kaspa"
                        };

                        switch (Address.generateAddressWithPrefix(pk_result.public_key, address_type, prefix)) {
                            case (#err(error)) { #err(error) };
                            case (#ok(addr_info)) {
                                #ok({
                                    address = addr_info.address;
                                    derivation_path = path;
                                    addr_type = address_type;
                                    public_key = pubkey_bytes;
                                    script_public_key = addr_info.script_public_key;
                                })
                            };
                        };
                    };
                };
            } catch (e) {
                #err(Errors.cryptographicError("Failed to generate address: " # Error.message(e)))
            }
        };

        // Get balance for an address
        public func getBalance(address: Text) : async Result<Balance> {
            switch (Validation.validateAddress(address)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {

                    switch (await fetchUTXOs(address)) {
                        case (#err(error)) { return #err(error) };
                        case (#ok(utxos)) {
                            var confirmed: Nat64 = 0;
                            var unconfirmed: Nat64 = 0;
                            var immature: Nat64 = 0;

                            for (extended_utxo in utxos.vals()) {
                                let amount = extended_utxo.utxo.amount;
                                if (extended_utxo.is_coinbase and extended_utxo.confirmations < 100) {
                                    immature += amount;
                                } else if (extended_utxo.confirmations >= 1) {
                                    confirmed += amount;
                                } else {
                                    unconfirmed += amount;
                                };
                            };

                            let total = confirmed + unconfirmed + immature;
                            #ok({
                                confirmed = confirmed;
                                unconfirmed = unconfirmed;
                                immature = immature;
                                total = total;
                            })
                        };
                    };
                };
            };
        };

        // Send transaction with comprehensive validation and broadcasting
        public func sendTransaction(
            from_address: Text,
            to_address: Text,
            amount: Nat64,
            fee: ?Nat64,
            derivation_path: ?Text
        ) : async Result<TransactionResult> {

            // Validate inputs
            switch (Validation.validateAddress(from_address)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {};
            };

            switch (Validation.validateAddress(to_address)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {};
            };

            switch (Validation.validateAmount(amount, true)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {};
            };

            let transaction_fee = switch (fee) {
                case (null) { estimateTransactionFee(1, 2) }; // 1 input, 2 outputs
                case (?f) {
                    switch (Validation.validateFee(f)) {
                        case (#err(error)) { return #err(error) };
                        case (#ok(validated_fee)) { validated_fee };
                    };
                };
            };

            if (transaction_fee > config.max_fee) {
                return #err(Errors.validationError(
                    "Fee " # debug_show(transaction_fee) #
                    " exceeds maximum allowed fee " # debug_show(config.max_fee)
                ));
            };

            // Get UTXOs and select coins
            switch (await selectCoinsForTransaction(from_address, amount, transaction_fee)) {
                case (#err(error)) { return #err(error) };
                case (#ok(selected_utxos)) {

                    // Get recipient and change script public keys
                    switch (Address.decodeAddress(to_address)) {
                        case (#err(error)) { return #err(error) };
                        case (#ok(recipient_info)) {

                            switch (Address.decodeAddress(from_address)) {
                                case (#err(error)) { return #err(error) };
                                case (#ok(change_info)) {

                                    // Build transaction
                                    let total_input = Array.foldLeft<Types.UTXO, Nat64>(
                                        selected_utxos, 0, func(acc, utxo) { acc + utxo.amount }
                                    );

                                    let change_amount = total_input - amount - transaction_fee;
                                    let outputs = if (change_amount >= Constants.DUST_THRESHOLD) {
                                        [
                                            {
                                                amount = amount;
                                                scriptPublicKey = {
                                                    version = 0 : Nat16;
                                                    scriptPublicKey = recipient_info.script_public_key;
                                                };
                                            },
                                            {
                                                amount = change_amount;
                                                scriptPublicKey = {
                                                    version = 0 : Nat16;
                                                    scriptPublicKey = change_info.script_public_key;
                                                };
                                            }
                                        ]
                                    } else {
                                        [
                                            {
                                                amount = amount;
                                                scriptPublicKey = {
                                                    version = 0 : Nat16;
                                                    scriptPublicKey = recipient_info.script_public_key;
                                                };
                                            }
                                        ]
                                    };

                                    let inputs = Array.map<Types.UTXO, Types.TransactionInput>(
                                        selected_utxos,
                                        func(utxo) {
                                            {
                                                previousOutpoint = {
                                                    transactionId = utxo.transactionId;
                                                    index = utxo.index;
                                                };
                                                signatureScript = "";
                                                sequence = 0;
                                                sigOpCount = 1;
                                            }
                                        }
                                    );

                                    let unsigned_tx : Types.KaspaTransaction = {
                                        version = 0;
                                        inputs = inputs;
                                        outputs = outputs;
                                        lockTime = 0;
                                        subnetworkId = "0000000000000000000000000000000000000000";
                                        gas = 0;
                                        payload = "";
                                    };

                                    // Sign transaction
                                    switch (await signTransaction(unsigned_tx, selected_utxos, derivation_path)) {
                                        case (#err(error)) { return #err(error) };
                                        case (#ok(signed_tx)) {
                                            let serialized = Transaction.serialize_transaction(signed_tx);

                                            // Broadcast transaction
                                            switch (await broadcastTransaction(serialized)) {
                                                case (#err(error)) { return #err(error) };
                                                case (#ok(transaction_id)) {
                                                    #ok({
                                                        transaction_id = transaction_id;
                                                        serialized_tx = serialized;
                                                        fee_paid = transaction_fee;
                                                        inputs_used = selected_utxos;
                                                        outputs_created = outputs;
                                                    })
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };

        // Build and sign transaction without broadcasting
        public func buildTransaction(
            from_address: Text,
            to_address: Text,
            amount: Nat64,
            fee: ?Nat64,
            derivation_path: ?Text
        ) : async Result<{serialized_tx: Text; fee_paid: Nat64}> {
            // Same validation and building logic as sendTransaction but without broadcasting
            switch (Validation.validateAddress(from_address)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {};
            };

            switch (Validation.validateAddress(to_address)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {};
            };

            switch (Validation.validateAmount(amount, true)) {
                case (#err(error)) { return #err(error) };
                case (#ok(_)) {};
            };

            let transaction_fee = switch (fee) {
                case (null) { estimateTransactionFee(1, 2) };
                case (?f) {
                    switch (Validation.validateFee(f)) {
                        case (#err(error)) { return #err(error) };
                        case (#ok(validated_fee)) { validated_fee };
                    };
                };
            };

            if (transaction_fee > config.max_fee) {
                return #err(Errors.validationError(
                    "Fee " # debug_show(transaction_fee) #
                    " exceeds maximum allowed fee " # debug_show(config.max_fee)
                ));
            };

            switch (await selectCoinsForTransaction(from_address, amount, transaction_fee)) {
                case (#err(error)) { return #err(error) };
                case (#ok(selected_utxos)) {
                    switch (Address.decodeAddress(to_address)) {
                        case (#err(error)) { return #err(error) };
                        case (#ok(recipient_info)) {
                            switch (Address.decodeAddress(from_address)) {
                                case (#err(error)) { return #err(error) };
                                case (#ok(change_info)) {
                                    let total_input = Array.foldLeft<Types.UTXO, Nat64>(
                                        selected_utxos, 0, func(acc, utxo) { acc + utxo.amount }
                                    );

                                    let change_amount = total_input - amount - transaction_fee;
                                    let outputs = if (change_amount >= Constants.DUST_THRESHOLD) {
                                        [
                                            {
                                                amount = amount;
                                                scriptPublicKey = {
                                                    version = 0 : Nat16;
                                                    scriptPublicKey = recipient_info.script_public_key;
                                                };
                                            },
                                            {
                                                amount = change_amount;
                                                scriptPublicKey = {
                                                    version = 0 : Nat16;
                                                    scriptPublicKey = change_info.script_public_key;
                                                };
                                            }
                                        ]
                                    } else {
                                        [
                                            {
                                                amount = amount;
                                                scriptPublicKey = {
                                                    version = 0 : Nat16;
                                                    scriptPublicKey = recipient_info.script_public_key;
                                                };
                                            }
                                        ]
                                    };

                                    let inputs = Array.map<Types.UTXO, Types.TransactionInput>(
                                        selected_utxos,
                                        func(utxo) {
                                            {
                                                previousOutpoint = {
                                                    transactionId = utxo.transactionId;
                                                    index = utxo.index;
                                                };
                                                signatureScript = "";
                                                sequence = 0;
                                                sigOpCount = 1;
                                            }
                                        }
                                    );

                                    let unsigned_tx : Types.KaspaTransaction = {
                                        version = 0;
                                        inputs = inputs;
                                        outputs = outputs;
                                        lockTime = 0;
                                        subnetworkId = "0000000000000000000000000000000000000000";
                                        gas = 0;
                                        payload = "";
                                    };

                                    switch (await signTransaction(unsigned_tx, selected_utxos, derivation_path)) {
                                        case (#err(error)) { return #err(error) };
                                        case (#ok(signed_tx)) {
                                            let serialized = Transaction.serialize_transaction(signed_tx);
                                            #ok({
                                                serialized_tx = serialized;
                                                fee_paid = transaction_fee;
                                            })
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };

        // Private helper functions

        private func parseDerivationPath(path: Text) : Result<[Blob]> {
            if (Text.size(path) == 0) {
                return #ok([]);
            };

            let parts = Text.split(path, #char '/');
            let result = Buffer.Buffer<Blob>(0);

            for (part in parts) {
                let cleaned = if (Text.endsWith(part, #char '\'')) {
                    Text.trimEnd(part, #char '\'')
                } else {
                    part
                };

                switch (textToNat32(cleaned)) {
                    case (null) {
                        return #err(Errors.validationError("Invalid derivation path component: " # part));
                    };
                    case (?n) {
                        result.add(nat32ToBlob(n));
                    };
                };
            };
            #ok(Buffer.toArray(result))
        };

        private func textToNat32(text: Text) : ?Nat32 {
            var num: Nat = 0;
            for (c in Text.toIter(text)) {
                if (c < '0' or c > '9') {
                    return null;
                };
                num := num * 10 + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
            };
            if (num > Nat32.toNat(Nat32.maximumValue)) {
                return null;
            };
            ?Nat32.fromNat(num)
        };

        private func nat32ToBlob(n: Nat32) : Blob {
            let bytes = Buffer.Buffer<Nat8>(4);
            bytes.add(Nat8.fromNat(Nat32.toNat(n & 0xFF)));
            bytes.add(Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)));
            bytes.add(Nat8.fromNat(Nat32.toNat((n >> 16) & 0xFF)));
            bytes.add(Nat8.fromNat(Nat32.toNat((n >> 24) & 0xFF)));
            Blob.fromArray(Buffer.toArray(bytes))
        };

        private func fetchUTXOs(address: Text) : async Result<[ExtendedUTXO]> {
            let url = "https://" # config.api_host # "/addresses/" # address # "/utxos";
            let request_headers = [
                { name = "Content-Type"; value = "application/json" },
                { name = "User-Agent"; value = "icp-kaspa-wallet" }
            ];

            try {
                let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
                    url = url;
                    max_response_bytes = ?16384; // Increased for production
                    headers = request_headers;
                    body = null;
                    method = #get;
                    is_replicated = ?false;
                    transform = null;
                });

                if (response.status != 200) {
                    let decoded_text = switch (Text.decodeUtf8(response.body)) {
                        case (null) { "Unknown error" };
                        case (?text) { text };
                    };
                    return #err(Errors.networkError(
                        "UTXO fetch failed: " # decoded_text,
                        ?response.status
                    ));
                };

                let decoded_text = switch (Text.decodeUtf8(response.body)) {
                    case (null) {
                        return #err(Errors.networkError("Failed to decode response", ?response.status));
                    };
                    case (?text) { text };
                };

                parseUTXOResponse(decoded_text)
            } catch (e) {
                #err(Errors.networkError("HTTP request failed: " # Error.message(e), null))
            }
        };

        private func parseUTXOResponse(json_text: Text) : Result<[ExtendedUTXO]> {
            switch (Json.parse(json_text)) {
                case (#err(e)) {
                    #err(Errors.internalError("Failed to parse UTXO JSON: " # debug_show(e)))
                };
                case (#ok(json)) {
                    switch (json) {
                        case (#array(utxos)) {
                            let result = Buffer.Buffer<ExtendedUTXO>(0);
                            for (utxo_json in utxos.vals()) {
                                switch (parseUTXOEntry(utxo_json)) {
                                    case (#err(error)) { return #err(error) };
                                    case (#ok(extended_utxo)) {
                                        result.add(extended_utxo);
                                    };
                                };
                            };
                            #ok(Buffer.toArray(result))
                        };
                        case (_) {
                            #err(Errors.internalError("Expected UTXO array in response"))
                        };
                    }
                };
            }
        };

        private func parseUTXOEntry(utxo_json: Json.Json) : Result.Result<ExtendedUTXO, Errors.KaspaError> {
            switch (utxo_json) {
                case (#object_(fields)) {
                    // Extract required fields from UTXO JSON according to API docs
                    var transaction_id: ?Text = null;
                    var index: ?Nat32 = null;
                    var amount: ?Nat64 = null;
                    var script_public_key: ?Text = null;
                    var address: ?Text = null;
                    var is_coinbase: ?Bool = null;

                    for ((key, value) in fields.vals()) {
                        switch (key) {
                            case ("address") {
                                switch (value) {
                                    case (#string(addr)) { address := ?addr };
                                    case (_) { return #err(Errors.internalError("Invalid address format")) };
                                };
                            };
                            // Parse outpoint object
                            case ("outpoint") {
                                switch (value) {
                                    case (#object_(outpoint_obj)) {
                                        for ((k, v) in outpoint_obj.vals()) {
                                            switch (k, v) {
                                                case ("transactionId", #string(txid)) {
                                                    transaction_id := ?txid;
                                                };
                                                case ("index", #number(#int(idx))) {
                                                    index := ?Nat32.fromNat(Int.abs(idx));
                                                };
                                                case ("index", #number(#float(idx))) {
                                                    index := ?Nat32.fromNat(Int.abs(Float.toInt(idx)));
                                                };
                                                case _ {};
                                            };
                                        };
                                    };
                                    case (_) { return #err(Errors.internalError("Invalid outpoint format")) };
                                };
                            };
                            // Parse utxoEntry object
                            case ("utxoEntry") {
                                switch (value) {
                                    case (#object_(entry_obj)) {
                                        for ((k, v) in entry_obj.vals()) {
                                            switch (k, v) {
                                                // Amount can be an array of strings or a direct string
                                                case ("amount", #array(amount_array)) {
                                                    if (amount_array.size() > 0) {
                                                        let first_element = amount_array[0];
                                                        switch (first_element) {
                                                            case (#string(amount_str)) {
                                                                // Parse amount from string
                                                                var parsed_amount: Nat64 = 0;
                                                                for (c in Text.toIter(amount_str)) {
                                                                    if (c >= '0' and c <= '9') {
                                                                        let digit = Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
                                                                        parsed_amount := parsed_amount * 10 + Nat64.fromNat(digit);
                                                                    };
                                                                };
                                                                amount := ?parsed_amount;
                                                            };
                                                            case (_) { return #err(Errors.internalError("Invalid amount array format: " # debug_show(first_element))) };
                                                        };
                                                    } else {
                                                        return #err(Errors.internalError("Empty amount array"));
                                                    };
                                                };
                                                // Try direct string amount as fallback
                                                case ("amount", #string(amount_str)) {
                                                    var parsed_amount: Nat64 = 0;
                                                    for (c in Text.toIter(amount_str)) {
                                                        if (c >= '0' and c <= '9') {
                                                            let digit = Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
                                                            parsed_amount := parsed_amount * 10 + Nat64.fromNat(digit);
                                                        };
                                                    };
                                                    amount := ?parsed_amount;
                                                };
                                                // Parse nested scriptPublicKey object
                                                case ("scriptPublicKey", #object_(spk_obj)) {
                                                    for ((spk_key, spk_value) in spk_obj.vals()) {
                                                        switch (spk_key, spk_value) {
                                                            case ("scriptPublicKey", #string(spk)) {
                                                                script_public_key := ?spk;
                                                            };
                                                            case _ {};
                                                        };
                                                    };
                                                };
                                                case ("isCoinbase", #bool(coinbase)) {
                                                    is_coinbase := ?coinbase;
                                                };
                                                case _ {};
                                            };
                                        };
                                    };
                                    case (_) { return #err(Errors.internalError("Invalid utxoEntry format")) };
                                };
                            };
                            case (_) { /* Ignore unknown fields */ };
                        };
                    };

                    // Validate required fields
                    switch (transaction_id, index, amount, script_public_key, address) {
                        case (?tx_id, ?idx, ?amt, ?script_key, ?addr) {
                            let utxo: Types.UTXO = {
                                transactionId = tx_id;
                                index = idx;
                                amount = amt;
                                scriptVersion = 0; // Default version
                                scriptPublicKey = script_key;
                                address = addr;
                            };

                            let extended_utxo: ExtendedUTXO = {
                                utxo = utxo;
                                confirmations = 1; // Assume confirmed if returned by API
                                is_coinbase = switch (is_coinbase) { case (?c) c; case null false };
                                maturity = null;
                            };

                            #ok(extended_utxo)
                        };
                        case (_, _, _, _, _) {
                            #err(Errors.internalError("Missing required UTXO fields: " # debug_show((transaction_id, index, amount, script_public_key, address))))
                        };
                    };
                };
                case (_) {
                    #err(Errors.internalError("Expected UTXO object"))
                };
            }
        };

        private func selectCoinsForTransaction(
            address: Text,
            amount: Nat64,
            fee: Nat64
        ) : async Result<[Types.UTXO]> {
            switch (await fetchUTXOs(address)) {
                case (#err(error)) { return #err(error) };
                case (#ok(extended_utxos)) {
                    let required = amount + fee;
                    let utxos = Array.map<ExtendedUTXO, Types.UTXO>(
                        extended_utxos,
                        func(ext) { ext.utxo }
                    );

                    // Simple greedy selection algorithm
                    let sorted = Array.sort<Types.UTXO>(
                        utxos,
                        func(a, b) { Nat64.compare(b.amount, a.amount) }
                    );

                    var total: Nat64 = 0;
                    let selected = Buffer.Buffer<Types.UTXO>(0);

                    label selection for (utxo in sorted.vals()) {
                        if (total >= required) {
                            break selection;
                        };
                        selected.add(utxo);
                        total += utxo.amount;
                    };

                    if (total < required) {
                        return #err(Errors.insufficientFunds(required, total));
                    };

                    #ok(Buffer.toArray(selected))
                };
            };
        };

        private func signTransaction(
            tx: Types.KaspaTransaction,
            utxos: [Types.UTXO],
            derivation_path: ?Text
        ) : async Result<Types.KaspaTransaction> {
            let path = switch (derivation_path) {
                case (null) { "" };
                case (?p) { p };
            };

            switch (parseDerivationPath(path)) {
                case (#err(error)) { return #err(error) };
                case (#ok(derivation_blobs)) {

                    // Create reused values for sighash calculations
                    let reused_values : Sighash.SighashReusedValues = {
                        var previousOutputsHash = null;
                        var sequencesHash = null;
                        var sigOpCountsHash = null;
                        var outputsHash = null;
                        var payloadHash = null;
                    };

                    // Sign each input
                    let signed_inputs = Buffer.Buffer<Types.TransactionInput>(tx.inputs.size());

                    for (i in tx.inputs.keys()) {
                        let input = tx.inputs[i];
                        let utxo = utxos[i]; // Assuming inputs and UTXOs are in same order

                        // Calculate sighash for this input
                        switch (Sighash.calculate_sighash_ecdsa(tx, i, utxo, Sighash.SigHashAll, reused_values)) {
                            case (null) {
                                return #err(Errors.cryptographicError("Failed to calculate sighash for input " # debug_show(i)));
                            };
                            case (?sighash) {
                                try {
                                    // Sign the hash using IC ECDSA
                                    let signature_result = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
                                        message_hash = Blob.fromArray(sighash);
                                        derivation_path = derivation_blobs;
                                        key_id = { name = config.key_name; curve = #secp256k1 };
                                    });

                                    // Create signature script with proper push format for Kaspa
                                    let signature_bytes = Blob.toArray(signature_result.signature);
                                    let sighash_type: Nat8 = 0x01; // SigHashAll

                                    // Format as push script: [length][signature][sighash_type]
                                    let script_bytes = Array.flatten<Nat8>([
                                        [Nat8.fromNat(signature_bytes.size() + 1)], // Length prefix
                                        signature_bytes,                             // Raw signature
                                        [sighash_type]                              // Sighash type
                                    ]);
                                    let signature_script = Address.hexFromArray(script_bytes);

                                    // Create signed input
                                    let signed_input : Types.TransactionInput = {
                                        previousOutpoint = input.previousOutpoint;
                                        signatureScript = signature_script;
                                        sequence = input.sequence;
                                        sigOpCount = input.sigOpCount;
                                    };

                                    signed_inputs.add(signed_input);
                                } catch (e) {
                                    return #err(Errors.cryptographicError("Failed to sign input " # debug_show(i) # ": " # Error.message(e)));
                                };
                            };
                        };
                    };

                    // Return signed transaction
                    let signed_tx : Types.KaspaTransaction = {
                        version = tx.version;
                        inputs = Buffer.toArray(signed_inputs);
                        outputs = tx.outputs;
                        lockTime = tx.lockTime;
                        subnetworkId = tx.subnetworkId;
                        gas = tx.gas;
                        payload = tx.payload;
                    };

                    #ok(signed_tx)
                };
            };
        };

        private func estimateTransactionFee(inputs: Nat, outputs: Nat) : Nat64 {
            // Simple fee estimation based on transaction size
            let estimated_size = inputs * 150 + outputs * 35 + 10; // Rough estimation
            Nat64.fromNat(estimated_size) * config.default_fee_rate
        };

        // Broadcast a signed transaction to the Kaspa network
        private func broadcastTransaction(serialized_tx: Text) : async Result<Text> {
            let url = "https://" # config.api_host # "/transactions";
            let request_headers = [
                { name = "Content-Type"; value = "application/json" },
                { name = "User-Agent"; value = "kaspa-production-wallet" }
            ];

            // The serialized transaction is already in JSON format
            let request_body = serialized_tx;

            try {
                let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
                    url = url;
                    max_response_bytes = ?4096;
                    headers = request_headers;
                    body = ?Text.encodeUtf8(request_body);
                    method = #post;
                    is_replicated = ?false;
                    transform = null;
                });

                if (response.status != 200) {
                    let decoded_text = switch (Text.decodeUtf8(response.body)) {
                        case (null) { "Unknown error" };
                        case (?text) { text };
                    };
                    return #err(Errors.networkError(
                        "Transaction broadcast failed: " # decoded_text,
                        ?response.status
                    ));
                };

                let decoded_text = switch (Text.decodeUtf8(response.body)) {
                    case (null) {
                        return #err(Errors.networkError("Failed to decode broadcast response", ?response.status));
                    };
                    case (?text) { text };
                };

                // Parse the response to extract the transaction ID
                switch (Json.parse(decoded_text)) {
                    case (#err(e)) {
                        #err(Errors.internalError("Failed to parse broadcast response JSON: " # debug_show(e)))
                    };
                    case (#ok(json)) {
                        switch (json) {
                            case (#object_(fields)) {
                                // Look for transaction ID in the response
                                for ((key, value) in fields.vals()) {
                                    switch (key) {
                                        case ("transactionId" or "txid" or "id") {
                                            switch (value) {
                                                case (#string(tx_id)) { return #ok(tx_id) };
                                                case (_) {};
                                            };
                                        };
                                        case (_) {};
                                    };
                                };
                                // If no transaction ID found, return a generic success message
                                #ok("Transaction broadcast successful")
                            };
                            case (_) {
                                #err(Errors.internalError("Unexpected broadcast response format"))
                            };
                        }
                    };
                }
            } catch (e) {
                #err(Errors.networkError("HTTP request failed: " # Error.message(e), null))
            }
        };

        // Broadcast a pre-built transaction
        public func broadcastSerializedTransaction(serialized_tx: Text) : async Result<Text> {
            // Validate the transaction format before broadcasting
            if (Text.size(serialized_tx) == 0) {
                return #err(Errors.validationError("Empty transaction data"));
            };

            await broadcastTransaction(serialized_tx)
        };

        // Get transaction status by transaction ID
        public func getTransactionStatus(transaction_id: Text) : async Result<{status: Text; confirmations: ?Nat}> {
            if (Text.size(transaction_id) == 0) {
                return #err(Errors.validationError("Empty transaction ID"));
            };

            let url = "https://" # config.api_host # "/transactions/" # transaction_id;
            let request_headers = [
                { name = "Content-Type"; value = "application/json" },
                { name = "User-Agent"; value = "kaspa-production-wallet" }
            ];

            try {
                let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
                    url = url;
                    max_response_bytes = ?4096;
                    headers = request_headers;
                    body = null;
                    method = #get;
                    is_replicated = ?false;
                    transform = null;
                });

                if (response.status != 200) {
                    let decoded_text = switch (Text.decodeUtf8(response.body)) {
                        case (null) { "Unknown error" };
                        case (?text) { text };
                    };
                    return #err(Errors.networkError(
                        "Transaction status fetch failed: " # decoded_text,
                        ?response.status
                    ));
                };

                let decoded_text = switch (Text.decodeUtf8(response.body)) {
                    case (null) {
                        return #err(Errors.networkError("Failed to decode transaction status response", ?response.status));
                    };
                    case (?text) { text };
                };

                // Parse the response to extract transaction status
                switch (Json.parse(decoded_text)) {
                    case (#err(e)) {
                        #err(Errors.internalError("Failed to parse transaction status JSON: " # debug_show(e)))
                    };
                    case (#ok(json)) {
                        switch (json) {
                            case (#object_(fields)) {
                                var status: ?Text = null;
                                var confirmations: ?Nat = null;

                                for ((key, value) in fields.vals()) {
                                    switch (key) {
                                        case ("status" or "is_accepted") {
                                            switch (value) {
                                                case (#string(s)) { status := ?s };
                                                case (#bool(true)) { status := ?"confirmed" };
                                                case (#bool(false)) { status := ?"pending" };
                                                case (_) {};
                                            };
                                        };
                                        case ("confirmations" or "confirmation_count") {
                                            switch (value) {
                                                case (#number(#int(conf))) {
                                                    confirmations := ?Int.abs(conf);
                                                };
                                                case (#number(#float(conf))) {
                                                    confirmations := ?Int.abs(Float.toInt(conf));
                                                };
                                                case (_) {};
                                            };
                                        };
                                        case (_) {};
                                    };
                                };

                                let final_status = switch (status) {
                                    case (?s) { s };
                                    case (null) { "unknown" };
                                };

                                #ok({
                                    status = final_status;
                                    confirmations = confirmations;
                                })
                            };
                            case (_) {
                                #err(Errors.internalError("Unexpected transaction status response format"))
                            };
                        }
                    };
                }
            } catch (e) {
                #err(Errors.networkError("HTTP request failed: " # Error.message(e), null))
            }
        };

        // Get UTXOs for an address
        // This is useful for advanced use cases like KRC20 where you need direct UTXO access
        public func getUTXOs(address: Text) : async Result<[Types.UTXO]> {
            switch (await fetchUTXOs(address)) {
                case (#err(error)) { #err(error) };
                case (#ok(extended_utxos)) {
                    // Convert ExtendedUTXO to basic UTXO type
                    let utxos = Array.map<ExtendedUTXO, Types.UTXO>(
                        extended_utxos,
                        func(ext) { ext.utxo }
                    );
                    #ok(utxos)
                };
            }
        };


    };

    // Factory function for creating production wallet
    public func createMainnetWallet(key_name: Text) : Wallet {
        let config: WalletConfig = {
            key_name = key_name;
            api_host = "api.kaspa.org";
            network = "mainnet";
            max_fee = 1_000_000; // 0.01 KAS max fee
            default_fee_rate = 1000; // 1000 sompi per byte
        };
        Wallet(config)
    };

    public func createTestnetWallet(key_name: Text) : Wallet {
        let config: WalletConfig = {
            key_name = key_name;
            api_host = "api-tn10.kaspa.org";
            network = "testnet";
            max_fee = 100_000_000_000; // Allow up to 1000 KAS for KRC20 deploys
            default_fee_rate = 1000;
        };
        Wallet(config)
    };
}