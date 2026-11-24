//! Tree-compatible listing options and explicit configuration operations.

use std::ffi::OsString;

use anyhow::{Context, Result, bail};

/// Listing rows before directories collapse; headers and footer are additional.
pub(crate) const DEFAULT_BUDGET: usize = 12_000;

pub(crate) const SUPPORTED: &str = "\
supported: -a -d -f -s -h -D -v -C -n -J -L <level> -I <pattern> -P <pattern>
           --noreport --dirsfirst --gitignore --ignore --no-ignore
           --budget <entries> --count <all|shown|none> --read-limit <size>
           --inventory <bounded|full> --metafirst --no-config --init --print-config
           --scan-collapsed --raw --help --version";

pub(crate) const HELP: &str = "\
usage: tree [options] [--] [directory ...]

Tree uses ripgrep's ignore rules (.gitignore, .ignore, .rgignore,
and git excludes), with line counts, git status, and a footer accounting
for everything not shown. No depth limit by default; output past the entry
budget collapses whole directories into summary lines. A .tree.toml in the
listed directory or an ancestor configures visibility and presentation.

  -a              include dotfiles
  -d              directories only
  -f              print each entry's path from the given root
  -s              show sizes in bytes
  -h              show human-readable sizes (overrides -s)
  -D              show modification times (UTC)
  -v              version sort: file9 before file10
  -L <level>      descend at most <level> directories (>= 1)
  -I <pattern>    exclude names matching <pattern> ('|' separates globs)
  -P <pattern>    list only files matching <pattern> ('|' separates globs)
  -C, -n          force color on / off (default: on for terminals; honors
                  NO_COLOR and CLICOLOR_FORCE)
  -J              JSON tree with a separate report after each root
  --no-ignore     do not honor .gitignore, .ignore, .rgignore, git excludes
  --ignore, --gitignore
                  honor them (the default; overrides gitignore = false)
  --noreport      omit the footer
  --budget <n>    entry budget before directories collapse (default 12000)
  --inventory <mode>
                  bounded (default): depth, budget and configuration cuts stop
                  traversal; full: retain descendant inventories behind cuts
  --count <mode>  all (default): every eligible file subject to --read-limit;
                  shown: listed files only; none: no file contents
  --read-limit <size>
                  cap actual content bytes read per listing root
                  (default 4G; K/M/G/T binary; 'unlimited'); files larger
                  than the remaining allowance are skipped. Listed files
                  have priority: depth and budget can affect partial totals.
  --raw ...       run eza --tree with the remaining arguments
  --no-filter ... alias for --raw; must be the first argument
  --scan-collapsed count files and bytes in collapsed re-shown directories
  --metafirst     metadata before tree drawing (the only layout)
  --no-config     bypass .tree.toml discovery
  --init [dir]    create .tree.toml; never overwrite an existing file
  --print-config  print effective settings and their sources as JSON
  --dirsfirst     accepted for compatibility; directories are always first

Columns: LINES is total text lines, including a final unterminated line.
N+ is incomplete; — is uncounted; bin is binary. Reasons accompany uncounted
files. GIT is the exact two-character porcelain record; + means multiple
records printed below the row (␠ denotes a space), and * means changes below.
▸ marks unexpanded contents; depth is stated once in the footer,
while brackets identify other collapse reasons.
Footer omission paths and rule sources are relative to the listing root.
";

/// Whether the base ignore rules (.gitignore, .ignore, .rgignore, git
/// excludes) apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum IgnoreRules {
    Honor,
    Off,
}

/// Sibling order. Directories always come first.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Sort {
    /// Byte order of names: identical in every locale.
    Name,
    /// GNU `-v`: runs of digits compare numerically.
    Version,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ColorChoice {
    Auto,
    Always,
    Never,
}

/// Which regular files have their lines read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Count {
    /// Every represented file, listed or inside a collapsed directory.
    All,
    /// Listed rows only; collapsed directories keep metadata totals.
    Shown,
    /// No file contents are read.
    None,
}

impl Count {
    pub(crate) const VALID: &'static str = "all, shown, none";

    pub(crate) fn parse(value: &str) -> Result<Self> {
        match value {
            "all" => Ok(Self::All),
            "shown" => Ok(Self::Shown),
            "none" => Ok(Self::None),
            _ => bail!("unknown count mode '{value}'; valid: {}", Self::VALID),
        }
    }

    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Shown => "shown",
            Self::None => "none",
        }
    }
}

/// Aggregate bytes read for line counts before remaining files go uncounted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum InventoryMode {
    #[default]
    Bounded,
    Full,
}

impl InventoryMode {
    pub(crate) fn parse(value: &str) -> Result<Self> {
        match value {
            "bounded" => Ok(Self::Bounded),
            "full" => Ok(Self::Full),
            _ => bail!("unknown inventory mode '{value}'; valid: bounded, full"),
        }
    }

    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::Bounded => "bounded",
            Self::Full => "full",
        }
    }
}

/// Aggregate bytes read for line counts before remaining files go uncounted.
pub(crate) const DEFAULT_READ_LIMIT: u64 = 4 << 30;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Sizes {
    Off,
    Bytes,
    Human,
}

#[derive(Debug)]
#[expect(
    clippy::struct_excessive_bools,
    reason = "each bool is an independent GNU tree flag; enums would only rename them"
)]
pub(crate) struct Options {
    pub(crate) roots: Vec<OsString>,
    pub(crate) all: bool,
    pub(crate) dirs_only: bool,
    pub(crate) full_path: bool,
    pub(crate) sizes: Sizes,
    pub(crate) init: bool,
    pub(crate) print_config: bool,
    pub(crate) no_config: bool,
    pub(crate) scan_collapsed: bool,
    pub(crate) dates: bool,
    pub(crate) json: bool,
    pub(crate) report: bool,
    pub(crate) level: Option<usize>,
    pub(crate) exclude: Vec<String>,
    pub(crate) include: Vec<String>,
    /// `--budget`; `None` defers to `.tree.toml`, then [`DEFAULT_BUDGET`].
    pub(crate) budget: Option<usize>,
    /// `--count`; `None` defers to `.tree.toml`, then [`Count::All`].
    pub(crate) count: Option<Count>,
    pub(crate) inventory: Option<InventoryMode>,
    /// `--read-limit`; `None` defers to `.tree.toml`, then [`DEFAULT_READ_LIMIT`].
    pub(crate) read_limit: Option<ReadLimit>,
    pub(crate) color: ColorChoice,
    /// `--no-ignore` / `--ignore`; `None` defers to `.tree.toml` `gitignore`.
    pub(crate) ignore_rules: Option<IgnoreRules>,
    pub(crate) ignore_source: Option<String>,
    pub(crate) sort: Sort,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            roots: Vec::new(),
            all: false,
            dirs_only: false,
            full_path: false,
            sizes: Sizes::Off,
            init: false,
            print_config: false,
            no_config: false,
            scan_collapsed: false,
            dates: false,
            json: false,
            report: true,
            level: None,
            exclude: Vec::new(),
            include: Vec::new(),
            budget: None,
            count: None,
            inventory: None,
            read_limit: None,
            color: ColorChoice::Auto,
            ignore_rules: None,
            ignore_source: None,
            sort: Sort::Name,
        }
    }
}

#[derive(Debug)]
pub(crate) enum Command {
    Help,
    Version,
    /// `--raw`: every other argument, in order, for `eza --tree`.
    Raw(Vec<OsString>),
    List(Options),
}

pub(crate) fn parse(args: Vec<OsString>) -> Result<Command> {
    let argument_count = args.len();
    let mut opts = Options::default();
    let mut args = args.into_iter();
    let mut positional_only = false;
    while let Some(arg) = args.next() {
        let text = match arg.to_str() {
            Some(text) if !positional_only => text.to_owned(),
            _ => {
                opts.roots.push(arg);
                continue;
            }
        };
        if text == "--" {
            positional_only = true;
        } else if text == "--raw" || text == "--no-filter" {
            if args.len() + 1 != argument_count {
                bail!("--raw must be the first argument; preceding options are not passed to eza");
            }
            return Ok(Command::Raw(args.collect()));
        } else if let Some(long) = text.strip_prefix("--") {
            if let Some(command) = parse_long(long, &mut args, &mut opts)? {
                return Ok(command);
            }
        } else if let Some(cluster) = text.strip_prefix('-').filter(|c| !c.is_empty()) {
            parse_short(cluster, &mut args, &mut opts)?;
        } else {
            opts.roots.push(arg);
        }
    }
    if opts.roots.is_empty() {
        opts.roots.push(OsString::from("."));
    }
    if opts.init && opts.print_config {
        bail!("--init and --print-config are mutually exclusive");
    }
    if (opts.init || opts.print_config) && opts.roots.len() != 1 {
        bail!("configuration operations require exactly one directory");
    }
    Ok(Command::List(opts))
}

fn parse_long(
    long: &str,
    args: &mut impl Iterator<Item = OsString>,
    opts: &mut Options,
) -> Result<Option<Command>> {
    let (name, inline) = match long.split_once('=') {
        Some((name, value)) => (name, Some(value.to_owned())),
        None => (long, None),
    };
    if matches!(name, "budget" | "count" | "read-limit" | "inventory") {
        let flag = format!("--{name}");
        let value = match inline {
            Some(value) => value,
            None => next_value(args, &flag)?,
        };
        match name {
            "budget" => opts.budget = Some(parse_positive(&value, &flag)?),
            "count" => opts.count = Some(Count::parse(&value).with_context(|| flag.clone())?),
            "inventory" => opts.inventory = Some(InventoryMode::parse(&value)?),
            _ => opts.read_limit = Some(parse_read_limit(&value).with_context(|| flag.clone())?),
        }
        return Ok(None);
    }
    if inline.is_some() {
        bail!("option '--{name}' takes no value\n{SUPPORTED}");
    }
    match name {
        "help" => return Ok(Some(Command::Help)),
        "version" => return Ok(Some(Command::Version)),
        "init" => opts.init = true,
        "print-config" => opts.print_config = true,
        "no-config" => opts.no_config = true,
        "scan-collapsed" => opts.scan_collapsed = true,
        "noreport" => opts.report = false,
        "no-ignore" | "ignore" | "gitignore" => {
            opts.ignore_rules = Some(if name == "no-ignore" {
                IgnoreRules::Off
            } else {
                IgnoreRules::Honor
            });
            opts.ignore_source = Some(format!("--{name}"));
        }
        "dirsfirst" | "metafirst" => {}
        _ => bail!("unsupported option '--{name}'\n{SUPPORTED}"),
    }
    Ok(None)
}

fn parse_short(
    cluster: &str,
    args: &mut impl Iterator<Item = OsString>,
    opts: &mut Options,
) -> Result<()> {
    for (index, flag) in cluster.char_indices() {
        match flag {
            'a' => opts.all = true,
            'd' => opts.dirs_only = true,
            'f' => opts.full_path = true,
            's' => {
                if opts.sizes != Sizes::Human {
                    opts.sizes = Sizes::Bytes;
                }
            }
            'h' => opts.sizes = Sizes::Human,
            'D' => opts.dates = true,
            'v' => opts.sort = Sort::Version,
            'J' => opts.json = true,
            'C' => opts.color = ColorChoice::Always,
            'n' => opts.color = ColorChoice::Never,
            'L' | 'I' | 'P' => {
                let attached = &cluster[index + flag.len_utf8()..];
                let value = if attached.is_empty() {
                    next_value(args, &format!("-{flag}"))?
                } else {
                    attached.to_owned()
                };
                match flag {
                    'L' => opts.level = Some(parse_positive(&value, "-L")?),
                    'I' => opts.exclude.extend(split_patterns(&value)),
                    _ => opts.include.extend(split_patterns(&value)),
                }
                return Ok(());
            }
            _ => bail!("unsupported option '-{flag}'\n{SUPPORTED}"),
        }
    }
    Ok(())
}

fn next_value(args: &mut impl Iterator<Item = OsString>, flag: &str) -> Result<String> {
    let value = args
        .next()
        .with_context(|| format!("option '{flag}' requires a value"))?;
    value
        .into_string()
        .map_err(|raw| anyhow::anyhow!("option '{flag}': value '{}' is not UTF-8", raw.display()))
}

fn parse_positive(value: &str, flag: &str) -> Result<usize> {
    let parsed: usize = value
        .parse()
        .with_context(|| format!("option '{flag}' needs a positive integer, got '{value}'"))?;
    if parsed == 0 {
        bail!("option '{flag}' needs a positive integer, got '0'");
    }
    Ok(parsed)
}

/// Aggregate bytes of file contents read for line counts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ReadLimit {
    Bytes(u64),
    Unlimited,
}

impl ReadLimit {
    pub(crate) fn bytes(self) -> Option<u64> {
        match self {
            Self::Bytes(n) => Some(n),
            Self::Unlimited => None,
        }
    }
}

/// `4G`, `512M`, `64K`, `100` (bytes; binary multiples; optional `iB`/`B`),
/// or `unlimited`.
pub(crate) fn parse_read_limit(value: &str) -> Result<ReadLimit> {
    if value == "unlimited" {
        return Ok(ReadLimit::Unlimited);
    }
    let unit = value
        .strip_suffix("iB")
        .or_else(|| value.strip_suffix('B'))
        .unwrap_or(value);
    let (digits, shift) = match unit.char_indices().last() {
        Some((i, 'K')) => (&unit[..i], 10),
        Some((i, 'M')) => (&unit[..i], 20),
        Some((i, 'G')) => (&unit[..i], 30),
        Some((i, 'T')) => (&unit[..i], 40),
        _ => (unit, 0),
    };
    let number: u64 = digits.parse().with_context(|| {
        format!("size '{value}': expected <number>[K|M|G|T] (binary multiples) or 'unlimited'")
    })?;
    number
        .checked_mul(1_u64 << shift)
        .map(ReadLimit::Bytes)
        .with_context(|| format!("size '{value}' overflows"))
}

fn split_patterns(value: &str) -> impl Iterator<Item = String> + '_ {
    value
        .split('|')
        .filter(|p| !p.is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn list(args: &[&str]) -> Result<Options> {
        match parse(args.iter().map(OsString::from).collect())? {
            Command::List(opts) => Ok(opts),
            other => bail!("expected a listing, got {other:?}"),
        }
    }

    #[test]
    fn defaults_to_current_directory_without_depth_limit() {
        let opts = list(&[]).expect("empty command line parses");
        assert_eq!(opts.roots, vec![OsString::from(".")]);
        assert_eq!(opts.level, None);
        assert_eq!(opts.budget, None);
        assert!(opts.report, "footer on by default");
    }

    #[test]
    fn level_accepts_separate_attached_and_clustered_forms() {
        for form in [&["-L", "3"][..], &["-L3"], &["-aL", "3"], &["-aL3"]] {
            let opts = list(form).expect("level form parses");
            assert_eq!(opts.level, Some(3), "form {form:?}");
        }
        assert!(
            list(&["-aL3"]).expect("cluster parses").all,
            "-a in cluster"
        );
    }

    #[test]
    fn rejects_bad_levels_and_unknown_flags() {
        assert!(list(&["-L", "x"]).is_err(), "non-numeric level");
        assert!(list(&["-L", "0"]).is_err(), "zero level");
        assert!(list(&["-L"]).is_err(), "missing level");
        let err = list(&["--bogus"])
            .expect_err("unknown long flag")
            .to_string();
        assert!(
            err.contains("--bogus") && err.contains("supported:"),
            "{err}"
        );
        assert!(list(&["-q"]).is_err(), "unknown short flag");
        assert!(list(&["--noreport=1"]).is_err(), "value on a switch");
    }

    #[test]
    fn patterns_split_on_pipe() {
        let opts = list(&["-I", "a|b", "-P*.rs"]).expect("patterns parse");
        assert_eq!(opts.exclude, ["a", "b"]);
        assert_eq!(opts.include, ["*.rs"]);
    }

    #[test]
    fn raw_preserves_following_arguments_and_rejects_preceding_arguments() {
        for preceding in ["-a", "--metafirst", "."] {
            assert!(
                parse([preceding, "--raw", "-L", "2"].map(OsString::from).to_vec()).is_err(),
                "--raw must reject preceding argument {preceding}"
            );
        }
        let command =
            parse(["--raw", "-a", "-L", "2"].map(OsString::from).to_vec()).expect("raw parses");
        match command {
            Command::Raw(rest) => assert_eq!(rest, ["-a", "-L", "2"].map(OsString::from)),
            other => panic!("expected raw, got {other:?}"),
        }
    }

    #[test]
    fn double_dash_ends_options() {
        let opts = list(&["--", "-a"]).expect("double dash parses");
        assert_eq!(opts.roots, vec![OsString::from("-a")]);
        assert!(!opts.all, "-a after -- is a path");
    }
}
