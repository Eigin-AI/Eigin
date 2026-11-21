use super::*;

#[test]
fn reasoning_gates_defaults_and_bounds() {
    use CatalogReasoningEffort::*;
    let large = fixture("mistral-large-4-0", &["mistral-large-4"])
        + r#"
reasoning_control = { supported_efforts = ["low", "medium", "high"], fast_effort = "low", escalated_effort = "medium", default_effort = "medium" }
"#;
    let medium = fixture(
        "mistral-medium-2604",
        &["mistral-medium-3-5", "Mistral-Medium-3.5-128B"],
    ) + r#"
reasoning_control = { supported_efforts = ["none", "high"], fast_effort = "none", escalated_effort = "high" }
"#;
    let c = catalog(vec![large, medium], &[]);
    for model in [
        "mistral/mistral-large-4-0",
        "mistral-large-4-0",
        "mistral-large-4",
        "mistral/mistral-medium-2604",
        "mistral-medium-3-5",
        "mistralai/Mistral-Medium-3.5-128B",
        "Mistral-Medium-3.5-128B",
    ] {
        assert!(
            c.reasoning_control(model.into(), "eigin-relay://production".into())
                .is_some(),
            "{model}"
        );
    }
    for endpoint in [
        "https://api.mistral.ai",
        "https://api.mistral.ai/v1",
        "https://api.mistral.ai:443",
        "https://user@api.mistral.ai",
        "https://%61pi.mistral.ai",
        "https://api.mistral.ai:99999",
        "https://api.mistral.ai:",
    ] {
        assert!(
            c.reasoning_control("mistral-large-4".into(), endpoint.into())
                .is_some()
        );
    }
    for endpoint in [
        "HTTPS://api.mistral.ai",
        "https://API.MISTRAL.AI",
        "http://api.mistral.ai",
        "https://api.mistral.ai.evil",
        "https://api.mistral.ai\\evil",
        "eigin-RELAY://prod",
        "invalid",
        "https://api.mistral.ai:abc",
        "https://api.mistral.ai:-1",
    ] {
        assert!(
            c.reasoning_control("mistral-large-4".into(), endpoint.into())
                .is_none(),
            "{endpoint}"
        );
    }
    for model in [
        "MISTRAL-LARGE-4",
        "mistral-large-4-0-2026",
        "vendor/mistral-large-4",
        "mistral-medium-2604",
    ] {
        assert!(
            c.reasoning_control(model.into(), "https://api.mistral.ai".into())
                .is_none()
        );
    }
    let large = c
        .reasoning_control("mistral-large-4".into(), "https://api.mistral.ai".into())
        .unwrap();
    assert_eq!(large.fast_effort, Low);
    assert_eq!(large.escalated_effort, Medium);
    assert_eq!(large.request_effort(Option::None), Some(Medium));
    for effort in [None, Minimal, High, Xhigh, Max] {
        assert_eq!(large.request_effort(Some(effort)), Some(Medium));
    }
    assert_eq!(large.request_effort(Some(Low)), Some(Low));
    let medium = c
        .reasoning_control("mistral-medium-3-5".into(), "https://api.mistral.ai".into())
        .unwrap();
    assert_eq!(medium.request_effort(Option::None), Option::None);
    assert_eq!(medium.request_effort(Some(None)), Some(None));
    assert_eq!(medium.request_effort(Some(Low)), Some(High));
    assert_eq!(
        c.bounded_reasoning_effort(Some(Max), "unknown".into(), "https://api.mistral.ai".into()),
        Some(Max)
    );
}

#[test]
fn image_allowance_defaults_identity_and_saturation() {
    let c = catalog(vec![fixture("gpt-4.1", &[])], &[]);
    for (model, expected) in [
        ("gpt-4o-mini", 32768),
        ("gpt-4.1", 3328),
        ("unknown", 32768),
    ] {
        assert_eq!(
            c.image_input_budget(None, None, Some(model.into())),
            expected
        );
        assert_eq!(
            c.image_input_budget(Some(i64::MAX), Some(i64::MAX), Some(model.into())),
            i64::MAX
        );
    }
    let custom = catalog(vec![fixture("gpt-4o-mini", &[])], &[]);
    assert_eq!(
        custom.image_input_budget(None, None, Some("openai/gpt-4o-mini-2024".into())),
        25501
    );
    assert_eq!(
        c.image_input_budget(Some(0), Some(-3), Some("gpt-4.1".into())),
        259
    );
    assert_eq!(c.image_input_budget(None, None, None), 32768);
}
