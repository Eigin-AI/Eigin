use super::{CatalogReasoningControl, CatalogReasoningEffort, ModelCatalog};

#[uniffi::export]
impl ModelCatalog {
    /// Returns effort policy only for verified model/endpoint contracts.
    pub fn reasoning_control(
        &self,
        model: String,
        base_url: String,
    ) -> Option<CatalogReasoningControl> {
        let control = self.lookup(model.clone())?.entry.reasoning_control?;
        if base_url.starts_with("eigin-relay://") {
            return [
                "mistral/mistral-large-4-0",
                "mistral-large-4-0",
                "mistral-large-4",
                "mistral/mistral-medium-2604",
                "mistral-medium-3-5",
                "mistralai/Mistral-Medium-3.5-128B",
                "Mistral-Medium-3.5-128B",
            ]
            .contains(&model.as_str())
            .then_some(control);
        }
        (verified_mistral_endpoint(&base_url)
            && ["mistral-large-4", "mistral-large-4-0", "mistral-medium-3-5"]
                .contains(&model.as_str()))
        .then_some(control)
    }

    /// Applies verified default/cap policy, passing effort through otherwise.
    pub fn bounded_reasoning_effort(
        &self,
        effort: Option<CatalogReasoningEffort>,
        model: String,
        base_url: String,
    ) -> Option<CatalogReasoningEffort> {
        self.reasoning_control(model, base_url)
            .map_or(effort, |control| control.request_effort(effort))
    }

    /// Conservative image allowance with signed 64-bit saturation for Apple parity.
    pub fn image_input_budget(
        &self,
        width: Option<i64>,
        height: Option<i64>,
        model: Option<String>,
    ) -> i64 {
        let entry = model.and_then(|id| self.lookup(id));
        crate::context::catalog_image_budget(
            width,
            height,
            entry.as_ref().map(|m| m.entry.pattern.as_str()),
        )
    }
}

// Foundation compares case-preserving, percent-decoded hosts and accepts any digit-only port.
fn verified_mistral_endpoint(base_url: &str) -> bool {
    let Some(rest) = base_url.strip_prefix("https://") else {
        return false;
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    let host_port = authority.rsplit('@').next().unwrap_or_default();
    let host = if let Some((host, port)) = host_port.split_once(':') {
        if !port.bytes().all(|b| b.is_ascii_digit()) {
            return false;
        }
        host
    } else {
        host_port
    };
    let Ok(host) = percent_encoding::percent_decode_str(host).decode_utf8() else {
        return false;
    };
    if host != "api.mistral.ai" {
        return false;
    }
    // Validate the URL with a representable port while retaining Foundation's port contract.
    let user_info = authority.rsplit_once('@').map_or("", |(user, _)| user);
    let safe_authority = if authority.contains('@') {
        format!("{user_info}@api.mistral.ai")
    } else {
        "api.mistral.ai".to_owned()
    };
    let normalized = base_url.replacen(authority, &safe_authority, 1);
    url::Url::parse(&normalized).is_ok_and(|url| url.host_str() == Some("api.mistral.ai"))
}
