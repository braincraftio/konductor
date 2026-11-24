//! Explain paths rejected by the walker using the same ordered ignore sources.
//!
//! Source precedence follows ripgrep's `crates/ignore/src/dir.rs`:
//! custom ignore files, .ignore, .gitignore, repository excludes, global excludes.
//! This matcher only explains omitted boundary entries; it does not traverse trees.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use ignore::Match;
use ignore::gitignore::{Gitignore, GitignoreBuilder};

#[derive(Debug, Clone)]
pub(crate) struct Omission {
    pub(crate) path: PathBuf,
    pub(crate) category: String,
    pub(crate) source: String,
    pub(crate) pattern: String,
    pub(crate) reveal: String,
}

#[derive(Debug)]
pub(crate) struct Provenance {
    files: HashMap<PathBuf, Gitignore>,
    global: Gitignore,
    pub(crate) warnings: Vec<String>,
}

impl Provenance {
    pub(crate) fn new() -> Self {
        let (global, error) = Gitignore::global();
        Self {
            warnings: error
                .into_iter()
                .map(|e| format!("loading global ignore rules: {e}"))
                .collect(),
            files: HashMap::new(),
            global,
        }
    }

    /// Mirrors ripgrep's `create_gitignore` (crates/ignore/src/dir.rs): a
    /// read failure (for example, `.ignore` being a directory) is a partial,
    /// non-fatal error; the rules read before it still apply. Each failing
    /// file is reported once in `warnings`.
    fn matcher(&mut self, file: &Path, root: &Path) -> Result<&Gitignore> {
        if !self.files.contains_key(file) {
            let mut builder = GitignoreBuilder::new(root);
            if file.exists()
                && let Some(error) = builder.add(file)
            {
                // ignore::Error already names the file and line.
                self.warnings.push(format!("ignore rules: {error}"));
            }
            self.files.insert(file.to_path_buf(), builder.build()?);
        }
        Ok(&self.files[file])
    }

    pub(crate) fn explain(
        &mut self,
        path: &Path,
        kind: std::fs::FileType,
    ) -> Result<Option<(PathBuf, String)>> {
        let parent = path.parent().context("omitted path has no parent")?;
        let dirs: Vec<_> = parent.ancestors().collect();
        let git_root = dirs
            .iter()
            .position(|dir| dir.join(".git").exists() || dir.join(".jj").exists());
        for name in [".rgignore", ".ignore", ".gitignore"] {
            if name == ".gitignore" && git_root.is_none() {
                continue;
            }
            for (index, dir) in dirs.iter().enumerate() {
                if name == ".gitignore" && git_root.is_some_and(|root| index > root) {
                    break;
                }
                let file = dir.join(name);
                match self.matcher(&file, dir)?.matched(path, kind.is_dir()) {
                    Match::Ignore(glob) => {
                        return Ok(Some((file, glob.original().to_owned())));
                    }
                    Match::Whitelist(_) => return Ok(None),
                    Match::None => {}
                }
            }
        }
        if let Some(index) = git_root {
            let root = dirs[index];
            let dotgit = root.join(".git");
            let gitdir = if dotgit.is_file() {
                let text = std::fs::read_to_string(&dotgit)?;
                let target = text
                    .trim()
                    .strip_prefix("gitdir: ")
                    .context("invalid .git indirection")?;
                root.join(target)
            } else {
                dotgit
            };
            let common_file = gitdir.join("commondir");
            let common = if common_file.is_file() {
                gitdir.join(std::fs::read_to_string(common_file)?.trim())
            } else {
                gitdir
            };
            let file = common.join("info/exclude");
            match self.matcher(&file, root)?.matched(path, kind.is_dir()) {
                Match::Ignore(glob) => return Ok(Some((file, glob.original().to_owned()))),
                Match::Whitelist(_) => return Ok(None),
                Match::None => {}
            }
            if let Match::Ignore(glob) = self.global.matched(path, kind.is_dir()) {
                return Ok(Some((
                    glob.from()
                        .context("global rule has no source")?
                        .to_path_buf(),
                    glob.original().to_owned(),
                )));
            }
        }
        Ok(None)
    }
}

/// Relative paths may ascend outside the listed root to identify parent rules.
pub(crate) fn relative(path: &Path, root: &Path) -> PathBuf {
    let path_parts: Vec<_> = path.components().collect();
    let root_parts: Vec<_> = root.components().collect();
    let common = path_parts
        .iter()
        .zip(&root_parts)
        .take_while(|(a, b)| a == b)
        .count();
    let mut result = PathBuf::new();
    for _ in common..root_parts.len() {
        result.push("..");
    }
    for part in &path_parts[common..] {
        result.push(part.as_os_str());
    }
    if result.as_os_str().is_empty() {
        result.push(".");
    }
    result
}
