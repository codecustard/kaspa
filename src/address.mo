import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Result "mo:base/Result";

import Errors "errors";
import Constants "constants";

module {

    public type Result<T> = Result.Result<T, Errors.KaspaError>;

    // Address type constants (re-exported from Constants)
    public let SCHNORR : Nat = Constants.SCHNORR;
    public let ECDSA : Nat = Constants.ECDSA;
    public let P2SH : Nat = Constants.P2SH;

    // Payload length constants (re-exported from Constants)
    public let SCHNORR_PAYLOAD_LEN : Nat = Constants.SCHNORR_PAYLOAD_LEN;
    public let ECDSA_PAYLOAD_LEN : Nat = Constants.ECDSA_PAYLOAD_LEN;

    // CashAddr charset
    private let charset : [Char] = [
        'q', 'p', 'z', 'r', 'y', '9', 'x', '8',
        'g', 'f', '2', 't', 'v', 'd', 'w', '0',
        's', '3', 'j', 'n', '5', '4', 'k', 'h',
        'c', 'e', '6', 'm', 'u', 'a', '7', 'l'
    ];

    // Address information type
    public type AddressInfo = {
        address: Text;
        addr_type: Nat;
        payload: [Nat8];
        script_public_key: Text;
    };

    // CashAddr polymod functions (unchanged for compatibility)
    private func cashaddr_polymod_step(pre : Nat64) : Nat64 {
        let b : Nat64 = pre >> 35;
        let mask : Nat64 = 0x07ffffffff;
        ((pre & mask) << 5) ^
        (if ((b >> 0) & 1 == 1) 0x98f2bc8e61 else 0) ^
        (if ((b >> 1) & 1 == 1) 0x79b76d99e2 else 0) ^
        (if ((b >> 2) & 1 == 1) 0xf33e5fb3c4 else 0) ^
        (if ((b >> 3) & 1 == 1) 0xae2eabe2a8 else 0) ^
        (if ((b >> 4) & 1 == 1) 0x1e4f43e470 else 0)
    };

    private func polymod(prefix : [Nat8], payload : [Nat8]) : Nat64 {
        var c : Nat64 = 1;
        for (p in prefix.vals()) {
            c := cashaddr_polymod_step(c) ^ Nat64.fromNat(Nat8.toNat(p & 0x1f));
        };
        c := cashaddr_polymod_step(c);
        for (p in payload.vals()) {
            c := cashaddr_polymod_step(c) ^ Nat64.fromNat(Nat8.toNat(p));
        };
        for (_ in Iter.range(0, 7)) {
            c := cashaddr_polymod_step(c);
        };
        c ^ 1
    };

    private func createChecksum(payload : [Nat8], prefix_bytes : [Nat8]) : [Nat8] {
        let mod : Nat64 = polymod(prefix_bytes, payload);
        let checksum = Buffer.Buffer<Nat8>(8);
        for (i in Iter.range(0, 7)) {
            let value = Nat8.fromNat(Nat64.toNat((mod >> Nat64.fromNat(5 * (7 - i))) & 0x1f));
            checksum.add(value);
        };
        Buffer.toArray<Nat8>(checksum)
    };

    private func convertBits(in_ : [Nat8], inbits : Nat, outbits : Nat, pad : Bool) : Result<[Nat8]> {
        var val : Nat32 = 0;
        var bits : Nat = 0;
        let maxv : Nat32 = (Nat32.fromNat(1) << Nat32.fromNat(outbits)) - 1;
        let out = Buffer.Buffer<Nat8>(in_.size() * inbits / outbits + 2);

        for (byte in in_.vals()) {
            val := (val << Nat32.fromNat(inbits)) | Nat32.fromNat(Nat8.toNat(byte));
            bits += inbits;
            while (bits >= outbits) {
                bits -= outbits;
                let value = Nat8.fromNat(Nat32.toNat((val >> Nat32.fromNat(bits)) & maxv));

                // Validate for encoding (outbits=5)
                if (outbits == 5 and Nat8.toNat(value) >= 32) {
                    return #err(Errors.validationError("Invalid value during bit conversion: " # debug_show(value)));
                };
                out.add(value);
            };
        };

        if (pad) {
            if (bits > 0) {
                let value = Nat8.fromNat(Nat32.toNat((val << Nat32.fromNat(outbits - bits)) & maxv));
                if (outbits == 5 and Nat8.toNat(value) >= 32) {
                    return #err(Errors.validationError("Invalid padding value during bit conversion: " # debug_show(value)));
                };
                out.add(value);
            };
        } else if (((val << Nat32.fromNat(outbits - bits)) & maxv) != 0 or bits >= inbits) {
            return #err(Errors.validationError("Invalid bit conversion: non-zero leftover or too many bits"));
        };

        #ok(Buffer.toArray<Nat8>(out))
    };

    private func cashaddrEncode(payload_bytes : [Nat8], version : Nat, prefix : Text) : Result<Text> {
        let version_byte : Nat8 = switch (version) {
            case (0) 0; // SCHNORR
            case (1) 1; // ECDSA
            case (2) 8; // P2SH
            case (_) {
                return #err(Errors.validationError("Invalid address type: " # debug_show(version)));
            };
        };

        // Convert prefix to bytes for checksum calculation
        let prefix_bytes = Blob.toArray(Text.encodeUtf8(prefix));

        let data = Buffer.Buffer<Nat8>(payload_bytes.size() + 1);
        data.add(version_byte);
        data.append(Buffer.fromArray(payload_bytes));
        let data_array = Buffer.toArray<Nat8>(data);

        switch (convertBits(data_array, 8, 5, true)) {
            case (#err(error)) { #err(error) };
            case (#ok(converted)) {
                let checksum = createChecksum(converted, prefix_bytes);
                let combined = Array.append(converted, checksum);
                let result = Buffer.Buffer<Char>(combined.size());

                for (p in combined.vals()) {
                    if (p >= 32) {
                        return #err(Errors.validationError("Invalid charset value: " # debug_show(p)));
                    };
                    result.add(charset[Nat8.toNat(p)]);
                };

                #ok(Text.fromIter(result.vals()))
            };
        }
    };

    // Validate public key
    private func validatePublicKey(pubkey : Blob, addr_type : Nat) : Result<[Nat8]> {
        let pubkey_bytes = Blob.toArray(pubkey);

        let expected_len = if (addr_type == ECDSA) {
            ECDSA_PAYLOAD_LEN
        } else if (addr_type == SCHNORR or addr_type == P2SH) {
            SCHNORR_PAYLOAD_LEN
        } else {
            return #err(Errors.validationError("Unsupported address type: " # debug_show(addr_type)));
        };

        if (pubkey_bytes.size() != expected_len) {
            return #err(Errors.invalidPublicKey(
                "Invalid public key length for address type " # debug_show(addr_type),
                expected_len
            ));
        };

        if (addr_type == ECDSA) {
            // ECDSA public keys must start with 0x02, 0x03, or 0x04
            if (pubkey_bytes.size() > 0) {
                let first_byte = pubkey_bytes[0];
                if (first_byte != 0x02 and first_byte != 0x03 and first_byte != 0x04) {
                    return #err(Errors.invalidPublicKey(
                        "Invalid ECDSA public key format",
                        expected_len
                    ));
                };
            };
        };

        #ok(pubkey_bytes)
    };

    // Generate Kaspa address from public key with comprehensive validation
    public func generateAddress(pubkey : Blob, addr_type : Nat) : Result<AddressInfo> {
        // Validate public key
        switch (validatePublicKey(pubkey, addr_type)) {
            case (#err(error)) { return #err(error) };
            case (#ok(pubkey_bytes)) {

                // Generate address
                switch (cashaddrEncode(pubkey_bytes, addr_type, "kaspa")) {
                    case (#err(error)) { return #err(error) };
                    case (#ok(encoded)) {
                        let address = "kaspa:" # encoded;

                        // Generate script public key
                        switch (generateScriptPublicKey(pubkey_bytes, addr_type)) {
                            case (#err(error)) { return #err(error) };
                            case (#ok(script)) {
                                #ok({
                                    address = address;
                                    addr_type = addr_type;
                                    payload = pubkey_bytes;
                                    script_public_key = script;
                                })
                            };
                        };
                    };
                };
            };
        };
    };

    // Generate Kaspa address with custom prefix (for testnet/devnet)
    public func generateAddressWithPrefix(pubkey : Blob, addr_type : Nat, prefix : Text) : Result<AddressInfo> {
        // Validate public key
        switch (validatePublicKey(pubkey, addr_type)) {
            case (#err(error)) { return #err(error) };
            case (#ok(pubkey_bytes)) {

                // Generate address
                switch (cashaddrEncode(pubkey_bytes, addr_type, prefix)) {
                    case (#err(error)) { return #err(error) };
                    case (#ok(encoded)) {
                        let address = prefix # ":" # encoded;

                        // Generate script public key
                        switch (generateScriptPublicKey(pubkey_bytes, addr_type)) {
                            case (#err(error)) { return #err(error) };
                            case (#ok(script)) {
                                #ok({
                                    address = address;
                                    addr_type = addr_type;
                                    payload = pubkey_bytes;
                                    script_public_key = script;
                                })
                            };
                        };
                    };
                };
            };
        };
    };

    // Decode Kaspa address with comprehensive validation
    public func decodeAddress(address: Text) : Result<AddressInfo> {
        // Basic validation
        if (Text.size(address) == 0) {
            return #err(Errors.invalidAddress("Address cannot be empty"));
        };

        if (not Text.startsWith(address, #text("kaspa:")) and not Text.startsWith(address, #text("kaspatest:"))) {
            return #err(Errors.invalidAddress("Address must start with 'kaspa:' or 'kaspatest:' prefix"));
        };

        // Core address decoding logic (avoiding circular dependency)
        // Strip either kaspa: or kaspatest: prefix and remember which one
        let is_testnet = Text.startsWith(address, #text("kaspatest:"));
        let prefix_text = if (is_testnet) { "kaspatest" } else { "kaspa" };

        let stripped = if (is_testnet) {
            switch (Text.stripStart(address, #text("kaspatest:"))) {
                case (null) {
                    return #err(Errors.invalidAddress("Failed to strip 'kaspatest:' prefix"));
                };
                case (?s) { s };
            }
        } else {
            switch (Text.stripStart(address, #text("kaspa:"))) {
                case (null) {
                    return #err(Errors.invalidAddress("Failed to strip 'kaspa:' prefix"));
                };
                case (?s) { s };
            }
        };

        // Decode using charset
        let chars = Text.toIter(stripped);
        let data = Buffer.Buffer<Nat8>(stripped.size());
        for (c in chars) {
            var found = false;
            var idx = 0;
            label charset_loop for (charset_char in charset.vals()) {
                if (c == charset_char) {
                    found := true;
                    data.add(Nat8.fromNat(idx));
                    break charset_loop;
                };
                idx += 1;
            };
            if (not found) {
                return #err(Errors.invalidAddress("Invalid character in address: " # Text.fromChar(c)));
            };
        };

        let data_array = Buffer.toArray<Nat8>(data);
        if (data_array.size() < 8) {
            return #err(Errors.invalidAddress("Address too short"));
        };

        // Split data and checksum
        let payload_len = data_array.size() - 8;
        let payload_5bit = Array.tabulate<Nat8>(payload_len, func(i) = data_array[i]);
        let checksum = Array.tabulate<Nat8>(8, func(i) = data_array[payload_len + i]);

        // Verify checksum using the correct prefix
        let prefix_bytes = Blob.toArray(Text.encodeUtf8(prefix_text));
        let calculated_checksum_mod = polymod(prefix_bytes, payload_5bit);
        let expected_checksum = Buffer.Buffer<Nat8>(8);
        for (i in Iter.range(0, 7)) {
            let value = Nat8.fromNat(Nat64.toNat((calculated_checksum_mod >> Nat64.fromNat(5 * (7 - i))) & 0x1f));
            expected_checksum.add(value);
        };

        if (not Array.equal(checksum, Buffer.toArray(expected_checksum), Nat8.equal)) {
            return #err(Errors.invalidAddress("Invalid checksum"));
        };

        // Convert from 5-bit to 8-bit
        let payload_8bit = switch (convertBits(payload_5bit, 5, 8, false)) {
            case (#err(error)) { return #err(error) };
            case (#ok(converted)) { converted };
        };

        if (payload_8bit.size() == 0) {
            return #err(Errors.invalidAddress("Empty payload"));
        };

        // Extract version and payload
        let version = payload_8bit[0];
        let addr_type = switch (version) {
            case (0) { SCHNORR };
            case (1) { ECDSA };
            case (8) { P2SH };
            case (_) {
                return #err(Errors.invalidAddress("Unsupported address version: " # debug_show(version)));
            };
        };

        let payload = Array.tabulate<Nat8>(payload_8bit.size() - 1, func(i) = payload_8bit[i + 1]);

        // Validate payload length
        let expected_len = if (addr_type == ECDSA) {
            ECDSA_PAYLOAD_LEN
        } else {
            SCHNORR_PAYLOAD_LEN
        };

        if (payload.size() != expected_len) {
            return #err(Errors.invalidAddress(
                "Invalid payload length: " # debug_show(payload.size()) #
                ", expected: " # debug_show(expected_len)
            ));
        };

        // Generate script public key
        switch (generateScriptPublicKey(payload, addr_type)) {
            case (#err(error)) { return #err(error) };
            case (#ok(script)) {
                #ok({
                    address = address;
                    addr_type = addr_type;
                    payload = payload;
                    script_public_key = script;
                })
            };
        };
    };

    // Generate script public key from payload and address type
    public func generateScriptPublicKey(payload : [Nat8], addr_type : Nat) : Result<Text> {
        switch (addr_type) {
            case (0) { // SCHNORR
                if (payload.size() != SCHNORR_PAYLOAD_LEN) {
                    return #err(Errors.validationError(
                        "Invalid Schnorr payload length: " # debug_show(payload.size()) #
                        ", expected: " # debug_show(SCHNORR_PAYLOAD_LEN)
                    ));
                };
                // P2PK (Schnorr): OP_DATA_32 <32-byte pubkey> OP_CHECKSIG
                let script = Buffer.Buffer<Nat8>(34);
                script.add(32); // OP_DATA_32
                script.append(Buffer.fromArray(payload));
                script.add(0xAC); // OP_CHECKSIG
                #ok(hexFromArray(Buffer.toArray(script)))
            };
            case (1) { // ECDSA
                if (payload.size() != ECDSA_PAYLOAD_LEN) {
                    return #err(Errors.validationError(
                        "Invalid ECDSA payload length: " # debug_show(payload.size()) #
                        ", expected: " # debug_show(ECDSA_PAYLOAD_LEN)
                    ));
                };
                // P2PK (ECDSA): OP_DATA_33 <33-byte pubkey> OP_CHECKSIG_ECDSA
                let script = Buffer.Buffer<Nat8>(35);
                script.add(33); // OP_DATA_33
                script.append(Buffer.fromArray(payload));
                script.add(0xAB); // OP_CHECKSIG_ECDSA
                #ok(hexFromArray(Buffer.toArray(script)))
            };
            case (2) { // P2SH
                if (payload.size() != SCHNORR_PAYLOAD_LEN) {
                    return #err(Errors.validationError(
                        "Invalid P2SH payload length: " # debug_show(payload.size()) #
                        ", expected: " # debug_show(SCHNORR_PAYLOAD_LEN)
                    ));
                };
                // P2SH: OP_HASH256 <32-byte script hash> OP_EQUAL
                let script = Buffer.Buffer<Nat8>(34);
                script.add(0xA9); // OP_HASH256
                script.add(32); // OP_DATA_32
                script.append(Buffer.fromArray(payload));
                script.add(0x87); // OP_EQUAL
                #ok(hexFromArray(Buffer.toArray(script)))
            };
            case (_) {
                #err(Errors.validationError("Unsupported address type: " # debug_show(addr_type)))
            };
        };
    };

    // Utility functions
    public func hexFromArray(bytes: [Nat8]) : Text {
        let hex_chars : [Char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
        let result = Buffer.Buffer<Char>(bytes.size() * 2);
        for (b in bytes.vals()) {
            let high = Nat8.toNat(b / 16);
            let low = Nat8.toNat(b % 16);
            result.add(hex_chars[high]);
            result.add(hex_chars[low]);
        };
        Text.fromIter(result.vals())
    };

    public func arrayFromHex(hex: Text) : Result<[Nat8]> {
        // Simple hex validation and conversion
        if (Text.size(hex) == 0) {
            return #err(Errors.validationError("Hex string cannot be empty"));
        };

        // Check if all characters are valid hex
        for (char in hex.chars()) {
            if (not ((char >= '0' and char <= '9') or (char >= 'a' and char <= 'f') or (char >= 'A' and char <= 'F'))) {
                return #err(Errors.validationError("Invalid hex character: " # Text.fromChar(char)));
            };
        };

        // Convert to bytes
        let bytes = Buffer.Buffer<Nat8>(Text.size(hex) / 2);
        let chars = Text.toArray(hex);
        var i = 0;
        while (i < chars.size()) {
            if (i + 1 >= chars.size()) {
                return #err(Errors.validationError("Hex string must have even length"));
            };
            let high = hexCharToNat8(chars[i]);
            let low = hexCharToNat8(chars[i + 1]);
            switch (high, low) {
                case (?h, ?l) {
                    bytes.add(h * 16 + l);
                };
                case (_, _) {
                    return #err(Errors.validationError("Invalid hex characters"));
                };
            };
            i += 2;
        };

        #ok(Buffer.toArray(bytes))
    };

    // Helper function to convert hex character to Nat8
    private func hexCharToNat8(char: Char) : ?Nat8 {
        if (char >= '0' and char <= '9') {
            ?Nat8.fromNat(Nat32.toNat(Char.toNat32(char) - Char.toNat32('0')))
        } else if (char >= 'a' and char <= 'f') {
            ?Nat8.fromNat(Nat32.toNat(Char.toNat32(char) - Char.toNat32('a') + 10))
        } else if (char >= 'A' and char <= 'F') {
            ?Nat8.fromNat(Nat32.toNat(Char.toNat32(char) - Char.toNat32('A') + 10))
        } else {
            null
        }
    };

    // Backward compatibility functions (deprecated)
    public func address_from_pubkey(pubkey : Blob, addr_type : Nat) : Text {
        switch (generateAddress(pubkey, addr_type)) {
            case (#ok(info)) { info.address };
            case (#err(_)) { "" };
        };
    };

    public func decode_address(address: Text) : ?(Nat, [Nat8]) {
        switch (decodeAddress(address)) {
            case (#ok(info)) { ?(info.addr_type, info.payload) };
            case (#err(_)) { null };
        };
    };

    public func pubkey_to_script(pubkey : [Nat8], addr_type : Nat) : Text {
        // Backward compatibility: only handle SCHNORR and ECDSA, not P2SH
        if (addr_type == SCHNORR and pubkey.size() == SCHNORR_PAYLOAD_LEN) {
            switch (generateScriptPublicKey(pubkey, addr_type)) {
                case (#ok(script)) { script };
                case (#err(_)) { "" };
            };
        } else if (addr_type == ECDSA and pubkey.size() == ECDSA_PAYLOAD_LEN) {
            switch (generateScriptPublicKey(pubkey, addr_type)) {
                case (#ok(script)) { script };
                case (#err(_)) { "" };
            };
        } else {
            // Legacy behavior: return empty string for P2SH or invalid inputs
            ""
        };
    };

    public func hex_from_array(bytes: [Nat8]) : Text {
        hexFromArray(bytes)
    };

    public func array_from_hex(hex: Text) : [Nat8] {
        switch (arrayFromHex(hex)) {
            case (#ok(bytes)) { bytes };
            case (#err(_)) { [] };
        };
    };
}