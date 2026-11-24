//! `.tree.toml`: per-repository listing configuration.
//!
//! ```toml
//! gitignore = true          # honor .gitignore, .ignore, git excludes (default)
//! dotfiles  = false         # list dotfiles, as -a does
//! ignore    = ["node_modules/", "!target/"]   # gitignore syntax and semantics
//!
//! [defaults]                # below command-line flags
//! level = 0                 # 0: no depth limit
//! budget = 12000
//! count = "all"             # all | shown | none: which files have lines read
//! read_limit = "4G"         # total bytes read for counts; "unlimited"
//! sizes = false
//! git = true
//!
//! ["target/"]               # presentation for paths matching the key
//! collapse = true
//! note = "build output"
//! ```
//!
//! Discovery: the nearest `.tree.toml` in the listed root or an ancestor, no
//! higher than the git top level. One file applies; files are never merged.
//!
//! `ignore` decides whether a path appears: a plain line hides it, a `!`
//! line shows it even when the base rules hide it, later lines win, and a
//! leading `/` anchors to the directory holding `.tree.toml` — all exactly as
//! in a `.gitignore`. Path sections decide only how a visible path appears;
//! their keys use the same syntax, and later sections override attributes
//! set by earlier ones. Unknown keys and wrong types are errors. Patterns
//! that match nothing are reported in the footer.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};

use anyhow::{Context, Result, bail};
use ignore::Match;
use ignore::gitignore::{Gitignore, GitignoreBuilder};
use serde::Deserialize;

pub(crate) const FILE_NAME: &str = ".tree.toml";

const TOP_LEVEL: &str =
    "gitignore, dotfiles, ignore, defaults, or a quoted path section such as [\"target/\"]";

/// Creates a repository-local starter without overwriting an existing file.
pub(crate) fn initialize(root: &Path) -> Result<()> {
    use std::fmt::Write as _;
    use std::io::Write;

    let root = root
        .canonicalize()
        .context("resolving initialization directory")?;
    if !root.is_dir() {
        bail!("{}: not a directory", root.display());
    }
    let path = root.join(FILE_NAME);
    let mut directories = fs::read_dir(&root)?
        .map(|entry| {
            let entry = entry?;
            Ok((entry.file_name(), entry.file_type()?))
        })
        .collect::<std::io::Result<Vec<_>>>()?;
    directories.sort_by(|a, b| a.0.cmp(&b.0));
    let mut provenance = crate::provenance::Provenance::new();
    for warning in &provenance.warnings {
        eprintln!("tree: {warning}");
    }
    let mut text = String::from(
        "# Repository tree visibility and presentation.\n\
         # Patterns are rooted here; uncomment ! entries to reveal ignored directories.\n\
         gitignore = true\n\
         dotfiles = false\n\
         ignore = [\n",
    );
    let mut sections = Vec::new();
    for (name, kind) in directories {
        if !kind.is_dir() || name == ".git" {
            continue;
        }
        let Some(name) = name.to_str() else {
            writeln!(
                text,
                "  # skipped non-UTF-8 directory: {}",
                crate::render::escape_os(&name)
            )?;
            continue;
        };
        let escaped: String = name
            .chars()
            .flat_map(|c| {
                if matches!(c, '\\' | '*' | '?' | '[' | ']' | '!' | '#') {
                    vec!['\\', c]
                } else {
                    vec![c]
                }
            })
            .collect();
        let pattern = format!("/{escaped}/");
        if let Some((source, rule)) = provenance.explain(&root.join(name), kind)? {
            let quoted = toml::Value::String(format!("!{pattern}")).to_string();
            writeln!(
                text,
                "  # {quoted}, # {}: {}",
                crate::render::escape(
                    &crate::provenance::relative(&source, &root)
                        .display()
                        .to_string()
                ),
                crate::render::escape(&rule)
            )?;
        }
        sections.push(pattern);
    }
    text.push_str("]\n\n# [defaults]\n# level = 0\n# budget = 12000\n# count = \"all\"\n# read_limit = \"4G\"\n# sizes = false\n# git = true\n");
    for pattern in sections {
        writeln!(
            text,
            "\n# [{}]\n# collapse = true\n# note = \"\"",
            toml::Value::String(pattern)
        )?;
    }
    // Validate the emitted syntax before exclusive creation.
    let _: toml::Table = toml::from_str(&text)?;
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .with_context(|| format!("creating {}", path.display()))?;
    file.write_all(text.as_bytes())
        .context("writing tree configuration")?;
    file.sync_all().context("syncing tree configuration")?;
    println!("created {}", path.display());
    Ok(())
}

/// Defaults below command-line flags. `level = 0` means no depth limit.
#[derive(Debug, Default, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Defaults {
    pub(crate) inventory: Option<crate::args::InventoryMode>,
    pub(crate) budget: Option<usize>,
    pub(crate) level: Option<usize>,
    /// `"all"`, `"shown"`, or `"none"`; validated into [`Config::count`].
    count: Option<String>,
    /// A size such as `"4G"` or `"unlimited"`; validated into [`Config::read_limit`].
    read_limit: Option<String>,
    pub(crate) sizes: Option<bool>,
    pub(crate) git: Option<bool>,
}

#[derive(Debug, Default, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Attributes {
    collapse: Option<bool>,
    note: Option<String>,
}

/// Whether a matched path is a directory (gitignore's trailing `/` matches
/// directories only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EntryKind {
    Dir,
    Other,
}

impl EntryKind {
    pub(crate) fn of(file_type: Option<std::fs::FileType>) -> Self {
        if file_type.is_some_and(|t| t.is_dir()) {
            Self::Dir
        } else {
            Self::Other
        }
    }
}

/// What the `ignore` list says about one path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Visibility {
    Hidden,
    Shown,
}

/// How a visible path is presented.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct Presentation {
    pub(crate) collapse: bool,
    pub(crate) note: Option<String>,
}

#[derive(Debug, Clone)]
struct Section {
    key: String,
    matcher: Gitignore,
    attributes: Attributes,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum RuleId {
    Visibility(usize),
    Presentation(usize),
}

/// Compiled `.tree.toml`. Clones share usage tracking, so the walker's
/// filter and the builder record into one set.
#[derive(Debug, Clone)]
pub(crate) struct Config {
    pub(crate) path: PathBuf,
    pub(crate) defaults: Defaults,
    pub(crate) gitignore: Option<bool>,
    pub(crate) dotfiles: Option<bool>,
    pub(crate) count: Option<crate::args::Count>,
    pub(crate) read_limit: Option<crate::args::ReadLimit>,
    ignore: Gitignore,
    ignore_lines: Vec<String>,
    sections: Vec<Section>,
    used: Arc<Mutex<BTreeSet<RuleId>>>,
}

fn matcher(dir: &Path, file: &Path, origin: &str, lines: &[String]) -> Result<Gitignore> {
    let mut builder = GitignoreBuilder::new(dir);
    for line in lines {
        builder
            .add_line(Some(file.to_path_buf()), line)
            .with_context(|| format!("{}: {origin}: invalid pattern '{line}'", file.display()))?;
    }
    builder
        .build()
        .with_context(|| format!("{}: {origin}", file.display()))
}

fn boolean(file: &Path, key: &str, value: &toml::Value) -> Result<bool> {
    value.as_bool().with_context(|| {
        format!(
            "{}: '{key}' must be true or false, got {}",
            file.display(),
            value.type_str()
        )
    })
}

impl Config {
    pub(crate) fn rules(&self) -> serde_json::Value {
        use serde_json::json;
        json!({
            "visibility": self.ignore_lines.iter().enumerate().map(|(order, pattern)| json!({
                "order": order, "pattern": pattern, "source": self.path,
            })).collect::<Vec<_>>(),
            "presentation": self.sections.iter().enumerate().map(|(order, section)| json!({
                "order": order, "pattern": section.key, "source": self.path,
                "collapse": section.attributes.collapse, "note": section.attributes.note,
            })).collect::<Vec<_>>(),
        })
    }
    pub(crate) fn rule(&self, path: &Path, kind: EntryKind) -> Option<String> {
        self.matched_visibility(path, kind)
            .map(|(_, pattern)| pattern.to_owned())
    }

    /// Finds and compiles the `.tree.toml` that applies to `root`.
    pub(crate) fn discover(root: &Path, stop: Option<&Path>) -> Result<Option<Self>> {
        for dir in root.ancestors() {
            let candidate = dir.join(FILE_NAME);
            if candidate.is_file() {
                return Self::load(&candidate, dir).map(Some);
            }
            if dir == stop.unwrap_or(root) {
                break;
            }
        }
        Ok(None)
    }

    fn load(file: &Path, dir: &Path) -> Result<Self> {
        let text =
            fs::read_to_string(file).with_context(|| format!("reading {}", file.display()))?;
        let table: toml::Table =
            toml::from_str(&text).with_context(|| format!("{}: invalid TOML", file.display()))?;
        let mut config = Self {
            path: file.to_path_buf(),
            defaults: Defaults::default(),
            gitignore: None,
            dotfiles: None,
            count: None,
            read_limit: None,
            ignore: Gitignore::empty(),
            ignore_lines: Vec::new(),
            sections: Vec::new(),
            used: Arc::default(),
        };
        for (key, value) in table {
            match key.as_str() {
                "gitignore" => config.gitignore = Some(boolean(file, &key, &value)?),
                "dotfiles" => config.dotfiles = Some(boolean(file, &key, &value)?),
                "ignore" => {
                    config.ignore_lines = value.try_into().with_context(|| {
                        format!("{}: 'ignore' must be an array of strings", file.display())
                    })?;
                    let mut builder = GitignoreBuilder::new(dir);
                    for (index, line) in config.ignore_lines.iter().enumerate() {
                        // Glob origins carry identity even when pattern text is duplicated.
                        builder
                            .add_line(Some(PathBuf::from(index.to_string())), line)
                            .with_context(|| {
                                format!(
                                    "{}: ignore[{index}]: invalid pattern '{line}'",
                                    file.display()
                                )
                            })?;
                    }
                    config.ignore = builder.build()?;
                }
                "defaults" => {
                    config.defaults = value.try_into().with_context(|| {
                        format!(
                            "{}: [defaults] (keys: budget, level, inventory, count, read_limit, sizes, git)",
                            file.display()
                        )
                    })?;
                    if let Some(mode) = &config.defaults.count {
                        config.count =
                            Some(crate::args::Count::parse(mode).with_context(|| {
                                format!("{}: [defaults] count", file.display())
                            })?);
                    }
                    if let Some(size) = &config.defaults.read_limit {
                        config.read_limit =
                            Some(crate::args::parse_read_limit(size).with_context(|| {
                                format!("{}: [defaults] read_limit", file.display())
                            })?);
                    }
                }
                _ => config.sections.push(Self::section(file, dir, key, value)?),
            }
        }
        Ok(config)
    }

    fn section(file: &Path, dir: &Path, key: String, value: toml::Value) -> Result<Section> {
        if !value.is_table() {
            bail!(
                "{}: unknown key '{key}' ({}); expected {TOP_LEVEL}",
                file.display(),
                value.type_str()
            );
        }
        if key.starts_with('!') {
            bail!(
                "{}: section [\"{key}\"]: '!' belongs in the ignore list; sections set presentation",
                file.display()
            );
        }
        let attributes: Attributes = value.try_into().with_context(|| {
            format!(
                "{}: section [\"{key}\"] (keys: collapse, note)",
                file.display()
            )
        })?;
        Ok(Section {
            matcher: matcher(
                dir,
                file,
                &format!("section [\"{key}\"]"),
                std::slice::from_ref(&key),
            )?,
            key,
            attributes,
        })
    }

    fn record(&self, rule: RuleId) {
        self.used
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(rule);
    }

    /// The `ignore` list's verdict for an absolute path under the config directory.
    pub(crate) fn visibility(&self, path: &Path, kind: EntryKind) -> Option<Visibility> {
        self.matched_visibility(path, kind)
            .map(|(visibility, _)| visibility)
    }

    fn matched_visibility(&self, path: &Path, kind: EntryKind) -> Option<(Visibility, &str)> {
        match self
            .ignore
            .matched_path_or_any_parents(path, kind == EntryKind::Dir)
        {
            Match::Ignore(glob) => {
                self.record_visibility(glob);
                Some((Visibility::Hidden, glob.original()))
            }
            Match::Whitelist(glob) => {
                self.record_visibility(glob);
                Some((Visibility::Shown, glob.original()))
            }
            Match::None => None,
        }
    }

    fn record_visibility(&self, glob: &ignore::gitignore::Glob) {
        let index = glob
            .from()
            .and_then(|path| path.to_str())
            .and_then(|text| text.parse().ok())
            .expect("visibility glob origins contain their rule index");
        self.record(RuleId::Visibility(index));
    }

    /// Presentation for an absolute path: every matching section in file
    /// order, later sections overriding the attributes they set.
    pub(crate) fn presentation(&self, path: &Path, kind: EntryKind) -> Presentation {
        let mut presentation = Presentation::default();
        for (index, section) in self.sections.iter().enumerate() {
            if !section
                .matcher
                .matched(path, kind == EntryKind::Dir)
                .is_ignore()
            {
                continue;
            }
            self.record(RuleId::Presentation(index));
            if let Some(collapse) = section.attributes.collapse {
                presentation.collapse = collapse;
            }
            if let Some(note) = &section.attributes.note {
                presentation.note = Some(note.clone());
            }
        }
        presentation
    }

    /// Patterns that matched nothing during this run, limited to patterns
    /// that can match at or below `root` (absolute). Anchored patterns whose
    /// literal path diverges from `root` are counted in `out_of_scope`.
    pub(crate) fn usage(&self, root: &Path) -> Usage {
        let dir = self.path.parent().unwrap_or(Path::new(""));
        let rel = root.strip_prefix(dir).unwrap_or(Path::new(""));
        let used = self.used.lock().unwrap_or_else(PoisonError::into_inner);
        let mut usage = Usage::default();
        let candidates = self
            .ignore_lines
            .iter()
            .enumerate()
            .filter(|(index, _)| !used.contains(&RuleId::Visibility(*index)))
            .map(|(index, line)| {
                (
                    format!("ignore[{index}] '{line}'"),
                    in_scope(
                        line.strip_prefix('!').unwrap_or(line),
                        rel,
                        Matching::WithParents,
                    ),
                )
            })
            .chain(
                self.sections
                    .iter()
                    .enumerate()
                    .filter(|(index, _)| !used.contains(&RuleId::Presentation(*index)))
                    .map(|(_, s)| {
                        (
                            format!("[\"{}\"]", s.key),
                            in_scope(&s.key, rel, Matching::PathOnly),
                        )
                    }),
            );
        for (label, scope) in candidates {
            match scope {
                Scope::Inside => usage.unused.push(label),
                Scope::Outside => usage.out_of_scope += 1,
            }
        }
        usage
    }
}

/// Unused-rule accounting for one listing root.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(crate) struct Usage {
    pub(crate) unused: Vec<String>,
    pub(crate) out_of_scope: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Scope {
    Inside,
    Outside,
}

/// Visibility rules apply to descendants of a matched directory
/// (`matched_path_or_any_parents`); path sections match the path itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Matching {
    WithParents,
    PathOnly,
}

/// Whether a gitignore-syntax pattern, relative to the configuration
/// directory, can match `root` (relative to that directory) or a path below
/// it. Unanchored patterns and patterns whose components cannot be compared
/// literally (glob metacharacters) are inside.
fn in_scope(pattern: &str, root: &Path, matching: Matching) -> Scope {
    let body = pattern.trim_end_matches('/');
    let anchored = pattern.starts_with('/') || body.contains('/');
    if !anchored || body.starts_with("**/") || root.as_os_str().is_empty() {
        return Scope::Inside;
    }
    let parts: Vec<&str> = body.trim_start_matches('/').split('/').collect();
    let roots: Vec<_> = root
        .components()
        .map(std::path::Component::as_os_str)
        .collect();
    for (part, root_part) in parts.iter().zip(&roots) {
        if part.contains(['*', '?', '[', '\\']) {
            return Scope::Inside;
        }
        if std::ffi::OsStr::new(part) != *root_part {
            return Scope::Outside;
        }
    }
    if parts.len() < roots.len() && matching == Matching::PathOnly {
        Scope::Outside
    } else {
        Scope::Inside
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Loads `text` from its own directory, so parallel tests never share a file.
    fn config(text: &str) -> Result<(Config, PathBuf)> {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "tree-config-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&dir)?;
        let path = dir.join(FILE_NAME);
        fs::write(&path, text)?;
        let loaded = Config::load(&path, &dir);
        fs::remove_file(&path)?;
        fs::remove_dir(&dir)?;
        Ok((loaded?, dir))
    }

    #[test]
    fn usage_distinguishes_duplicate_visibility_rules_and_sections() {
        let (cfg, dir) = config("ignore = [\"same\", \"same\"]\n[\"same\"]\nnote = \"hidden\"\n")
            .expect("configuration parses");
        assert_eq!(
            cfg.visibility(&dir.join("same"), EntryKind::Other),
            Some(Visibility::Hidden)
        );
        assert_eq!(cfg.usage(&dir).unused, ["ignore[0] 'same'", "[\"same\"]"]);
    }

    #[test]
    fn rejects_unknown_keys_and_types() {
        // cspell:ignore gitignre nbudgit budgit ncolapse
        let err = config("gitignre = true\n").expect_err("typo is an error");
        assert!(format!("{err:#}").contains("gitignre"), "{err:#}");
        let err = config("[defaults]\nbudgit = 1\n").expect_err("unknown default");
        assert!(format!("{err:#}").contains("budgit"), "{err:#}");
        assert!(config("gitignore = \"no\"\n").is_err(), "wrong type");
        assert!(
            config("[\"src/\"]\ncolapse = true\n").is_err(),
            "unknown attribute"
        );
        assert!(
            config("[\"!src/\"]\nnote = \"x\"\n").is_err(),
            "negated section"
        );
    }

    #[test]
    fn ignore_list_has_gitignore_semantics() {
        let (cfg, dir) =
            config("ignore = [\"*.log\", \"!keep.log\", \"/build/\"]\n").expect("parses");
        let (file, directory) = (EntryKind::Other, EntryKind::Dir);
        assert_eq!(
            cfg.visibility(&dir.join("a.log"), file),
            Some(Visibility::Hidden)
        );
        assert_eq!(
            cfg.visibility(&dir.join("keep.log"), file),
            Some(Visibility::Shown),
            "later ! wins"
        );
        assert_eq!(
            cfg.visibility(&dir.join("build"), directory),
            Some(Visibility::Hidden),
            "anchored dir"
        );
        assert_eq!(
            cfg.visibility(&dir.join("sub/build"), directory),
            None,
            "anchor does not float"
        );
        assert_eq!(
            cfg.visibility(&dir.join("build"), file),
            None,
            "trailing slash: directories only"
        );
    }

    #[test]
    fn later_sections_override_and_unused_is_reported() {
        let (cfg, dir) = config(
            "[\"src/\"]\nnote = \"sources\"\ncollapse = true\n[\"/src/\"]\ncollapse = false\n[\"never/\"]\nnote = \"x\"\n",
        )
        .expect("parses");
        let p = cfg.presentation(&dir.join("src"), EntryKind::Dir);
        assert_eq!(p.note.as_deref(), Some("sources"));
        assert!(!p.collapse, "later section wins");
        assert_eq!(cfg.usage(&dir).unused, ["[\"never/\"]"]);
    }

    #[test]
    fn scope_excludes_anchored_rules_outside_the_root() {
        let root = Path::new("src/inner");
        let scope = |p, m| in_scope(p, root, m);
        assert_eq!(scope("/docs/", Matching::PathOnly), Scope::Outside);
        assert_eq!(scope("docs/x", Matching::PathOnly), Scope::Outside);
        assert_eq!(
            scope("/src/", Matching::PathOnly),
            Scope::Outside,
            "ancestor section"
        );
        assert_eq!(
            scope("/src/", Matching::WithParents),
            Scope::Inside,
            "ancestor rule"
        );
        assert_eq!(scope("/src/inner/x", Matching::PathOnly), Scope::Inside);
        assert_eq!(
            scope("/src/inner", Matching::PathOnly),
            Scope::Inside,
            "the root"
        );
        assert_eq!(
            scope("node_modules/", Matching::PathOnly),
            Scope::Inside,
            "unanchored"
        );
        assert_eq!(scope("**/gen/", Matching::PathOnly), Scope::Inside);
        assert_eq!(scope("/s*/x", Matching::PathOnly), Scope::Inside, "glob");
        assert_eq!(
            in_scope("/docs/", Path::new(""), Matching::PathOnly),
            Scope::Inside
        );
    }
}
