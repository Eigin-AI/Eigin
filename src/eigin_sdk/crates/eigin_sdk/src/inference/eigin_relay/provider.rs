use super::{EiginRelayStream, EiginRelayWalletSource};
use crate::{http::*, inference::*};
use std::sync::Arc;

const API_VERSION: &str = "v1";
const RELAY_KEY_HEADER: &str = "X-Eigin-Key";

/// Relay root endpoint and application key. Wallet credentials come from the host.
#[derive(Clone, uniffi::Record)]
pub struct EiginRelayProviderConfig {
    pub base_url: String,
    pub relay_key: String,
}

/// Relay inference with host-owned wallets and injectable platform HTTP.
#[derive(uniffi::Object)]
pub struct EiginRelayProvider {
    config: EiginRelayProviderConfig,
    wallets: Arc<dyn EiginRelayWalletSource>,
    transport: Arc<dyn HttpTransport>,
}

#[uniffi::export]
impl EiginRelayProvider {
    /// Uses SDK-owned native HTTP; browser hosts supply Fetch with with_transport.
    #[uniffi::constructor]
    pub fn new(
        config: EiginRelayProviderConfig,
        wallet_source: Box<dyn EiginRelayWalletSource>,
    ) -> Result<Arc<Self>, InferenceError> {
        #[cfg(not(target_arch = "wasm32"))]
        {
            Self::with_transport(
                config,
                wallet_source,
                Box::new(DefaultHttpTransport::new()?),
            )
        }
        #[cfg(target_arch = "wasm32")]
        {
            let _ = (config, wallet_source);
            Err(InferenceError::Transport {
                reason: "browser hosts must supply a Fetch transport".into(),
                domain: None,
                code: None,
            })
        }
    }

    /// Preserves platform networking while the SDK owns relay authorization and failover.
    #[uniffi::constructor]
    pub fn with_transport(
        config: EiginRelayProviderConfig,
        wallet_source: Box<dyn EiginRelayWalletSource>,
        transport: Box<dyn HttpTransport>,
    ) -> Result<Arc<Self>, InferenceError> {
        if config.base_url.is_empty() || config.relay_key.is_empty() {
            return Err(InferenceError::EiginRelayNotConfigured);
        }
        Ok(Arc::new(Self {
            config,
            wallets: wallet_source.into(),
            transport: transport.into(),
        }))
    }

    /// Discovers relay models without selecting or sending a wallet credential.
    pub fn discovery(&self) -> Arc<ModelDiscoveryOperation> {
        OpenAiCompatibleProvider::with_shared_transport(
            self.compatible_config(),
            self.transport.clone(),
        )
        .discovery()
    }

    /// Creates a lazy stream; initial HTTP 402 responses advance to another wallet.
    pub fn stream(
        &self,
        mut input: InferenceCompletionInput,
    ) -> Result<Arc<EiginRelayStream>, InferenceError> {
        input.is_relay = true;
        Ok(EiginRelayStream::new(
            self.compatible_config(),
            self.wallets.clone(),
            self.transport.clone(),
            input,
        ))
    }
}

impl EiginRelayProvider {
    fn compatible_config(&self) -> InferenceProviderConfig {
        InferenceProviderConfig {
            base_url: format!(
                "{}/{API_VERSION}",
                self.config.base_url.trim_end_matches('/')
            ),
            api_token: String::new(),
            extra_headers: [(RELAY_KEY_HEADER.into(), self.config.relay_key.clone())].into(),
        }
    }
}
