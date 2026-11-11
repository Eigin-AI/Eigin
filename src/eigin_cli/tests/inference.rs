use std::process::Command;

#[test]
fn inference_commands_are_grouped_and_document_their_inputs() {
    for args in [
        vec!["inference", "--help"],
        vec!["inference", "models", "--help"],
        vec!["inference", "chat", "--help"],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
            .args(&args)
            .output()
            .unwrap();
        assert!(output.status.success());
        let help = String::from_utf8(output.stdout).unwrap();
        if args.len() == 2 {
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
        .args(["inference", "chat", "--base-url", "https://example.test/v1"])
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
