use std::{fs, os::unix::fs::PermissionsExt, path::Path, process::Command};

pub fn executable(path: &Path, script: &str) {
    fs::write(path, script).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

pub fn install(bin: &Path) {
    fs::create_dir_all(bin).unwrap();
    executable(
        &bin.join("clang"),
        "#!/bin/sh\n[ \"$1\" = --print-targets ] || exit 99\nprintf 'wasm32 - WebAssembly 32-bit\n'\n",
    );
    executable(
        &bin.join("llvm-ar"),
        "#!/bin/sh\n[ \"$1\" = --version ] || exit 99\nprintf 'LLVM archiver\n'\n",
    );
}

pub fn clear_overrides(command: &mut Command) -> &mut Command {
    for variable in ["CC", "AR"] {
        for target in ["wasm32_unknown_unknown", "wasm32-unknown-unknown"] {
            command.env_remove(format!("{variable}_{target}"));
        }
    }
    command
}
