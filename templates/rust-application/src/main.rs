//! Application crate scaffold on Konductor's Rust defaults.

use std::env;

use anyhow::{Context, Result, bail};

fn main() -> Result<()> {
    let name = env::args()
        .nth(1)
        .context("usage: template-application <name>")?;
    println!("{}", greeting(&name)?);
    Ok(())
}

/// Builds the greeting for `name`, rejecting blank input.
fn greeting(name: &str) -> Result<String> {
    let name = name.trim();
    if name.is_empty() {
        bail!("name must not be blank");
    }
    Ok(format!("hello, {name}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greets_trimmed_name() {
        assert_eq!(
            greeting(" Ferris ").expect("non-blank name is accepted"),
            "hello, Ferris"
        );
    }

    #[test]
    fn rejects_blank_name() {
        assert!(greeting(" \t").is_err(), "blank name must be rejected");
    }
}
