//! One walk per listing root, then the listing model.
//!
//! Visibility, in order: the base rules (ripgrep's: `.gitignore`, `.ignore`,
//! `.rgignore`, git excludes; on unless `.tree.toml` `gitignore = false` or
//! `--no-ignore`), dotfiles (hidden unless `-a` or `dotfiles = true`), then
//! the `.tree.toml` `ignore` list, which hides (`node_modules/`) and re-shows
//! (`!target/`) paths in gitignore syntax. `-I` and `-P` apply last. Every
//! entry on disk that is not listed is accounted for in the report.
//!
//! Bounded inventories stop descending at presentation limits. Full inventories
//! retain descendants behind those limits for aggregate metadata and counting.
//!
//! Phases: walk (metadata only), build nodes, apply depth and budget cuts,
//! then read file contents for line counts: listed files first, then files
//! inside collapsed directories (`--count all`), within `--read-limit` total
//! bytes per root. Finite allowances are consumed sequentially in listing
//! order; unlimited counting is parallel. Totals are
//! computed last, bottom-up, so every uncounted file makes its ancestors `N+`.

use std::cmp::Ordering;
use std::collections::{BTreeSet, HashMap, HashSet};
use std::ffi::{OsStr, OsString};
use std::fs::{self, File, FileType, Metadata};
use std::io::{ErrorKind, Read};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::SystemTime;

use anyhow::{Context, Result, bail};
use globset::{Glob, GlobSet, GlobSetBuilder};
use ignore::WalkBuilder;

use crate::args::{
    Count, DEFAULT_BUDGET, DEFAULT_READ_LIMIT, IgnoreRules, InventoryMode, Options, ReadLimit,
    Sizes, Sort,
};
use crate::config::{Config, EntryKind, Presentation, Visibility};
use crate::git::{self, GitStatus};
use crate::provenance::{self, Omission, Provenance};

/// Files larger than this are listed with their size; their lines are not counted.
pub(crate) const COUNT_LIMIT: u64 = 64 * 1024 * 1024;
/// Bytes inspected for a NUL to classify a file as binary (git's heuristic).
const BINARY_PROBE: usize = 8000;

#[derive(Debug)]
pub(crate) struct Node {
    pub(crate) name: String,
    /// Path relative to the listing root.
    pub(crate) rel: PathBuf,
    pub(crate) kind: Kind,
    /// Files: the porcelain code. Directories: every distinct code below.
    pub(crate) git: Vec<String>,
    pub(crate) note: Option<String>,
    pub(crate) size: u64,
    pub(crate) mtime: Option<SystemTime>,
    pub(crate) cut: Option<Cut>,
    pub(crate) hidden_entries: usize,
    pub(crate) reshown: bool,
    pub(crate) inventory: InventoryState,
    /// Placeholder directory: totals come from a metadata scan (or are
    /// unknown), not from children.
    pub(crate) summarized: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InventoryState {
    NotScanned,
    Incomplete,
    Complete,
}

#[derive(Debug)]
pub(crate) enum Kind {
    Dir { children: Vec<Node>, totals: Totals },
    File(Lines),
    Link { target: PathBuf, state: LinkState },
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LinkState {
    Resolves,
    Broken,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub(crate) struct Totals {
    #[serde(rename = "directories")]
    pub(crate) dirs: u64,
    pub(crate) files: u64,
    pub(crate) lines: u64,
    pub(crate) bytes: u64,
    /// Files whose lines were not counted (summarized ignored directories,
    /// oversize, unreadable, or counting disabled).
    pub(crate) uncounted: u64,
}

impl Totals {
    fn add(&mut self, other: &Self) {
        self.dirs += other.dirs;
        self.files += other.files;
        self.lines += other.lines;
        self.bytes += other.bytes;
        self.uncounted += other.uncounted;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Lines {
    Text(u64),
    Binary,
    TooLarge,
    Unreadable,
    /// `--count none`.
    NotCounted,
    /// `--count shown`: inside a collapsed directory.
    NotShown,
    /// Past `--read-limit`.
    ReadLimit,
    /// Queued for the counting phase; never rendered.
    Pending,
}

#[derive(Debug, Clone, Copy, serde::Serialize)]
#[serde(tag = "state", content = "totals", rename_all = "snake_case")]
pub(crate) enum Inventory {
    NotScanned,
    Incomplete(Totals),
    Complete(Totals),
}

/// Why a directory's contents are summarized instead of listed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Cut {
    Level(usize),
    Budget,
    /// `.tree.toml` path section `collapse = true`.
    Config,
    GitMetadata,
}

/// Where the base-rules setting came from, when it is not the default.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RulesOff {
    Flag,
    Config,
}

/// Everything the footer accounts for, merged across listing roots.
#[derive(Debug, Default)]
pub(crate) struct Report {
    pub(crate) inventory_mode: InventoryMode,
    pub(crate) omissions: Vec<Omission>,
    pub(crate) totals: Totals,
    pub(crate) level_cuts: u64,
    pub(crate) level: Option<usize>,
    pub(crate) budget_cuts: u64,
    pub(crate) budget: usize,
    pub(crate) config_cuts: u64,
    pub(crate) shown: Vec<String>,
    pub(crate) deleted: Vec<(PathBuf, String)>,
    /// Every error and warning, each recorded once.
    pub(crate) unreadable: Vec<String>,
    pub(crate) too_large: u64,
    pub(crate) read_limited: u64,
    pub(crate) not_shown: u64,
    pub(crate) unreadable_files: u64,
    pub(crate) count: Option<Count>,
    pub(crate) read_limit: Option<u64>,
    pub(crate) content_bytes_read: u64,
    pub(crate) inventory_incomplete: bool,
    pub(crate) incomplete_paths: HashSet<PathBuf>,
    /// Directories below the listing root holding their own `.git`: their
    /// git status and `.tree.toml` are not applied.
    pub(crate) nested_repos: Vec<PathBuf>,
    /// Absolute listing root; footer paths are relative to it.
    pub(crate) root: PathBuf,
    pub(crate) rules_off: Option<RulesOff>,
    pub(crate) configs: Vec<(PathBuf, Vec<String>)>,
    pub(crate) git_error: Option<String>,
    pub(crate) reshown_inventory: Vec<(String, Inventory)>,
}

impl Report {
    /// Sorts every name list, so the footer reads in path order regardless
    /// of the order the walk visited directories.
    pub(crate) fn sort(&mut self) {
        self.omissions.sort_by(|a, b| {
            a.path
                .cmp(&b.path)
                .then_with(|| a.category.cmp(&b.category))
        });
        for list in [&mut self.shown, &mut self.unreadable] {
            list.sort();
            list.dedup();
        }
        self.deleted.sort();
        self.nested_repos.sort();
        let roots: Vec<PathBuf> = self
            .shown
            .iter()
            .filter(|p| p.ends_with('/'))
            .map(PathBuf::from)
            .collect();
        self.shown.retain(|path| {
            !roots
                .iter()
                .any(|root| Path::new(path) != root && Path::new(path).starts_with(root))
        });
    }
}

#[derive(Debug)]
pub(crate) struct Listing {
    pub(crate) report: Report,
    pub(crate) label: String,
    pub(crate) root: Node,
    pub(crate) sizes: SizeColumn,
}

/// Which children a listing prints (`-d` prints directories only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Entries {
    All,
    DirsOnly,
}

pub(crate) fn entries(opts: &Options) -> Entries {
    if opts.dirs_only {
        Entries::DirsOnly
    } else {
        Entries::All
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SizeColumn {
    Bytes,
    Human,
    Off,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GitMarkers {
    On,
    Off,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Dotfiles {
    Listed,
    Hidden,
}

/// Effective settings: command line over `.tree.toml` over built-in defaults.
#[derive(Debug, Clone, Copy)]
struct Resolved {
    inventory: InventoryMode,
    level: Option<usize>,
    budget: usize,
    count: Count,
    read_limit: Option<u64>,
    git: GitMarkers,
    sizes: SizeColumn,
    rules: IgnoreRules,
    rules_off: Option<RulesOff>,
    dotfiles: Dotfiles,
}

fn resolve(opts: &Options, config: Option<&Config>) -> Resolved {
    let defaults = config.map(|c| c.defaults.clone()).unwrap_or_default();
    let (rules, rules_off) = match (opts.ignore_rules, config.and_then(|c| c.gitignore)) {
        (Some(IgnoreRules::Off), _) => (IgnoreRules::Off, Some(RulesOff::Flag)),
        (Some(IgnoreRules::Honor), _) | (None, Some(true) | None) => (IgnoreRules::Honor, None),
        (None, Some(false)) => (IgnoreRules::Off, Some(RulesOff::Config)),
    };
    Resolved {
        inventory: opts.inventory.or(defaults.inventory).unwrap_or_default(),
        level: opts.level.or(defaults.level.filter(|&l| l > 0)),
        budget: opts.budget.or(defaults.budget).unwrap_or(DEFAULT_BUDGET),
        count: opts
            .count
            .or(config.and_then(|c| c.count))
            .unwrap_or(Count::All),
        read_limit: opts
            .read_limit
            .or(config.and_then(|c| c.read_limit))
            .unwrap_or(ReadLimit::Bytes(DEFAULT_READ_LIMIT))
            .bytes(),
        git: if defaults.git.unwrap_or(true) {
            GitMarkers::On
        } else {
            GitMarkers::Off
        },
        sizes: match opts.sizes {
            Sizes::Bytes => SizeColumn::Bytes,
            Sizes::Human => SizeColumn::Human,
            Sizes::Off if defaults.sizes.unwrap_or(false) => SizeColumn::Human,
            Sizes::Off => SizeColumn::Off,
        },
        rules,
        rules_off,
        dotfiles: if opts.all || config.and_then(|c| c.dotfiles).unwrap_or(false) {
            Dotfiles::Listed
        } else {
            Dotfiles::Hidden
        },
    }
}

/// Prints resolved settings together with the source of each effective value.
pub(crate) fn print_config(opts: &Options) -> Result<()> {
    use serde_json::json;
    use std::io::Write;

    let root = Path::new(&opts.roots[0]).canonicalize()?;
    let top = git::top_level(&root);
    let config = if opts.no_config {
        None
    } else {
        Config::discover(&root, top.as_deref())?
    };
    let resolved = resolve(opts, config.as_ref());
    let defaults = config
        .as_ref()
        .map(|c| c.defaults.clone())
        .unwrap_or_default();
    let file = config
        .as_ref()
        .map(|c| provenance::relative(&c.path, &root));
    let source = |flag: Option<&str>, configured: bool| -> String {
        flag.map_or_else(
            || {
                if configured {
                    file.as_ref()
                        .map_or_else(|| "default".to_owned(), |p| p.display().to_string())
                } else {
                    "default".to_owned()
                }
            },
            str::to_owned,
        )
    };
    let settings = json!({
        "inventory": { "value": resolved.inventory.name(), "source": source(opts.inventory.map(|_| "--inventory"), defaults.inventory.is_some()) },
        "root": root,
        "config": file,
        "gitignore": { "value": resolved.rules == IgnoreRules::Honor, "source": source(opts.ignore_source.as_deref(), config.as_ref().is_some_and(|c| c.gitignore.is_some())) },
        "dotfiles": { "value": resolved.dotfiles == Dotfiles::Listed, "source": source(opts.all.then_some("-a"), config.as_ref().is_some_and(|c| c.dotfiles.is_some())) },
        "level": { "value": resolved.level.unwrap_or(0), "source": source(opts.level.map(|_| "-L"), defaults.level.is_some()) },
        "budget": { "value": resolved.budget, "source": source(opts.budget.map(|_| "--budget"), defaults.budget.is_some()) },
        "count": { "value": resolved.count.name(), "source": source(opts.count.map(|_| "--count"), config.as_ref().is_some_and(|c| c.count.is_some())) },
        "read_limit": { "value": resolved.read_limit, "source": source(opts.read_limit.map(|_| "--read-limit"), config.as_ref().is_some_and(|c| c.read_limit.is_some())) },
        "git": { "value": resolved.git == GitMarkers::On, "source": source(None, defaults.git.is_some()) },
        "sizes": { "value": format!("{:?}", resolved.sizes).to_lowercase(), "source": source(match opts.sizes { Sizes::Off => None, Sizes::Bytes => Some("-s"), Sizes::Human => Some("-h") }, defaults.sizes.is_some()) },
        "exclude": opts.exclude,
        "include": opts.include,
        "rules": config.as_ref().map(Config::rules),
    });
    let mut out = std::io::stdout().lock();
    serde_json::to_writer_pretty(&mut out, &settings)?;
    writeln!(out)?;
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Filters {
    /// The base rules, as resolved.
    Base,
    /// Inside a directory shown by a `.tree.toml` `!` line: the base rules
    /// do not apply (the `ignore` list still does).
    Off,
}

#[derive(Debug)]
struct Raw {
    rel: PathBuf,
    name: OsString,
    file_type: FileType,
    meta: Option<Metadata>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Filtered {
    Excluded,
    ConfigHidden,
    Cut(Cut),
}

#[derive(Debug, Default)]
struct Walked {
    base_rules: bool,
    children: HashMap<PathBuf, Vec<Raw>>,
    filtered: HashMap<PathBuf, Filtered>,
}

/// Counts lines of `files` (absolute path, size) on every available core and
/// returns results in input order. Workers claim files from a shared index,
/// so one large file does not idle the rest.
fn count_all(files: &[(PathBuf, u64)]) -> Vec<(Lines, u64)> {
    use std::sync::atomic::{AtomicUsize, Ordering as Atomic};
    let workers = std::thread::available_parallelism().map_or(1, std::num::NonZeroUsize::get);
    let next = AtomicUsize::new(0);
    let mut results = vec![(Lines::Unreadable, 0); files.len()];
    std::thread::scope(|scope| {
        let handles: Vec<_> = (0..workers.min(files.len().max(1)))
            .map(|_| {
                scope.spawn(|| {
                    let mut counted = Vec::new();
                    loop {
                        let index = next.fetch_add(1, Atomic::Relaxed);
                        let Some((abs, size)) = files.get(index) else {
                            break;
                        };
                        let mut left = u64::MAX;
                        let lines = count_bounded(abs, *size, &mut left);
                        counted.push((index, (lines, u64::MAX - left)));
                    }
                    counted
                })
            })
            .collect();
        for handle in handles {
            let counted = handle
                .join()
                .unwrap_or_else(|panic| std::panic::resume_unwind(panic));
            for (index, lines) in counted {
                results[index] = lines;
            }
        }
    });
    results
}

/// The walker's entry filter: drops `.git`, `-I` matches, and paths the
/// `.tree.toml` `ignore` list hides, recording each drop for the builder.
#[derive(Debug, Clone)]
struct EntryFilter {
    resolved: Resolved,
    visited: Arc<Mutex<usize>>,
    filtered: Arc<Mutex<HashMap<PathBuf, Filtered>>>,
    exclude: GlobSet,
    config: Option<Config>,
    start: PathBuf,
    start_rel: PathBuf,
}

impl EntryFilter {
    fn keep(&self, entry: &ignore::DirEntry) -> bool {
        if entry.depth() == 0 {
            return true;
        }
        if entry.file_name() == ".git" {
            return false;
        }
        let rel = self.start_rel.join(
            entry
                .path()
                .strip_prefix(&self.start)
                .unwrap_or(entry.path()),
        );
        let kind = EntryKind::of(entry.file_type());
        let reason = if self.exclude.is_match(entry.file_name()) {
            Filtered::Excluded
        } else if self
            .config
            .as_ref()
            .and_then(|c| c.visibility(entry.path(), kind))
            == Some(Visibility::Hidden)
        {
            Filtered::ConfigHidden
        } else {
            if self.resolved.inventory == InventoryMode::Bounded {
                let mut visited = self.visited.lock().expect("traversal counter poisoned");
                let cut = if kind == EntryKind::Dir {
                    if self
                        .resolved
                        .level
                        .is_some_and(|level| rel.components().count() >= level)
                    {
                        self.resolved.level.map(Cut::Level)
                    } else if self
                        .config
                        .as_ref()
                        .is_some_and(|c| c.presentation(entry.path(), kind).collapse)
                    {
                        Some(Cut::Config)
                    } else if *visited >= self.resolved.budget {
                        Some(Cut::Budget)
                    } else {
                        None
                    }
                } else {
                    None
                };
                *visited = visited.saturating_add(1);
                if let Some(cut) = cut {
                    self.filtered
                        .lock()
                        .expect("entry filter poisoned")
                        .insert(rel, Filtered::Cut(cut));
                    return false;
                }
            }
            return true;
        };
        self.filtered
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(rel, reason);
        false
    }
}

struct Builder<'a> {
    visited: Arc<Mutex<usize>>,
    provenance: Provenance,
    opts: &'a Options,
    resolved: Resolved,
    abs: PathBuf,
    config: Option<Config>,
    status: Option<GitStatus>,
    exclude: GlobSet,
    include: Option<GlobSet>,
    report: &'a mut Report,
}

fn globs(patterns: &[String], flag: &str) -> Result<GlobSet> {
    let mut builder = GlobSetBuilder::new();
    for pattern in patterns {
        builder.add(
            Glob::new(pattern).with_context(|| format!("{flag}: invalid pattern '{pattern}'"))?,
        );
    }
    Ok(builder.build()?)
}

/// Builds the listing for one root, merging its accounting into `report`.
pub(crate) fn build(root: &OsStr, opts: &Options) -> Result<Listing> {
    let mut report = Report::default();
    let path = Path::new(root);
    let meta = fs::metadata(path).with_context(|| format!("{}: cannot open", path.display()))?;
    if !meta.is_dir() {
        bail!("{}: not a directory", path.display());
    }
    let abs = path
        .canonicalize()
        .with_context(|| format!("{}: cannot resolve", path.display()))?;
    let top = git::top_level(&abs);
    let config = if opts.no_config {
        None
    } else {
        Config::discover(&abs, top.as_deref())?
    };
    let resolved = resolve(opts, config.as_ref());
    let status = match (resolved.git, top.as_deref()) {
        (GitMarkers::On, Some(top)) => match GitStatus::load(&abs, top) {
            Ok(status) => Some(status),
            Err(error) => {
                report.git_error = Some(format!("{error:#}"));
                None
            }
        },
        _ => None,
    };
    report.level = resolved.level;
    report.inventory_mode = resolved.inventory;
    report.budget = resolved.budget;
    report.count = Some(resolved.count);
    report.read_limit = resolved.read_limit;
    report.root.clone_from(&abs);
    report.rules_off = report.rules_off.or(resolved.rules_off);
    let mut builder = Builder {
        visited: Arc::new(Mutex::new(1)),
        provenance: Provenance::new(),
        opts,
        resolved,
        abs,
        config,
        status,
        exclude: globs(&opts.exclude, "-I")?,
        include: if opts.include.is_empty() {
            None
        } else {
            Some(globs(&opts.include, "-P")?)
        },
        report: &mut report,
    };
    builder
        .report
        .unreadable
        .append(&mut builder.provenance.warnings);
    let label = root.to_string_lossy().into_owned();
    let start = builder.abs.clone();
    let mut walked = builder.walk(&start, Path::new(""), Filters::Base);
    let mut node = builder.dir_node(&mut walked, PathBuf::new(), label.clone(), Some(&meta));
    drop(walked);
    builder.finish(&mut node);
    builder
        .report
        .unreadable
        .append(&mut builder.provenance.warnings);
    report.sort();
    Ok(Listing {
        report,
        label,
        root: node,
        sizes: resolved.sizes,
    })
}

impl Builder<'_> {
    fn omit(&mut self, path: PathBuf, category: &str, source: String, pattern: String) {
        let reveal = match category {
            "dotfile" => "tree -a",
            "ignore" => "tree --no-ignore",
            "config" => "tree --no-config",
            "excluded" => "rerun without -I",
            "pattern" => "rerun without -P",
            "metadata" => "tree --raw -a .git",
            "disagreement" => "inspect diagnostics; tree -a --no-ignore --no-config",
            _ => "inspect filesystem permissions",
        }
        .to_owned();
        self.report.omissions.push(Omission {
            path,
            category: category.to_owned(),
            source,
            pattern,
            reveal,
        });
    }
    fn walk(&mut self, start: &Path, start_rel: &Path, filters: Filters) -> Walked {
        let mut walker = WalkBuilder::new(start);
        let base = filters == Filters::Base && self.resolved.rules == IgnoreRules::Honor;
        walker.standard_filters(base).follow_links(false);
        if self.resolved.inventory == InventoryMode::Bounded {
            walker.sort_by_file_name(OsStr::cmp);
        }
        if base {
            walker.add_custom_ignore_filename(".rgignore");
        }
        walker.hidden(filters == Filters::Base && self.resolved.dotfiles == Dotfiles::Hidden);
        let filter = EntryFilter {
            resolved: self.resolved,
            visited: Arc::clone(&self.visited),
            filtered: Arc::default(),
            exclude: self.exclude.clone(),
            config: self.config.clone(),
            start: start.to_path_buf(),
            start_rel: start_rel.to_path_buf(),
        };
        let shared = filter.clone();
        walker.filter_entry(move |entry| shared.keep(entry));

        let mut found = Walked {
            base_rules: base,
            ..Walked::default()
        };
        for result in walker.build() {
            let entry = match result {
                Ok(entry) => entry,
                Err(err) => {
                    self.report.incomplete_paths.insert(start_rel.to_path_buf());
                    self.report.unreadable.push(err.to_string());
                    continue;
                }
            };
            let Some(file_type) = entry.file_type().filter(|_| entry.depth() > 0) else {
                continue;
            };
            let rel = start_rel.join(entry.path().strip_prefix(start).unwrap_or(entry.path()));
            let meta = match entry.metadata() {
                Ok(meta) => Some(meta),
                Err(error) => {
                    self.report
                        .incomplete_paths
                        .insert(rel.parent().unwrap_or(start_rel).to_path_buf());
                    self.report.unreadable.push(error.to_string());
                    None
                }
            };
            let parent = rel.parent().map(Path::to_path_buf).unwrap_or_default();
            found.children.entry(parent).or_default().push(Raw {
                name: entry.file_name().to_os_string(),
                meta,
                file_type,
                rel,
            });
        }
        found.filtered = std::mem::take(
            &mut *filter
                .filtered
                .lock()
                .unwrap_or_else(PoisonError::into_inner),
        );
        found
    }

    fn presentation(&self, rel: &Path, kind: EntryKind) -> Presentation {
        self.config
            .as_ref()
            .map(|c| c.presentation(&self.abs.join(rel), kind))
            .unwrap_or_default()
    }

    fn sort(&self, children: &mut [Node]) {
        let sort = self.opts.sort;
        children.sort_by(|a, b| {
            let a_dir = matches!(a.kind, Kind::Dir { .. });
            let b_dir = matches!(b.kind, Kind::Dir { .. });
            b_dir.cmp(&a_dir).then_with(|| match sort {
                Sort::Name => a.name.as_bytes().cmp(b.name.as_bytes()),
                Sort::Version => version_cmp(&a.name, &b.name),
            })
        });
    }

    fn dir_node(
        &mut self,
        walked: &mut Walked,
        rel: PathBuf,
        name: String,
        meta: Option<&Metadata>,
    ) -> Node {
        let omissions_start = self.report.omissions.len();
        let mut children = Vec::new();
        let mut present: HashSet<OsString> = HashSet::new();
        // Consume traversal records as nodes replace them; retaining both
        // complete representations keeps traversal storage alive throughout construction.
        for raw in walked.children.remove(&rel).unwrap_or_default() {
            present.insert(raw.name.clone());
            if let Some(child) = self.child_node(walked, &raw) {
                children.push(child);
            }
        }
        self.account_hidden(walked, &rel, &present, &mut children);
        self.sort(&mut children);
        let mut changes: BTreeSet<String> = BTreeSet::new();
        for child in &children {
            changes.extend(child.git.iter().cloned());
        }
        let presentation = self.presentation(&rel, EntryKind::Dir);
        let cut = (!rel.as_os_str().is_empty() && presentation.collapse).then(|| {
            self.report.config_cuts += 1;
            Cut::Config
        });
        Node {
            reshown: false,
            summarized: false,
            inventory: if self.report.incomplete_paths.contains(&rel) {
                InventoryState::Incomplete
            } else {
                InventoryState::Complete
            },
            hidden_entries: self.report.omissions[omissions_start..]
                .iter()
                .filter(|o| o.path.parent() == Some(rel.as_path()))
                .count(),
            note: presentation.note,
            mtime: meta.and_then(|m| m.modified().ok()),
            size: meta.map_or(0, Metadata::len),
            name,
            rel,
            kind: Kind::Dir {
                children,
                totals: Totals::default(),
            },
            git: changes.into_iter().collect(),
            cut,
        }
    }

    /// Counting happens after presentation is decided; files wait as `Pending`.
    fn initial_lines(&self) -> Lines {
        match self.resolved.count {
            Count::None => Lines::NotCounted,
            Count::All | Count::Shown => Lines::Pending,
        }
    }

    fn child_node(&mut self, walked: &mut Walked, raw: &Raw) -> Option<Node> {
        let name = raw.name.to_string_lossy().into_owned();
        if raw.file_type.is_dir() {
            return Some(self.dir_node(walked, raw.rel.clone(), name, raw.meta.as_ref()));
        }
        if raw.file_type.is_file()
            && let Some(include) = &self.include
            && !include.is_match(&raw.name)
        {
            self.omit(
                raw.rel.clone(),
                "pattern",
                "-P".to_owned(),
                self.opts.include.join("|"),
            );
            return None;
        }
        let size = raw.meta.as_ref().map_or(0, Metadata::len);
        let kind = if raw.file_type.is_symlink() {
            self.link(&raw.rel)
        } else if raw.file_type.is_file() {
            Kind::File(self.initial_lines())
        } else {
            Kind::Other
        };
        Some(Node {
            reshown: false,
            summarized: false,
            inventory: InventoryState::Complete,
            hidden_entries: 0,
            git: self
                .status
                .as_ref()
                .map(|s| s.codes(&raw.rel).to_vec())
                .unwrap_or_default(),
            note: self.presentation(&raw.rel, EntryKind::Other).note,
            mtime: raw.meta.as_ref().and_then(|m| m.modified().ok()),
            rel: raw.rel.clone(),
            name,
            kind,
            size,
            cut: None,
        })
    }

    fn link(&mut self, rel: &Path) -> Kind {
        let abs = self.abs.join(rel);
        let target = match fs::read_link(&abs) {
            Ok(target) => target,
            Err(error) => {
                self.report.incomplete_paths.insert(rel.to_path_buf());
                self.report
                    .unreadable
                    .push(format!("{}: {error}", rel.display()));
                PathBuf::from("?")
            }
        };
        let state = if fs::metadata(&abs).is_ok() {
            LinkState::Resolves
        } else {
            LinkState::Broken
        };
        Kind::Link { target, state }
    }

    /// Entries on disk that the walk did not yield: listed when the
    /// `.tree.toml` `ignore` list re-shows them (`!path`), otherwise
    /// classified for the footer.
    fn account_hidden(
        &mut self,
        walked: &Walked,
        rel: &Path,
        present: &HashSet<OsString>,
        children: &mut Vec<Node>,
    ) {
        for (name, file_type) in self.missing_entries(rel, present) {
            let child_rel = rel.join(&name);
            let is_dir = file_type.is_dir();
            let mut label = child_rel.clone().into_os_string();
            if is_dir {
                label.push("/");
            }
            let label = PathBuf::from(label);
            if let Some(Filtered::Cut(cut)) = walked.filtered.get(&child_rel) {
                children.push(self.cut_node(child_rel, &name, *cut));
                continue;
            }
            if self.exclude.is_match(&name) {
                self.omit(
                    label.clone(),
                    "excluded",
                    "-I".to_owned(),
                    self.opts.exclude.join("|"),
                );
                continue;
            }
            if walked.filtered.get(&child_rel) == Some(&Filtered::ConfigHidden) {
                if let Some(config) = &self.config {
                    let source = provenance::relative(&config.path, &self.abs)
                        .display()
                        .to_string();
                    let pattern = config
                        .rule(&self.abs.join(&child_rel), EntryKind::of(Some(file_type)))
                        .unwrap_or_default();
                    self.omit(label.clone(), "config", source, pattern);
                }
                continue;
            }
            if name == ".git" {
                if !rel.as_os_str().is_empty() {
                    self.report.nested_repos.push(rel.to_path_buf());
                }
                if is_dir && self.resolved.dotfiles == Dotfiles::Listed {
                    children.push(placeholder(child_rel, ".git", Cut::GitMetadata));
                } else {
                    self.omit(label, "metadata", "tree".to_owned(), ".git".to_owned());
                }
                continue;
            }
            let shown = self.config.as_ref().and_then(|c| {
                c.visibility(&self.abs.join(&child_rel), EntryKind::of(Some(file_type)))
            }) == Some(Visibility::Shown);
            if shown {
                self.report.shown.push(label.to_string_lossy().into_owned());
                let mut node = self.shown_node(child_rel, &name, file_type);
                node.reshown = true;
                children.push(node);
            } else if walked.base_rules
                && let Some((source, pattern)) = match self
                    .provenance
                    .explain(&self.abs.join(&child_rel), file_type)
                {
                    Ok(rule) => rule,
                    Err(error) => {
                        self.report.unreadable.push(format!("{error:#}"));
                        self.omit(
                            label,
                            "disagreement",
                            "walker/explainer".to_owned(),
                            "explanation failed; see errors".to_owned(),
                        );
                        continue;
                    }
                }
            {
                self.omit(
                    label.clone(),
                    "ignore",
                    provenance::relative(&source, &self.abs)
                        .display()
                        .to_string(),
                    pattern,
                );
            } else if name.as_bytes().first() == Some(&b'.')
                && self.resolved.dotfiles == Dotfiles::Hidden
            {
                self.omit(
                    label.clone(),
                    "dotfile",
                    "tree default".to_owned(),
                    ".*".to_owned(),
                );
            } else {
                self.omit(
                    label.clone(),
                    "disagreement",
                    "walker/explainer".to_owned(),
                    "entry omitted without a matching rule".to_owned(),
                );
                self.report.unreadable.push(format!(
                    "{}: walker/explainer disagreement",
                    crate::render::escape_os(label.as_os_str())
                ));
            }
        }
    }

    fn cut_node(&mut self, rel: PathBuf, name: &OsStr, cut: Cut) -> Node {
        match cut {
            Cut::Level(_) => self.report.level_cuts += 1,
            Cut::Budget => self.report.budget_cuts += 1,
            Cut::Config => self.report.config_cuts += 1,
            Cut::GitMetadata => {}
        }
        let presentation = self.presentation(&rel, EntryKind::Dir);
        let mut node = placeholder(rel, &name.to_string_lossy(), cut);
        node.note = presentation.note;
        node
    }

    fn missing_entries(
        &mut self,
        rel: &Path,
        present: &HashSet<OsString>,
    ) -> Vec<(OsString, FileType)> {
        let entries = match fs::read_dir(self.abs.join(rel)) {
            Ok(entries) => entries,
            Err(error) => {
                self.report.incomplete_paths.insert(rel.to_path_buf());
                self.report
                    .unreadable
                    .push(format!("{}: {error}", rel.display()));
                return Vec::new();
            }
        };
        let mut missing = Vec::new();
        for entry in entries {
            let entry = entry.and_then(|entry| {
                let name = entry.file_name();
                if present.contains(&name) {
                    Ok(None)
                } else {
                    entry.file_type().map(|kind| Some((name, kind)))
                }
            });
            match entry {
                Ok(Some(entry)) => missing.push(entry),
                Ok(None) => {}
                Err(error) => {
                    self.report.incomplete_paths.insert(rel.to_path_buf());
                    self.report
                        .unreadable
                        .push(format!("{}: {error}", rel.display()));
                }
            }
        }
        missing.sort_by(|a, b| a.0.cmp(&b.0));
        missing
    }

    /// A path the base rules hide and the `ignore` list re-shows. A
    /// collapsed directory is summarized without reading file contents.
    fn shown_node(&mut self, rel: PathBuf, name: &OsStr, file_type: FileType) -> Node {
        if file_type.is_dir() && self.resolved.inventory == InventoryMode::Bounded {
            let cut = if self
                .resolved
                .level
                .is_some_and(|level| rel.components().count() >= level)
            {
                self.resolved.level.map(Cut::Level)
            } else if *self.visited.lock().expect("traversal counter poisoned")
                >= self.resolved.budget
            {
                Some(Cut::Budget)
            } else {
                None
            };
            if let Some(cut) = cut {
                return self.cut_node(rel, name, cut);
            }
        }
        let name = name.to_string_lossy().into_owned();
        let abs = self.abs.join(&rel);
        let meta = fs::symlink_metadata(&abs).ok();
        if file_type.is_dir() {
            let presentation = self.presentation(&rel, EntryKind::Dir);
            if presentation.collapse {
                let mut node = placeholder(rel, &name, Cut::Config);
                node.note = presentation.note;
                self.report.config_cuts += 1;
                if self.opts.scan_collapsed {
                    let (totals, complete) = self.summarize(&abs);
                    node.inventory = if complete {
                        InventoryState::Complete
                    } else {
                        InventoryState::Incomplete
                    };
                    if let Kind::Dir { totals: inner, .. } = &mut node.kind {
                        *inner = totals;
                    }
                }
                return node;
            }
            let mut walked = self.walk(&abs, &rel, Filters::Off);
            return self.dir_node(&mut walked, rel, name, meta.as_ref());
        }
        let size = meta.as_ref().map_or(0, Metadata::len);
        let kind = if file_type.is_symlink() {
            self.link(&rel)
        } else if file_type.is_file() {
            Kind::File(self.initial_lines())
        } else {
            Kind::Other
        };
        Node {
            reshown: false,
            summarized: false,
            inventory: InventoryState::Complete,
            hidden_entries: 0,
            note: self.presentation(&rel, EntryKind::Other).note,
            mtime: meta.as_ref().and_then(|m| m.modified().ok()),
            git: Vec::new(),
            name,
            rel,
            kind,
            size,
            cut: None,
        }
    }

    /// Stream metadata without retaining descendants or re-reading directories.
    fn summarize(&mut self, root: &Path) -> (Totals, bool) {
        let mut walker = WalkBuilder::new(root);
        walker
            .standard_filters(false)
            .hidden(false)
            .follow_links(false);
        let config = self.config.clone();
        let exclude = self.exclude.clone();
        walker.filter_entry(move |entry| {
            entry.depth() == 0
                || (entry.file_name() != ".git"
                    && !exclude.is_match(entry.file_name())
                    && config
                        .as_ref()
                        .and_then(|c| c.visibility(entry.path(), EntryKind::of(entry.file_type())))
                        != Some(Visibility::Hidden))
        });
        let mut totals = Totals::default();
        let mut complete = true;
        for entry in walker.build() {
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    complete = false;
                    self.report.unreadable.push(error.to_string());
                    continue;
                }
            };
            if entry.depth() == 0 {
                continue;
            }
            match entry.file_type() {
                Some(kind) if kind.is_dir() => totals.dirs += 1,
                Some(kind)
                    if kind.is_file()
                        && self
                            .include
                            .as_ref()
                            .is_none_or(|p| p.is_match(entry.file_name())) =>
                {
                    totals.files += 1;
                    totals.uncounted += 1;
                    match entry.metadata() {
                        Ok(meta) => totals.bytes += meta.len(),
                        Err(error) => {
                            complete = false;
                            self.report.unreadable.push(error.to_string());
                        }
                    }
                }
                _ => {}
            }
        }
        (totals, complete)
    }

    /// Applies the depth limit and the entry budget, counts lines for the
    /// files the count mode and read limit allow, totals the tree, then
    /// fills the report.
    fn finish(&mut self, root: &mut Node) {
        if let Some(level) = self.resolved.level {
            self.report.level_cuts += cut_at_level(root, 0, level);
        }
        let collapse = budget_plan(root, self.resolved.budget, entries(self.opts));
        self.report.budget_cuts += u64::try_from(collapse.len()).unwrap_or(u64::MAX);
        apply_budget(root, &collapse);
        self.count(root);
        sum_totals(root);
        self.report.inventory_incomplete = root.inventory != InventoryState::Complete;
        collect_reshown(root, &mut self.report.reshown_inventory);
        if let Kind::Dir { totals, .. } = &root.kind {
            self.report.totals.add(totals);
        }
        if let Some(status) = &self.status {
            self.report.deleted.extend(status.deleted.iter().cloned());
        }
        if let Some(config) = &self.config {
            self.report.configs.push((
                provenance::relative(&config.path, &self.abs),
                config.unused(),
            ));
        }
    }
}

impl Builder<'_> {
    /// Reads file contents for line counts. Listed files come first, then
    /// files inside collapsed directories (`--count all`), each in listing
    /// order. Finite allowances charge actual reads before admitting the next
    /// file, so binary probes and failed opens leave unused bytes available.
    fn count(&mut self, root: &mut Node) {
        let mut listed = Vec::new();
        let mut unlisted = Vec::new();
        pending_files(
            root,
            Row::Listed,
            entries(self.opts),
            &mut listed,
            &mut unlisted,
        );
        if self.resolved.count == Count::Shown {
            for node in unlisted.drain(..) {
                node.kind = Kind::File(Lines::NotShown);
                self.report.not_shown += 1;
            }
        }
        let mut left = self.resolved.read_limit;
        let mut plan = Vec::new();
        let mut queued = Vec::new();
        for node in listed.into_iter().chain(unlisted) {
            if node.size > COUNT_LIMIT {
                node.kind = Kind::File(Lines::TooLarge);
                self.report.too_large += 1;
                continue;
            }
            plan.push((self.abs.join(&node.rel), node.size));
            queued.push(node);
        }
        let counted = if let Some(left) = &mut left {
            plan.iter()
                .map(|(path, size)| {
                    let before = *left;
                    let lines = count_bounded(path, *size, left);
                    (lines, before - *left)
                })
                .collect()
        } else {
            count_all(&plan)
        };
        for (node, (lines, bytes)) in queued.into_iter().zip(counted) {
            self.report.content_bytes_read += bytes;
            match lines {
                Lines::ReadLimit => self.report.read_limited += 1,
                Lines::Unreadable => {
                    self.report.unreadable_files += 1;
                    self.report.unreadable.push(format!(
                        "{}: contents unreadable",
                        crate::render::escape_os(node.rel.as_os_str())
                    ));
                }
                Lines::TooLarge => self.report.too_large += 1,
                _ => {}
            }
            node.kind = Kind::File(lines);
        }
    }
}

/// Whether a node's row appears in the listing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Row {
    Listed,
    Unlisted,
}

/// Files awaiting a count, split by whether their row is listed.
fn pending_files<'a>(
    node: &'a mut Node,
    row: Row,
    entries: Entries,
    shown: &mut Vec<&'a mut Node>,
    hidden: &mut Vec<&'a mut Node>,
) {
    if matches!(node.kind, Kind::File(Lines::Pending)) {
        match row {
            Row::Listed => shown.push(node),
            Row::Unlisted => hidden.push(node),
        }
        return;
    }
    let expanded = row == Row::Listed && node.cut.is_none();
    if let Kind::Dir { children, .. } = &mut node.kind {
        for child in children.iter_mut() {
            let child_row = if expanded
                && (entries == Entries::All || matches!(child.kind, Kind::Dir { .. }))
            {
                Row::Listed
            } else {
                Row::Unlisted
            };
            pending_files(child, child_row, entries, shown, hidden);
        }
    }
}

/// Bottom-up totals. Re-shown children are excluded from their parent;
/// summarized placeholders keep the totals their scan produced.
fn sum_totals(node: &mut Node) -> Totals {
    if node.summarized {
        return match &node.kind {
            Kind::Dir { totals, .. } => *totals,
            _ => Totals::default(),
        };
    }
    let Kind::Dir { children, totals } = &mut node.kind else {
        return Totals::default();
    };
    let mut sum = Totals::default();
    for child in children.iter_mut() {
        let inner = sum_totals(child);
        if child.reshown {
            continue;
        }
        match &child.kind {
            Kind::Dir { .. } if child.cut != Some(Cut::GitMetadata) => {
                if child.inventory != InventoryState::Complete {
                    node.inventory = InventoryState::Incomplete;
                }
                sum.dirs += 1;
                sum.add(&inner);
            }
            Kind::File(lines) => {
                sum.files += 1;
                sum.bytes += child.size;
                match lines {
                    Lines::Text(n) => sum.lines += n,
                    Lines::Binary => {}
                    _ => sum.uncounted += 1,
                }
            }
            _ => {}
        }
    }
    *totals = sum;
    sum
}

fn collect_reshown(node: &Node, inventories: &mut Vec<(String, Inventory)>) {
    if node.reshown {
        let totals = match &node.kind {
            Kind::Dir { totals, .. } => match node.inventory {
                InventoryState::NotScanned => Inventory::NotScanned,
                InventoryState::Complete => Inventory::Complete(*totals),
                InventoryState::Incomplete => Inventory::Incomplete(*totals),
            },
            Kind::File(lines) => Inventory::Complete(Totals {
                files: 1,
                bytes: node.size,
                lines: if let Lines::Text(n) = lines { *n } else { 0 },
                uncounted: u64::from(!matches!(lines, Lines::Text(_) | Lines::Binary)),
                ..Totals::default()
            }),
            _ => Inventory::Complete(Totals::default()),
        };
        inventories.push((node.rel.display().to_string(), totals));
        return;
    }
    if let Kind::Dir { children, .. } = &node.kind {
        for child in children {
            collect_reshown(child, inventories);
        }
    }
}

/// GNU `-v` order: digit runs compare by value, everything else by byte.
fn version_cmp(a: &str, b: &str) -> Ordering {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    let (mut i, mut j) = (0, 0);
    while i < a.len() && j < b.len() {
        if a[i].is_ascii_digit() && b[j].is_ascii_digit() {
            let (si, sj) = (i, j);
            while i < a.len() && a[i].is_ascii_digit() {
                i += 1;
            }
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            let (na, nb) = (trim_zeros(&a[si..i]), trim_zeros(&b[sj..j]));
            let order = na.len().cmp(&nb.len()).then_with(|| na.cmp(nb));
            if order != Ordering::Equal {
                return order;
            }
        } else {
            if a[i] != b[j] {
                return a[i].cmp(&b[j]);
            }
            i += 1;
            j += 1;
        }
    }
    (a.len() - i).cmp(&(b.len() - j)).then_with(|| a.cmp(b))
}

fn trim_zeros(digits: &[u8]) -> &[u8] {
    let first = digits
        .iter()
        .position(|&d| d != b'0')
        .unwrap_or(digits.len());
    &digits[first..]
}

fn placeholder(rel: PathBuf, name: &str, cut: Cut) -> Node {
    Node {
        reshown: false,
        summarized: true,
        inventory: InventoryState::NotScanned,
        hidden_entries: 0,
        name: name.to_owned(),
        rel,
        kind: Kind::Dir {
            children: Vec::new(),
            totals: Totals::default(),
        },
        git: Vec::new(),
        note: None,
        size: 0,
        mtime: None,
        cut: Some(cut),
    }
}

/// Total lines: newline count, plus one for a final line without a newline.
/// NUL within the first 8000 bytes classifies the file as binary.
#[cfg(test)]
fn count_lines(path: &Path, size: u64) -> Lines {
    let mut allowance = u64::MAX;
    count_bounded(path, size, &mut allowance)
}

/// Charge only bytes returned by read, including binary probes and reads that
/// precede an error. At a boundary, descriptor metadata verifies the observed
/// length without reading an extra byte. This is not a filesystem snapshot.
fn count_bounded(path: &Path, size: u64, allowance: &mut u64) -> Lines {
    if size > COUNT_LIMIT {
        return Lines::TooLarge;
    }
    if size > *allowance {
        return Lines::ReadLimit;
    }
    let Ok(mut file) = File::open(path) else {
        return Lines::Unreadable;
    };
    let mut buf = vec![0_u8; 64 * 1024];
    let (mut lines, mut seen, mut last) = (0_u64, 0_usize, b'\n');
    loop {
        let consumed = u64::try_from(seen).expect("read count fits u64");
        let remaining = (*allowance).min(COUNT_LIMIT - consumed);
        if remaining == 0 {
            match file.metadata() {
                Ok(meta) if meta.is_file() && meta.len() == consumed => break,
                Err(_) => return Lines::Unreadable,
                _ if consumed == COUNT_LIMIT => return Lines::TooLarge,
                _ => return Lines::ReadLimit,
            }
        }
        let probe = if seen < BINARY_PROBE {
            BINARY_PROBE - seen
        } else {
            buf.len()
        };
        let length = probe.min(usize::try_from(remaining).unwrap_or(usize::MAX));
        let n = match file.read(&mut buf[..length]) {
            Ok(0) => break,
            Ok(n) => n,
            Err(err) if err.kind() == ErrorKind::Interrupted => continue,
            Err(_) => return Lines::Unreadable,
        };
        *allowance -= u64::try_from(n).expect("buffer length fits u64");
        let chunk = &buf[..n];
        if seen < BINARY_PROBE && chunk[..n.min(BINARY_PROBE - seen)].contains(&0) {
            return Lines::Binary;
        }
        let newlines = memchr::memchr_iter(b'\n', chunk).count();
        lines += u64::try_from(newlines).unwrap_or(u64::MAX);
        last = chunk[n - 1];
        seen = seen.saturating_add(n);
    }
    if seen > 0 && last != b'\n' {
        lines += 1;
    }
    Lines::Text(lines)
}

fn has_entries(node: &Node) -> bool {
    match &node.kind {
        Kind::Dir { children, .. } => !children.is_empty(),
        _ => false,
    }
}

/// Marks directories at `level` (root is 0) as cut; returns how many hold entries.
fn cut_at_level(node: &mut Node, depth: usize, level: usize) -> u64 {
    let Kind::Dir { children, .. } = &mut node.kind else {
        return 0;
    };
    let mut cuts = 0;
    for child in children.iter_mut() {
        if !matches!(child.kind, Kind::Dir { .. }) || child.cut.is_some() {
            continue;
        }
        if depth + 1 >= level {
            if has_entries(child) {
                child.cut = Some(Cut::Level(level));
                cuts += 1;
            }
        } else {
            cuts += cut_at_level(child, depth + 1, level);
        }
    }
    cuts
}

/// Lines a directory adds when expanded.
pub(crate) fn visible(node: &Node, entries: Entries) -> usize {
    match &node.kind {
        Kind::Dir { children, .. } if node.cut.is_none() => children
            .iter()
            .filter(|c| entries == Entries::All || matches!(c.kind, Kind::Dir { .. }))
            .map(|c| 1 + usize::from(!matches!(c.kind, Kind::Dir { .. }) && c.git.len() > 1))
            .sum(),
        _ => 0,
    }
}

/// Breadth-first: expand each level's directories cheapest first while the
/// listing fits `budget` lines; directories that do not fit collapse to one
/// summary line. The root is always expanded.
fn budget_plan(root: &Node, budget: usize, entries: Entries) -> HashSet<PathBuf> {
    let mut collapse = HashSet::new();
    let mut used = 1 + usize::from(root.note.is_some()) + visible(root, entries);
    let mut frontier = vec![root];
    while !frontier.is_empty() {
        let mut candidates: Vec<(usize, &Node)> = frontier
            .iter()
            .filter_map(|n| match &n.kind {
                Kind::Dir { children, .. } => Some(children.iter()),
                _ => None,
            })
            .flatten()
            .filter(|c| visible(c, entries) > 0)
            .map(|c| (visible(c, entries), c))
            .collect();
        candidates.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.rel.cmp(&b.1.rel)));
        let mut next = Vec::new();
        for (cost, node) in candidates {
            if used + cost <= budget {
                used += cost;
                next.push(node);
            } else {
                collapse.insert(node.rel.clone());
            }
        }
        frontier = next;
    }
    collapse
}

fn apply_budget(node: &mut Node, collapse: &HashSet<PathBuf>) {
    if let Kind::Dir { children, .. } = &mut node.kind {
        for child in children.iter_mut() {
            if collapse.contains(&child.rel) {
                child.cut = Some(Cut::Budget);
            } else if child.cut.is_none() {
                apply_budget(child, collapse);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_file(name: &str, bytes: &[u8]) -> PathBuf {
        let path = std::env::temp_dir().join(format!("tree-lines-{}-{name}", std::process::id()));
        fs::write(&path, bytes).expect("write fixture");
        path
    }

    #[test]
    fn counts_total_lines_including_unterminated_last_line() {
        for (name, bytes, expected) in [
            ("empty", &b""[..], 0),
            ("one", b"a\n", 1),
            ("unterminated", b"a\nb", 2),
            ("blank-lines", b"\n\n\n", 3),
        ] {
            let path = temp_file(name, bytes);
            assert_eq!(count_lines(&path, 0), Lines::Text(expected), "{name}");
            fs::remove_file(path).expect("remove fixture");
        }
    }

    #[test]
    fn nul_in_probe_is_binary_and_oversize_is_not_read() {
        let path = temp_file("binary", b"ab\x00cd\n");
        assert_eq!(count_lines(&path, 6), Lines::Binary, "NUL byte");
        assert_eq!(
            count_lines(&path, COUNT_LIMIT + 1),
            Lines::TooLarge,
            "size cap"
        );
        fs::remove_file(path).expect("remove fixture");
    }

    #[test]
    fn binary_probe_refunds_allowance_before_next_file() {
        let dir = std::env::temp_dir().join(format!("tree-refund-{}", std::process::id()));
        fs::create_dir_all(&dir).expect("create fixture");
        fs::write(dir.join("a"), vec![0; 16000]).expect("binary fixture");
        fs::write(dir.join("b"), b"text\n").expect("text fixture");
        let opts = Options {
            no_config: true,
            ignore_rules: Some(IgnoreRules::Off),
            read_limit: Some(ReadLimit::Bytes(16000)),
            ..Options::default()
        };
        let listing = build(dir.as_os_str(), &opts).expect("listing");
        fs::remove_dir_all(dir).expect("remove fixture");
        assert_eq!(
            listing.report.totals.lines, 1,
            "unused binary reservation admits text"
        );
    }

    #[test]
    fn unreadable_directory_makes_ancestor_inventory_incomplete() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("tree-locked-{}", std::process::id()));
        let locked = dir.join("locked");
        fs::create_dir_all(&locked).expect("create fixture");
        fs::write(locked.join("unknown"), b"x\n").expect("write fixture");
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o0)).expect("lock fixture");
        let listing = build(
            dir.as_os_str(),
            &Options {
                no_config: true,
                ignore_rules: Some(IgnoreRules::Off),
                ..Options::default()
            },
        );
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o700)).expect("unlock fixture");
        fs::remove_dir_all(dir).expect("remove fixture");
        let listing = listing.expect("listing");
        assert_eq!(
            listing.root.inventory,
            InventoryState::Incomplete,
            "unknown descendants must not look like an empty complete subtree"
        );
    }

    #[test]
    fn actual_read_accounting_handles_stale_sizes_and_boundaries() {
        let path = temp_file("growing", b"a\nb\nc\n");
        let mut left = 4;
        assert_eq!(count_bounded(&path, 2, &mut left), Lines::ReadLimit);
        assert_eq!(left, 0, "growth cannot read past the allowance");
        let mut left = 6;
        assert_eq!(count_bounded(&path, 2, &mut left), Lines::Text(3));
        assert_eq!(left, 0, "exact EOF requires no extra byte");
        fs::remove_file(&path).expect("remove fixture");
        let mut left = 6;
        assert_eq!(count_bounded(&path, 2, &mut left), Lines::Unreadable);
        assert_eq!(left, 6, "failed open consumes no bytes");
    }

    #[test]
    fn bounded_depth_does_not_inventory_descendants() {
        let dir = std::env::temp_dir().join(format!("tree-depth-{}", std::process::id()));
        fs::create_dir_all(dir.join("child/deeper")).expect("fixture");
        fs::write(dir.join("child/deeper/file"), b"x\n").expect("fixture");
        let listing = build(
            dir.as_os_str(),
            &Options {
                no_config: true,
                level: Some(1),
                ..Options::default()
            },
        )
        .expect("listing");
        let full = build(
            dir.as_os_str(),
            &Options {
                no_config: true,
                level: Some(1),
                inventory: Some(InventoryMode::Full),
                ..Options::default()
            },
        )
        .expect("full listing");
        fs::remove_dir_all(dir).expect("cleanup");
        let Kind::Dir { children, .. } = &listing.root.kind else {
            panic!("directory")
        };
        assert_eq!(children[0].inventory, InventoryState::NotScanned);
        assert_eq!(listing.report.totals.files, 0);
        assert!(listing.report.inventory_incomplete, "unknown descendants");
        assert_eq!(full.report.totals.files, 1);
        assert_eq!(full.report.totals.lines, 1);
        assert!(!full.report.inventory_incomplete, "full inventory");
    }

    #[test]
    fn version_sort_compares_digit_runs_by_value() {
        let mut names = ["f10", "f9", "f1", "f01", "g", "f"];
        names.sort_by(|a, b| version_cmp(a, b));
        assert_eq!(names, ["f", "f01", "f1", "f9", "f10", "g"]);
    }
}
