/// KRC20 Token Types
///
/// This module defines the data structures for KRC20 token operations.
/// KRC20 supports two deployment modes:
/// - Deploy-Mint: Permissionless minting (fair launch)
/// - Deploy-Issue: Owner-controlled issuance
///
/// This implementation focuses on Deploy-Mint mode for the MVP.

module {
  /// Deployment modes
  public type DeployMode = { #Mint; #Issue };

  /// Deploy-Mint mode parameters
  /// Used for fair-launch tokens where anyone can mint
  public type DeployMintParams = {
    tick: Text;        // 4-6 letter unique ticker (case-insensitive)
    max: Text;         // Max supply as string (includes decimals)
    lim: Text;         // Balance per mint (includes decimals)
    to: ?Text;         // Optional deployer address (defaults to sender)
    dec: ?Nat8;        // Optional decimals (default: 8)
    pre: ?Text;        // Optional pre-allocation amount
  };

  /// Mint operation parameters
  /// Anyone can mint up to the limit specified in deployment
  public type MintParams = {
    tick: Text;        // Token ticker
    to: ?Text;         // Optional recipient (defaults to sender)
  };

  /// Transfer operation parameters (Mint mode)
  /// Transfer tokens between addresses
  public type TransferMintParams = {
    tick: Text;        // Token ticker
    amt: Text;         // Transfer amount (with decimals)
    to: Text;          // Recipient address (required)
  };

  /// Burn operation parameters (Mint mode)
  /// Permanently destroy tokens
  public type BurnMintParams = {
    tick: Text;        // Token ticker
    amt: Text;         // Amount to burn (with decimals)
  };

  /// List operation parameters
  /// Create a sell order for trading
  public type ListParams = {
    tick: Text;        // Must be lowercase for trading
    amt: Text;         // Amount to list
  };

  /// Send operation parameters
  /// Buy tokens from a listing
  public type SendParams = {
    tick: Text;        // Must be lowercase for trading
  };

  /// Deploy-Issue mode parameters (for future implementation)
  /// Used for controlled issuance tokens
  public type DeployIssueParams = {
    name: Text;        // 4-6 letter token name (duplicates allowed)
    max: Text;         // Max supply (0 for unlimited)
    mod: Text;         // Must be "issue"
    to: ?Text;         // Optional owner address (also used for pre-allocation)
    dec: ?Nat8;        // Optional decimals (default: 8)
    pre: ?Text;        // Optional pre-allocation amount
  };

  /// Issue operation parameters (Issue mode only)
  public type IssueParams = {
    ca: Text;          // Contract address
    amt: Text;         // Issue amount (with decimals)
    to: ?Text;         // Optional recipient (defaults to sender)
  };

  /// Transfer operation parameters (Issue mode)
  public type TransferIssueParams = {
    ca: Text;          // Contract address
    amt: Text;         // Transfer amount (with decimals)
    to: Text;          // Recipient address (required)
  };

  /// Burn operation parameters (Issue mode)
  public type BurnIssueParams = {
    ca: Text;          // Contract address
    amt: Text;         // Amount to burn (with decimals)
  };

  /// Blacklist operation parameters (Issue mode only)
  /// Restricts addresses from holding/transferring tokens
  public type BlacklistParams = {
    ca: Text;          // Contract address
    // Additional fields TBD based on full spec
  };

  /// Change owner operation parameters (Issue mode only)
  /// Transfer token ownership
  public type ChownParams = {
    ca: Text;          // Contract address
    // Additional fields TBD based on full spec
  };
};
