/// Host wallet access failed. Details and credentials stay with the host.
#[derive(Clone, Debug, thiserror::Error, uniffi::Error)]
pub enum EiginRelayWalletError {
    #[error("Wallet source unavailable")]
    Unavailable,
}

/// Access to the host's wallet collection. Each wallet has one bearer credit token.
/// Calls are synchronous local operations; implementations must support concurrent callers.
#[uniffi::export(callback_interface)]
pub trait EiginRelayWalletSource: Send + Sync {
    /// Returns the first spendable token in host order, excluding prior attempts.
    fn next_token(&self, excluded: Vec<String>) -> Result<Option<String>, EiginRelayWalletError>;

    /// Records exhaustion of this wallet without changing other wallets.
    fn mark_exhausted(&self, token: String) -> Result<(), EiginRelayWalletError>;
}
