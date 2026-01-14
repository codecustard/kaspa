module {
    // Address type constants
    public let SCHNORR : Nat = 0;
    public let ECDSA : Nat = 1;
    public let P2SH : Nat = 2;

    // Payload length constants
    public let SCHNORR_PAYLOAD_LEN : Nat = 32;
    public let ECDSA_PAYLOAD_LEN : Nat = 33;

    // Amount constants
    public let DUST_THRESHOLD : Nat64 = 1_000; // 1,000 sompi
    public let MAX_AMOUNT : Nat64 = 2_100_000_000_000_000; // 21 million KAS in sompi
    public let MIN_FEE : Nat64 = 1_000; // Minimum fee in sompi
    public let MAX_FEE : Nat64 = 100_000_000_000; // Allow up to 1000 KAS for KRC20 deploys
}