//! Git status for the listed subtree: `git status --porcelain=v1 -z`, keyed by
//! path relative to the listing root. Outside a work tree there is no status.
//! Running `git` itself (rather than a library) keeps every git setting and
//! environment variable (`GIT_DIR`, `core.excludesFile`, ...) in effect.

use anyhow::{Context, Result, bail};
use std::collections::HashMap;
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// `git` executable. Nix builds bake the store path; other builds use PATH.
fn git() -> &'static str {
    option_env!("KONDUCTOR_TREE_GIT").unwrap_or("git")
}

#[derive(Debug, Default)]
pub(crate) struct GitStatus {
    /// Every code reported for a path, sorted. Porcelain can report two
    /// records for one path (a staged deletion of a file still on disk is
    /// `D ` and `??`); keeping one would hide the other.
    codes: HashMap<PathBuf, Vec<String>>,
    /// Tracked paths deleted from disk, relative to the listing root.
    pub(crate) deleted: Vec<(PathBuf, String)>,
}

/// The git top level containing `root`, if `root` is inside a work tree.
pub(crate) fn top_level(root: &Path) -> Option<PathBuf> {
    let out = Command::new(git())
        .arg("-C")
        .arg(root)
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout);
    Some(PathBuf::from(OsStr::from_bytes(text)))
}

impl GitStatus {
    pub(crate) fn load(root: &Path, top: &Path) -> Result<Self> {
        let prefix = root
            .strip_prefix(top)
            .context("Git root does not contain listing root")?
            .to_path_buf();
        let out = Command::new(git())
            .arg("-C")
            .arg(root)
            .args([
                "status",
                "--porcelain=v1",
                "-z",
                "--untracked-files=all",
                "--no-renames",
                "--",
                ".",
            ])
            .output()
            .context("executing git status")?;
        if !out.status.success() {
            bail!(
                "git status {}: {}",
                out.status,
                String::from_utf8_lossy(&out.stderr).trim()
            );
        }
        let mut status = Self::default();
        for record in out.stdout.split(|&b| b == 0).filter(|r| r.len() > 3) {
            // Preserve both porcelain columns verbatim, including spaces.
            let code = String::from_utf8_lossy(&record[..2]).into_owned();
            let path = Path::new(OsStr::from_bytes(&record[3..]));
            let Ok(rel) = path.strip_prefix(&prefix) else {
                continue;
            };
            if code.contains('D') && std::fs::symlink_metadata(root.join(rel)).is_err() {
                status.deleted.push((rel.to_path_buf(), code));
            } else {
                status
                    .codes
                    .entry(rel.to_path_buf())
                    .or_default()
                    .push(code);
            }
        }
        for codes in status.codes.values_mut() {
            codes.sort();
            codes.dedup();
        }
        status.deleted.sort();
        Ok(status)
    }

    pub(crate) fn codes(&self, rel: &Path) -> &[String] {
        self.codes.get(rel).map_or(&[], Vec::as_slice)
    }
}
