import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Buffer "mo:base/Buffer";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Char "mo:base/Char";

import Errors "errors";
import Constants "constants";

module {

    public type Result<T> = Result.Result<T, Errors.KaspaError>;

    // Basic address format validation (detailed validation in address.mo)
    public func validateAddress(address: Text) : Result<Text> {
        if (Text.size(address) == 0) {
            return #err(Errors.invalidAddress("Address cannot be empty"));
        };

        if (not Text.startsWith(address, #text("kaspa:")) and not Text.startsWith(address, #text("kaspatest:"))) {
            return #err(Errors.invalidAddress("Address must start with 'kaspa:' or 'kaspatest:' prefix"));
        };

        // Basic length check
        if (Text.size(address) < 10) {
            return #err(Errors.invalidAddress("Address too short"));
        };

        #ok(address)
    };

    // Validate amount with optional dust check
    public func validateAmount(amount: Nat64, dust_check: Bool) : Result<Nat64> {
        if (dust_check and amount < Constants.DUST_THRESHOLD) {
            return #err(Errors.invalidAmount(
                "Amount below dust threshold",
                ?Constants.DUST_THRESHOLD,
                ?Constants.MAX_AMOUNT
            ));
        };

        if (amount > Constants.MAX_AMOUNT) {
            return #err(Errors.invalidAmount(
                "Amount exceeds maximum",
                ?Constants.DUST_THRESHOLD,
                ?Constants.MAX_AMOUNT
            ));
        };

        #ok(amount)
    };

    // Validate fee
    public func validateFee(fee: Nat64) : Result<Nat64> {
        if (fee < Constants.MIN_FEE) {
            return #err(Errors.invalidAmount(
                "Fee too small",
                ?Constants.MIN_FEE,
                ?Constants.MAX_FEE
            ));
        };

        if (fee > Constants.MAX_FEE) {
            return #err(Errors.invalidAmount(
                "Fee too large",
                ?Constants.MIN_FEE,
                ?Constants.MAX_FEE
            ));
        };

        #ok(fee)
    };

    // Validate hex string
    public func validateHexString(hex: Text, expected_length: ?Nat) : Result<[Nat8]> {
        if (Text.size(hex) == 0) {
            return #err(Errors.validationError("Hex string cannot be empty"));
        };

        // Check if all characters are valid hex
        for (char in hex.chars()) {
            if (not ((char >= '0' and char <= '9') or (char >= 'a' and char <= 'f') or (char >= 'A' and char <= 'F'))) {
                return #err(Errors.validationError("Invalid hex character: " # Text.fromChar(char)));
            };
        };

        // Check length if specified
        switch (expected_length) {
            case (?len) {
                if (Text.size(hex) != len * 2) {
                    return #err(Errors.validationError(
                        "Invalid hex length: " # debug_show(Text.size(hex)) #
                        ", expected: " # debug_show(len * 2)
                    ));
                };
            };
            case (null) {};
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

    // Validate BIP44 derivation path
    public func validateDerivationPath(path: Text) : Result<Text> {
        if (Text.size(path) == 0) {
            return #err(Errors.validationError("Derivation path cannot be empty"));
        };

        let parts = Text.split(path, #char '/');
        for (part in parts) {
            // Remove hardened key indicator (')
            let cleaned = if (Text.endsWith(part, #char '\'')) {
                Text.trimEnd(part, #char '\'')
            } else {
                part
            };

            // Check if it's a valid number
            for (char in cleaned.chars()) {
                if (not (char >= '0' and char <= '9')) {
                    return #err(Errors.validationError("Invalid derivation path component: " # part));
                };
            };
        };

        #ok(path)
    };
}