use std::process::Command;

#[test]
fn inference_commands_are_grouped_and_document_their_inputs() {
    for args in [
        vec!["experimental", "inference", "--help"],
        vec!["experimental", "inference", "models", "--help"],
        vec!["experimental", "inference", "chat", "--help"],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
            .args(&args)
            .output()
            .unwrap();
        assert!(output.status.success());
        let help = String::from_utf8(output.stdout).unwrap();
        if args.len() == 3 {
            assert!(help.contains("models") && help.contains("chat"));
        } else {
            assert!(
                help.contains("--base-url")
                    && help.contains("--api-key-env")
                    && help.contains("--no-auth")
            );
        }
    }
}

#[test]
fn chat_requires_model_and_prompt_before_starting_network_work() {
    let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
        .args([
            "experimental",
            "inference",
            "chat",
            "--base-url",
            "https://example.test/v1",
        ])
        .output()
        .unwrap();
    assert!(!output.status.success());
    let error = String::from_utf8(output.stderr).unwrap();
    assert!(error.contains("--model") && error.contains("--prompt"));
}

#[test]
fn authentication_choice_is_required_and_mutually_exclusive() {
    for auth in [
        vec![],
        vec!["--api-key-env", "EIGIN_TEST_API_KEY", "--no-auth"],
    ] {
        for (command, arguments) in [
            ("models", vec![]),
            ("chat", vec!["--model", "test", "--prompt", "hello"]),
        ] {
            let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
                .args([
                    "experimental",
                    "inference",
                    command,
                    "--base-url",
                    "https://example.test/v1",
                ])
                .args(arguments)
                .args(&auth)
                .env("OPENAI_API_KEY", "must-not-be-used")
                .env("EIGIN_TEST_API_KEY", "selected-key")
                .output()
                .unwrap();
            assert!(!output.status.success());
            let error = String::from_utf8(output.stderr).unwrap();
            assert!(error.contains("--api-key-env"), "{error}");
            assert!(!error.contains("must-not-be-used") && !error.contains("selected-key"));
        }
    }
}

#[test]
fn missing_and_empty_credentials_fail_before_endpoint_validation() {
    for value in [None, Some(""), Some(" \t")] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_eigin"));
        command.args([
            "experimental",
            "inference",
            "models",
            "--base-url",
            "invalid-url",
            "--api-key-env",
            "EIGIN_TEST_API_KEY",
        ]);
        command.env("OPENAI_API_KEY", "must-not-be-used");
        if let Some(value) = value {
            command.env("EIGIN_TEST_API_KEY", value);
        } else {
            command.env_remove("EIGIN_TEST_API_KEY");
        }
        let output = command.output().unwrap();
        assert!(!output.status.success());
        let error = String::from_utf8(output.stderr).unwrap();
        assert!(
            error.contains("Environment variable EIGIN_TEST_API_KEY"),
            "{error}"
        );
        assert!(!error.contains("invalid-url") && !error.contains("must-not-be-used"));
    }
}

#[test]
fn relay_parameters_are_explicit_and_provider_specific() {
    for (args, expected) in [
        (vec!["--provider", "eigin-relay"], "--relay-key-env"),
        (
            vec!["--provider", "eigin-relay", "--relay-key-env", "RELAY_KEY"],
            "--credit-token-env",
        ),
        (vec!["--provider", "eigin-relay", "--no-auth"], "--no-auth"),
        (
            vec!["--relay-key-env", "RELAY_KEY"],
            "--provider eigin-relay",
        ),
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
            .args([
                "experimental",
                "inference",
                "chat",
                "--base-url",
                "invalid-url",
                "--model",
                "test",
                "--prompt",
                "hi",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(!output.status.success());
        assert!(String::from_utf8_lossy(&output.stderr).contains(expected));
    }
}

#[test]
fn inference_has_no_stable_top_level_alias() {
    let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
        .args(["inference", "--help"])
        .output()
        .unwrap();
    assert!(!output.status.success());
}
