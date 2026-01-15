/// KRC20 Operations
///
/// This module provides JSON formatting functions for KRC20 token operations.
/// All operations follow the KRC20 specification:
/// - Lowercase keys: "p", "op", "tick", etc.
/// - No spaces in JSON output
/// - Fixed field order for consistency
/// - Trading operations (list/send) require lowercase ticker values

import Text "mo:base/Text";
import Nat8 "mo:base/Nat8";
import Char "mo:base/Char";
import Option "mo:base/Option";

import Types "types";

module {
  /// Format a Deploy-Mint operation
  ///
  /// Required fields: p, op, tick, max, lim
  /// Optional fields: to, dec, pre
  ///
  /// Example: {"p":"krc-20","op":"deploy","tick":"kasp","max":"2100000000000000","lim":"100000000000"}
  public func formatDeployMint(params: Types.DeployMintParams) : Text {
    var json = "{\"p\":\"krc-20\",\"op\":\"deploy\",\"tick\":\"" # params.tick # "\"";
    json #= ",\"max\":\"" # params.max # "\"";
    json #= ",\"lim\":\"" # params.lim # "\"";

    // Add optional fields
    switch (params.to) {
      case (?addr) { json #= ",\"to\":\"" # addr # "\"" };
      case null {};
    };

    switch (params.dec) {
      case (?decimals) { json #= ",\"dec\":\"" # Nat8.toText(decimals) # "\"" };  // dec as string
      case null {};
    };

    switch (params.pre) {
      case (?prealloc) { json #= ",\"pre\":\"" # prealloc # "\"" };
      case null {};
    };

    json # "}"
  };

  /// Format a Mint operation
  ///
  /// Required fields: p, op, tick
  /// Optional fields: to
  ///
  /// Example: {"p":"krc-20","op":"mint","tick":"kasp"}
  public func formatMint(params: Types.MintParams) : Text {
    var json = "{\"p\":\"krc-20\",\"op\":\"mint\",\"tick\":\"" # params.tick # "\"";

    switch (params.to) {
      case (?addr) { json #= ",\"to\":\"" # addr # "\"" };
      case null {};
    };

    json # "}"
  };

  /// Format a Transfer operation (Mint mode)
  ///
  /// Required fields: p, op, tick, amt, to
  ///
  /// Example: {"p":"krc-20","op":"transfer","tick":"kasp","amt":"100000000","to":"kaspa:..."}
  public func formatTransferMint(params: Types.TransferMintParams) : Text {
    "{\"p\":\"krc-20\",\"op\":\"transfer\",\"tick\":\"" # params.tick #
    "\",\"amt\":\"" # params.amt # "\",\"to\":\"" # params.to # "\"}"
  };

  /// Format a Burn operation (Mint mode)
  ///
  /// Required fields: p, op, tick, amt
  ///
  /// Example: {"p":"krc-20","op":"burn","tick":"kasp","amt":"6600000000"}
  public func formatBurnMint(params: Types.BurnMintParams) : Text {
    "{\"p\":\"krc-20\",\"op\":\"burn\",\"tick\":\"" # params.tick #
    "\",\"amt\":\"" # params.amt # "\"}"
  };

  /// Format a List operation (create sell order)
  ///
  /// Required fields: p, op, tick, amt
  /// CRITICAL: tick must be lowercase for trading operations
  ///
  /// Example: {"p":"krc-20","op":"list","tick":"test","amt":"292960000000"}
  public func formatList(params: Types.ListParams) : Text {
    // Ensure tick is lowercase for trading
    let tickLower = toLowercase(params.tick);
    "{\"p\":\"krc-20\",\"op\":\"list\",\"tick\":\"" # tickLower #
    "\",\"amt\":\"" # params.amt # "\"}"
  };

  /// Format a Send operation (buy from listing)
  ///
  /// Required fields: p, op, tick
  /// CRITICAL: tick must be lowercase for trading operations
  ///
  /// Example: {"p":"krc-20","op":"send","tick":"test"}
  public func formatSend(params: Types.SendParams) : Text {
    // Ensure tick is lowercase for trading
    let tickLower = toLowercase(params.tick);
    "{\"p\":\"krc-20\",\"op\":\"send\",\"tick\":\"" # tickLower # "\"}"
  };

  // ===== Issue Mode Operations (for future implementation) =====

  /// Format a Deploy-Issue operation
  ///
  /// Required fields: p, op, mod, name, max
  /// Optional fields: to, dec, pre
  ///
  /// Example: {"p":"krc-20","op":"deploy","mod":"issue","name":"mytoken","max":"1000000000"}
  public func formatDeployIssue(params: Types.DeployIssueParams) : Text {
    var json = "{\"p\":\"krc-20\",\"op\":\"deploy\",\"mod\":\"" # params.mod # "\"";
    json #= ",\"name\":\"" # params.name # "\"";
    json #= ",\"max\":\"" # params.max # "\"";

    switch (params.to) {
      case (?addr) { json #= ",\"to\":\"" # addr # "\"" };
      case null {};
    };

    switch (params.dec) {
      case (?decimals) { json #= ",\"dec\":\"" # Nat8.toText(decimals) # "\"" };  // dec as string
      case null {};
    };

    switch (params.pre) {
      case (?prealloc) { json #= ",\"pre\":\"" # prealloc # "\"" };
      case null {};
    };

    json # "}"
  };

  /// Format an Issue operation
  ///
  /// Required fields: p, op, ca, amt
  /// Optional fields: to
  ///
  /// Example: {"p":"krc-20","op":"issue","ca":"a0183c1f...","amt":"100000000000"}
  public func formatIssue(params: Types.IssueParams) : Text {
    var json = "{\"p\":\"krc-20\",\"op\":\"issue\",\"ca\":\"" # params.ca # "\"";
    json #= ",\"amt\":\"" # params.amt # "\"";

    switch (params.to) {
      case (?addr) { json #= ",\"to\":\"" # addr # "\"" };
      case null {};
    };

    json # "}"
  };

  /// Format a Transfer operation (Issue mode)
  ///
  /// Required fields: p, op, ca, amt, to
  ///
  /// Example: {"p":"krc-20","op":"transfer","ca":"a0183c1f...","amt":"100000000","to":"kaspa:..."}
  public func formatTransferIssue(params: Types.TransferIssueParams) : Text {
    "{\"p\":\"krc-20\",\"op\":\"transfer\",\"ca\":\"" # params.ca #
    "\",\"amt\":\"" # params.amt # "\",\"to\":\"" # params.to # "\"}"
  };

  /// Format a Burn operation (Issue mode)
  ///
  /// Required fields: p, op, ca, amt
  ///
  /// Example: {"p":"krc-20","op":"burn","ca":"a0183c1f...","amt":"6600000000"}
  public func formatBurnIssue(params: Types.BurnIssueParams) : Text {
    "{\"p\":\"krc-20\",\"op\":\"burn\",\"ca\":\"" # params.ca #
    "\",\"amt\":\"" # params.amt # "\"}"
  };

  // ===== Helper Functions =====

  /// Convert text to lowercase
  /// Simple implementation for ASCII characters
  private func toLowercase(text: Text) : Text {
    let chars = Text.toArray(text);
    var result = "";

    for (c in chars.vals()) {
      if (c >= 'A' and c <= 'Z') {
        let offset = Char.toNat32(c) - Char.toNat32('A');
        let lowerChar = Char.fromNat32(Char.toNat32('a') + offset);
        result #= Char.toText(lowerChar);
      } else {
        result #= Char.toText(c);
      };
    };

    result
  };
};
