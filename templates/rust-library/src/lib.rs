//! Library crate scaffold on Konductor's Rust defaults.
//!
//! Replace [`Name`] with the crate's own API. It demonstrates the shape the
//! lint policy expects: private fields, a fallible constructor through
//! [`FromStr`], a dedicated error type, and documented failure modes.

use std::error::Error;
use std::fmt;
use std::str::FromStr;

/// A trimmed, non-empty name.
///
/// # Examples
///
/// ```
/// # use template_library::{Name, ParseNameError};
/// # fn main() -> Result<(), ParseNameError> {
/// let name: Name = "  Ferris ".parse()?;
/// assert_eq!(name.as_str(), "Ferris");
/// # Ok(())
/// # }
/// ```
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Name(String);

impl Name {
    /// Returns the name without surrounding whitespace.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for Name {
    type Err = ParseNameError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let trimmed = s.trim();
        if trimmed.is_empty() {
            return Err(ParseNameError(()));
        }
        Ok(Self(trimmed.to_owned()))
    }
}

impl fmt::Display for Name {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// The input to [`Name::from_str`] was empty or only whitespace.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseNameError(());

impl fmt::Display for ParseNameError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("name is empty")
    }
}

impl Error for ParseNameError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_through_display() {
        let name: Name = " Ferris ".parse().expect("non-empty input parses");
        assert_eq!(name.to_string(), "Ferris");
    }
}
