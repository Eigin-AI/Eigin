use super::KnowledgeError;

/// Normalizes logical paths without consulting an operating-system filesystem.
pub(super) fn normalize(path: &str) -> Result<String, KnowledgeError> {
    let invalid = || KnowledgeError::InvalidPath { path: path.into() };
    if path.starts_with('/') || path.contains(['\\', ':', '\0']) {
        return Err(invalid());
    }
    let mut components = Vec::new();
    for component in path.split('/') {
        match component {
            "" | "." => {}
            ".." => {
                components.pop().ok_or_else(invalid)?;
            }
            value => components.push(value),
        }
    }
    if components.is_empty() {
        return Err(invalid());
    }
    Ok(components.join("/"))
}
