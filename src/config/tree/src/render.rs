//! Metadata-first text trees and JSON listings with one report per root.
//!
//! Every name, link target, and note printed as text passes through
//! [`escape`]: a control character in a file name would otherwise start a
//! new line (a fake entry) or a terminal escape sequence.

use std::borrow::Cow;
use std::collections::BTreeMap;
use std::ffi::OsStr;
use std::io::{IsTerminal, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Result;
use serde_json::{Value, json};

use crate::args::{ColorChoice, Options};
use crate::walk::{
    Cut, Entries, Inventory, InventoryState, Kind, Lines, LinkState, Listing, Node, Report,
    RulesOff, SizeColumn, Totals, entries,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Color {
    On,
    Off,
}

/// `-C`/`-n` win; otherwise `CLICOLOR_FORCE` (not "0") forces, a non-empty
/// `NO_COLOR` disables, and color is on only when stdout is a terminal.
pub(crate) fn color(choice: ColorChoice) -> Color {
    let env = |name: &str| std::env::var_os(name).filter(|v| !v.is_empty());
    let on = match choice {
        ColorChoice::Always => true,
        ColorChoice::Never => false,
        ColorChoice::Auto => {
            if env("CLICOLOR_FORCE").is_some_and(|v| v != "0") {
                true
            } else {
                env("NO_COLOR").is_none() && std::io::stdout().is_terminal()
            }
        }
    };
    if on { Color::On } else { Color::Off }
}

/// Escape backslashes and Unicode control characters; preserve other Unicode.
pub(crate) fn escape(text: &str) -> Cow<'_, str> {
    let control = |c: char| {
        c.is_control()
            || c == '\\'
            || matches!(c, '\u{061c}' | '\u{200e}' | '\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
    };
    if !text.chars().any(control) {
        return Cow::Borrowed(text);
    }
    Cow::Owned(
        text.chars()
            .map(|c| {
                if control(c) {
                    c.escape_default().to_string()
                } else {
                    c.to_string()
                }
            })
            .collect(),
    )
}

/// Preserve invalid filename bytes with hexadecimal escapes, without replacement characters.
pub(crate) fn escape_os(value: &OsStr) -> String {
    use std::fmt::Write as _;
    let mut bytes = value.as_bytes();
    let mut result = String::new();
    while !bytes.is_empty() {
        match std::str::from_utf8(bytes) {
            Ok(text) => {
                result.push_str(&escape(text));
                break;
            }
            Err(error) => {
                let valid = error.valid_up_to();
                result.push_str(&escape(&String::from_utf8_lossy(&bytes[..valid])));
                let invalid = error.error_len().unwrap_or(bytes.len() - valid);
                for byte in &bytes[valid..valid + invalid] {
                    write!(result, "\\x{byte:02x}").expect("writing into a String cannot fail");
                }
                bytes = &bytes[valid + invalid..];
            }
        }
    }
    result
}

struct Paint(Color);

impl Paint {
    fn wrap(&self, code: &str, text: &str) -> String {
        match self.0 {
            Color::On => format!("\x1b[{code}m{text}\x1b[0m"),
            Color::Off => text.to_owned(),
        }
    }
}

fn plural(n: u64, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

/// Binary-prefixed size with one decimal from KiB up: 9 B, 6.5 KiB, 1.2 GiB.
pub(crate) fn human(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["KiB", "MiB", "GiB", "TiB", "PiB"];
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    let mut unit = 0;
    let mut scale: u128 = 1024;
    while unit + 1 < UNITS.len() && u128::from(bytes) >= scale * 1024 {
        scale *= 1024;
        unit += 1;
    }
    let tenths = (u128::from(bytes) * 10 + scale / 2) / scale;
    format!("{}.{} {}", tenths / 10, tenths % 10, UNITS[unit])
}

/// `YYYY-MM-DD HH:MM UTC` without a time-zone database.
fn utc(time: SystemTime) -> String {
    let secs = time
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX));
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02} {:02}:{:02} UTC",
        rem / 3600,
        rem % 3600 / 60
    )
}

fn dir_meta(totals: &Totals, cut: Option<Cut>) -> String {
    if cut == Some(Cut::GitMetadata) {
        return "—".to_owned();
    }
    if totals.files == 0 {
        return "0".to_owned();
    }
    if totals.uncounted == totals.files {
        return "—".to_owned();
    }
    if totals.uncounted > 0 {
        return format!("{}+", totals.lines);
    }
    totals.lines.to_string()
}

fn file_meta(lines: Lines) -> String {
    match lines {
        Lines::Text(n) => n.to_string(),
        Lines::Binary => "bin".to_owned(),
        Lines::TooLarge
        | Lines::Unreadable
        | Lines::NotCounted
        | Lines::NotShown
        | Lines::ReadLimit
        | Lines::Pending => "—".to_owned(),
    }
}

fn line_state(lines: Lines) -> &'static str {
    match lines {
        Lines::Text(_) => "text",
        Lines::Binary => "binary",
        Lines::TooLarge => "too_large",
        Lines::Unreadable => "unreadable",
        Lines::NotCounted => "not_counted",
        Lines::NotShown => "not_shown",
        Lines::ReadLimit => "read_limit",
        Lines::Pending => "pending",
    }
}

fn cut_text(cut: Cut) -> String {
    match cut {
        Cut::Level(level) => format!("-L {level}"),
        Cut::Budget => "budget".to_owned(),
        Cut::Config => ".tree.toml".to_owned(),
        Cut::GitMetadata => "git metadata".to_owned(),
    }
}

struct TextCtx<'a> {
    opts: &'a Options,
    paint: Paint,
    label: &'a str,
    sizes: SizeColumn,
    entries: Entries,
    width: usize,
}

impl TextCtx<'_> {
    fn columns(&self, node: &Node) -> String {
        let lines = match &node.kind {
            Kind::Dir { totals, .. }
                if node.inventory == InventoryState::Incomplete && totals.lines > 0 =>
            {
                format!("{}+", totals.lines)
            }
            Kind::Dir { .. } if node.inventory != InventoryState::Complete => "—".to_owned(),
            Kind::Dir { totals, .. } if totals.files == 0 && node.hidden_entries > 0 => {
                "—".to_owned()
            }
            Kind::Dir { totals, .. } => dir_meta(totals, node.cut),
            Kind::File(lines) => file_meta(*lines),
            _ => "—".to_owned(),
        };
        let git = match &node.kind {
            Kind::Dir { .. } if !node.git.is_empty() => " *",
            _ if node.git.len() > 1 => " +",
            _ => node.git.first().map_or("  ", String::as_str),
        };
        let mut columns = format!("{lines:>width$}  {git}   ", width = self.width);
        if node.inventory != InventoryState::Complete && self.sizes != SizeColumn::Off {
            return format!("{columns}{:>12}  ", "—");
        }
        let bytes = match &node.kind {
            Kind::Dir { totals, .. } => totals.bytes,
            _ => node.size,
        };
        match self.sizes {
            SizeColumn::Off => {}
            SizeColumn::Bytes => columns = format!("{columns}{bytes:>12}  "),
            SizeColumn::Human => columns = format!("{columns}{:>12}  ", human(bytes)),
        }
        columns
    }
    fn name(&self, node: &Node) -> String {
        let display = if self.opts.full_path {
            escape_os(Path::new(self.label).join(&node.rel).as_os_str())
        } else {
            escape_os(node.rel.file_name().unwrap_or(OsStr::new(&node.name)))
        };
        match &node.kind {
            Kind::Dir { .. } => self.paint.wrap("1;34", &format!("{display}/")),
            Kind::Link { target, state } => {
                let broken = match state {
                    LinkState::Resolves => "",
                    LinkState::Broken => " (broken)",
                };
                format!(
                    "{} -> {}{broken}",
                    self.paint.wrap("36", &display),
                    escape_os(target.as_os_str())
                )
            }
            Kind::File(_) | Kind::Other => display,
        }
    }

    fn line(&self, node: &Node) -> String {
        let mut out = if node.cut.is_some() {
            format!("▸ {}", self.name(node))
        } else {
            self.name(node)
        };
        if self.opts.dates
            && let Some(mtime) = node.mtime
        {
            out.push_str("  ");
            out.push_str(&utc(mtime));
        }
        if let Some(cut) = node.cut.filter(|cut| !matches!(cut, Cut::Level(_))) {
            out.push_str(&self.paint.wrap("35", &format!("  [{}]", cut_text(cut))));
        }
        match &node.kind {
            Kind::Dir { .. } if node.inventory != InventoryState::Complete => {}
            Kind::File(Lines::TooLarge) => out.push_str("  [too large]"),
            Kind::File(Lines::Unreadable) => out.push_str("  [unreadable]"),
            Kind::File(Lines::NotCounted | Lines::NotShown | Lines::Pending) => {
                out.push_str("  [not counted]");
            }
            Kind::File(Lines::ReadLimit) => out.push_str("  [read limit]"),
            Kind::Dir { totals, .. } if node.cut.is_some() => {
                out = format!(
                    "{out}  {}, {}",
                    plural(totals.files, "file", "files"),
                    human(totals.bytes)
                );
            }
            _ => {}
        }
        if node.hidden_entries > 0 {
            out = format!("{out}  [hidden: {}]", node.hidden_entries);
        }
        out
    }

    fn children(&self, out: &mut impl Write, node: &Node, prefix: &str) -> Result<()> {
        let Kind::Dir { children, .. } = &node.kind else {
            return Ok(());
        };
        if node.cut.is_some() {
            return Ok(());
        }
        let shown: Vec<&Node> = children
            .iter()
            .filter(|c| self.entries == Entries::All || matches!(c.kind, Kind::Dir { .. }))
            .collect();
        let plain = Self {
            paint: Paint(Color::Off),
            ..*self
        };
        let note_width = shown
            .iter()
            .filter(|node| node.note.is_some())
            .map(|node| plain.line(node).chars().count())
            .max()
            .unwrap_or(0);
        for (index, child) in shown.iter().enumerate() {
            let last = index + 1 == shown.len();
            let branch = self.paint.wrap("90", if last { "└── " } else { "├── " });
            let mut line = self.line(child);
            if let Some(note) = &child.note {
                let padding = note_width.saturating_sub(plain.line(child).chars().count()) + 2;
                line.push_str(
                    &self
                        .paint
                        .wrap("32", &format!("{:padding$}# {}", "", escape(note))),
                );
            }
            writeln!(out, "{}{prefix}{branch}{}", self.columns(child), line)?;
            if !matches!(child.kind, Kind::Dir { .. }) && child.git.len() > 1 {
                writeln!(
                    out,
                    "{:width$}{prefix}    git: {}",
                    "",
                    child
                        .git
                        .iter()
                        .map(|s| s.replace(' ', "␠"))
                        .collect::<Vec<_>>()
                        .join(" | "),
                    width = self.width + 7,
                )?;
            }
            let extension = if last { "    " } else { "│   " };
            let next = format!("{prefix}{}", self.paint.wrap("90", extension));
            self.children(out, child, &next)?;
        }
        Ok(())
    }
}

pub(crate) fn text(
    out: &mut impl Write,
    listings: &[Listing],
    opts: &Options,
    color: Color,
) -> Result<()> {
    for listing in listings {
        let ctx = TextCtx {
            opts,
            paint: Paint(color),
            label: &listing.label,
            sizes: listing.sizes,
            entries: entries(opts),
            width: displayed_nodes(&listing.root, opts)
                .iter()
                .map(|node| match &node.kind {
                    Kind::Dir { totals, .. } => dir_meta(totals, node.cut).chars().count(),
                    Kind::File(lines) => file_meta(*lines).chars().count(),
                    _ => 1,
                })
                .max()
                .unwrap_or(0)
                .max("LINES".len()),
        };
        let size_header = match listing.sizes {
            SizeColumn::Off => "",
            SizeColumn::Bytes => "       BYTES  ",
            SizeColumn::Human => "        SIZE  ",
        };
        writeln!(
            out,
            "{:>width$}  GIT  {size_header}PATH",
            "LINES",
            width = ctx.width
        )?;
        writeln!(
            out,
            "{}{}",
            ctx.columns(&listing.root),
            escape(&listing.label)
        )?;
        if let Some(note) = &listing.root.note {
            writeln!(
                out,
                "{:>width$}# {}",
                "",
                escape(note),
                width = ctx.width + 7
            )?;
        }
        ctx.children(out, &listing.root, "")?;
        if opts.report {
            let paint = Paint(color);
            writeln!(out)?;
            for line in footer(&listing.report, &listing.root, opts) {
                writeln!(out, "{}", paint.wrap("2", &line))?;
            }
        }
    }
    Ok(())
}

fn names(items: &[String]) -> String {
    escaped_names(
        &items
            .iter()
            .map(|s| escape(s).into_owned())
            .collect::<Vec<_>>(),
    )
}

fn escaped_names(items: &[String]) -> String {
    const LIMIT: usize = 10;
    let shown: Vec<&str> = items.iter().take(LIMIT).map(String::as_str).collect();
    let mut text = shown.join(", ");
    if items.len() > LIMIT {
        text = format!("{text}, … {} more (tree -J for all)", items.len() - LIMIT);
    }
    text
}

/// Omission groups printed as rows; the rest are summarized per category.
const GROUP_ROWS: usize = 20;
/// Maximum padded width of the `source: pattern` column.
const SOURCE_WIDTH: usize = 48;

/// Why the line total is incomplete, by cause, with the flag that changes it.
fn uncounted_line(report: &Report) -> Option<String> {
    let totals = &report.totals;
    if totals.uncounted == 0 {
        return None;
    }
    let files = |n: u64| plural(n, "file", "files");
    let mut causes = Vec::new();
    if report.not_shown > 0 {
        causes.push(format!(
            "{} not listed (--count shown)",
            files(report.not_shown)
        ));
    }
    if report.read_limited > 0 {
        let limit = report
            .read_limit
            .map_or_else(|| "unlimited".to_owned(), human);
        causes.push(format!(
            "{} past --read-limit {limit}",
            files(report.read_limited)
        ));
    }
    if report.too_large > 0 {
        causes.push(format!(
            "{} over {}",
            files(report.too_large),
            human(crate::walk::COUNT_LIMIT)
        ));
    }
    if report.unreadable_files > 0 {
        causes.push(format!("{} unreadable", files(report.unreadable_files)));
    }
    let explained =
        report.not_shown + report.read_limited + report.too_large + report.unreadable_files;
    if totals.uncounted > explained {
        causes.push(format!(
            "{} not counted (--count none)",
            files(totals.uncounted - explained)
        ));
    }
    Some(format!("lines: incomplete; {}", causes.join(", ")))
}

/// Footer lines: summary first, then one line per kind of omission, each
/// naming its source and the flag that reveals it.
pub(crate) fn footer(report: &Report, root: &Node, opts: &Options) -> Vec<String> {
    let totals = &report.totals;
    let mut lines = vec![format!(
        "{}, {}, {}",
        plural(totals.dirs, "directory", "directories"),
        plural(totals.files, "file", "files"),
        plural(totals.lines, "line", "lines")
    )];
    lines.extend(uncounted_line(report));
    if report.inventory_incomplete {
        lines.push(
            "inventory: incomplete; totals are lower bounds; unknown descendants; use --inventory full for traversal cuts"
                .to_owned(),
        );
    }
    let (rows, reveals) = hidden_rows(report);
    lines.extend(rows);
    let unscanned = report
        .reshown_inventory
        .iter()
        .any(|(_, inventory)| matches!(inventory, Inventory::NotScanned));
    if !reveals.is_empty() || unscanned {
        lines.push("reveal (run from the listing root):".to_owned());
        for (category, command) in reveals {
            lines.push(format!("  {category}  {}", escape(command)));
        }
        if unscanned {
            lines.push("  inventory  tree --scan-collapsed".to_owned());
        }
    }
    lines.extend(omission_lines(report));
    lines.extend(rules_line(report));
    if displayed_nodes(root, opts).iter().any(|node| {
        node.cut.is_some()
            || !node.git.is_empty()
            || node.inventory != InventoryState::Complete
            || matches!(node.kind, Kind::File(lines) if !matches!(lines, Lines::Text(_)))
    }) {
        lines.push("legend: N+ incomplete lines; — uncounted; bin binary; GIT: index/worktree, + full records below, * changes below; ▸ unexpanded".to_owned());
    }
    bound_footer(lines, report)
}

/// UTF-8 byte bound, including newlines and room for color escapes. Essential
/// accounting is allocated before optional omission samples, regardless of
/// their display order. JSON records remain exhaustive.
fn bound_footer(mut lines: Vec<String>, report: &Report) -> Vec<String> {
    const BUDGET: usize = 8192;
    const ROW: usize = 512;
    const GUIDANCE: &str = "details: footer abbreviated; rerun the same listing with -J (tree -J)";
    let mut categories = BTreeMap::<&str, usize>::new();
    for omission in &report.omissions {
        *categories.entry(&omission.category).or_default() += 1;
    }
    let summary = categories
        .iter()
        .map(|(name, count)| format!("{name}={count}"))
        .collect::<Vec<_>>()
        .join(", ");
    let summary = format!("omitted boundaries: {summary}");
    let mut left = BUDGET - GUIDANCE.len() - summary.len() - 32;
    let mut shortened = false;
    let mut keep = vec![false; lines.len()];
    let essential =
        |line: &str| !line.starts_with("hidden ") || line.split_whitespace().nth(2) == Some("…");
    for required in [true, false] {
        for (index, line) in lines.iter_mut().enumerate() {
            if essential(line) != required {
                continue;
            }
            let allowance = ROW.min(left.saturating_sub(16));
            if allowance < 64 {
                shortened = true;
                continue;
            }
            if line.len() > allowance {
                let mut end = allowance - " …".len();
                while !line.is_char_boundary(end) {
                    end -= 1;
                }
                line.truncate(end);
                line.push_str(" …");
                shortened = true;
            }
            left -= line.len() + 16;
            keep[index] = true;
        }
    }
    let mut result: Vec<_> = lines
        .into_iter()
        .zip(keep)
        .filter_map(|(line, keep)| keep.then_some(line))
        .collect();
    if shortened {
        // Boundary totals remain available even when sampled groups do not fit.
        result.push(summary);
        result.push(GUIDANCE.to_owned());
    }
    result
}

/// The base-path line, then the omission rows: the [`GROUP_ROWS`] largest
/// `(category, source, pattern)` groups in path order, then one remainder
/// row per category. Also returns each category's reveal command.
fn hidden_rows(report: &Report) -> (Vec<String>, BTreeMap<&str, &str>) {
    let mut lines = Vec::new();
    let mut groups = BTreeMap::<(&str, &str, &str, &str), Vec<String>>::new();
    for omission in &report.omissions {
        if omission.category == "metadata" {
            continue;
        }
        groups
            .entry((
                &omission.category,
                &omission.source,
                &omission.pattern,
                &omission.reveal,
            ))
            .or_default()
            .push(escape_os(omission.path.as_os_str()));
    }
    if !groups.is_empty() || !report.nested_repos.is_empty() {
        lines.push(format!(
            "paths relative to {}",
            escape_os(report.root.as_os_str())
        ));
    }
    let mut reveals = BTreeMap::new();
    // The largest groups get rows (shown in path order); the rest are
    // summarized per category. -J carries every omission record.
    let mut ranked: Vec<_> = groups.iter().collect();
    ranked.sort_by(|a, b| b.1.len().cmp(&a.1.len()).then_with(|| a.0.cmp(b.0)));
    let shown: std::collections::BTreeSet<_> = ranked
        .iter()
        .take(GROUP_ROWS)
        .map(|(key, _)| *key)
        .collect();
    let mut rest = BTreeMap::<&str, (usize, usize, std::collections::BTreeSet<&str>)>::new();
    for (key, paths) in &groups {
        reveals.insert(key.0, key.3);
        if !shown.contains(key) {
            let entry = rest.entry(key.0).or_default();
            entry.0 += paths.len();
            entry.1 += 1;
            entry.2.insert(key.1);
        }
    }
    let category_width = groups
        .keys()
        .map(|(category, ..)| category.len())
        .max()
        .unwrap_or(0);
    let count_width = shown
        .iter()
        .map(|key| groups[*key].len().to_string().len())
        .max()
        .unwrap_or(0);
    // Columns align to the shown rows, never wider than SOURCE_WIDTH: one
    // long rule or diagnostic must not pad every other row.
    let rule = |source: &str, pattern: &str| format!("{}: {}", escape(source), escape(pattern));
    let source_width = shown
        .iter()
        .map(|(_, source, pattern, _)| rule(source, pattern).chars().count())
        .max()
        .unwrap_or(0)
        .min(SOURCE_WIDTH);
    for key in &shown {
        let (category, source, pattern, _) = **key;
        let paths = &groups[*key];
        lines.push(format!(
            "hidden  {category:<category_width$}  {:>count_width$}  {:<source_width$}  {}",
            paths.len(),
            rule(source, pattern),
            escaped_names(paths),
        ));
    }
    for (category, (entries, count, sources)) in rest {
        lines.push(format!(
            "hidden  {category:<category_width$}  … {entries} more in {count} groups from {} \
             (tree -J | jq '.[-1].omissions')",
            plural(
                u64::try_from(sources.len()).unwrap_or(u64::MAX),
                "source",
                "sources"
            ),
        ));
    }
    (lines, reveals)
}

fn displayed_nodes<'a>(root: &'a Node, opts: &Options) -> Vec<&'a Node> {
    let mut nodes = vec![root];
    let mut index = 0;
    while index < nodes.len() {
        let node = nodes[index];
        if node.cut.is_none()
            && let Kind::Dir { children, .. } = &node.kind
        {
            nodes.extend(
                children
                    .iter()
                    .filter(|child| !opts.dirs_only || matches!(child.kind, Kind::Dir { .. })),
            );
        }
        index += 1;
    }
    nodes
}

fn rules_line(report: &Report) -> Option<String> {
    report.rules_off.map(|source| {
        let by = match source {
            RulesOff::Flag => "--no-ignore",
            RulesOff::Config => ".tree.toml gitignore = false",
        };
        format!("ignore rules: off ({by}); .gitignore, .ignore, and git excludes are not applied")
    })
}

/// Lines for paths re-shown, directories not expanded, git deletions,
/// uncounted or unreadable files, and the applied `.tree.toml`.
fn omission_lines(report: &Report) -> Vec<String> {
    let mut lines = Vec::new();
    if let Some(error) = &report.git_error {
        lines.push(format!("git: status unavailable ({})", escape(error)));
    }
    if !report.shown.is_empty() {
        let inventories = report
            .reshown_inventory
            .iter()
            .map(|(path, totals)| match totals {
                Inventory::NotScanned => format!("{path}/ inventory not scanned"),
                Inventory::Incomplete(t) => format!(
                    "{path}/ inventory incomplete: at least {} {} (see errors)",
                    plural(t.files, "file", "files"),
                    human(t.bytes)
                ),
                Inventory::Complete(t) => format!(
                    "{path}/ {} {}",
                    plural(t.files, "file", "files"),
                    human(t.bytes)
                ),
            })
            .collect::<Vec<_>>();
        lines.push(format!(
            "re-shown  {}  .tree.toml  {}",
            inventories.len(),
            names(&inventories)
        ));
    }
    if report.level_cuts > 0
        && let Some(level) = report.level
    {
        lines.push(format!(
            "collapsed  {}  -L: {level}  inventory: {}",
            report.level_cuts,
            report.inventory_mode.name()
        ));
    }
    if report.budget_cuts > 0 {
        lines.push(format!(
            "collapsed  {}  --budget: {}  increase --budget to expand",
            report.budget_cuts, report.budget
        ));
    }
    if report.config_cuts > 0 {
        lines.push(format!(
            "collapsed  {}  .tree.toml: collapse  edit collapse to expand",
            report.config_cuts
        ));
    }
    if !report.deleted.is_empty() {
        lines.push(format!(
            "deleted  {}  git: porcelain  {}",
            report.deleted.len(),
            names(
                &report
                    .deleted
                    .iter()
                    .map(|(path, code)| {
                        format!("{} {}", code.replace(' ', "␠"), escape_os(path.as_os_str()))
                    })
                    .collect::<Vec<_>>()
            )
        ));
    }
    if !report.nested_repos.is_empty() {
        let repos: Vec<String> = report
            .nested_repos
            .iter()
            .map(|path| format!("{}/", escape_os(path.as_os_str())))
            .collect();
        lines.push(format!(
            ".git markers  {} nested  unvalidated; nested git status and .tree.toml are not applied; list one directly  {}",
            repos.len(),
            escaped_names(&repos)
        ));
    }
    if !report.unreadable.is_empty() {
        lines.push(format!(
            "errors: {} recorded; {}",
            report.unreadable.len(),
            names(&report.unreadable)
        ));
    }
    for (path, unused) in &report.configs {
        lines.push(if unused.is_empty() {
            format!("config: {}", escape_os(path.as_os_str()))
        } else {
            format!(
                "config: {}; unused patterns: {}",
                escape_os(path.as_os_str()),
                names(unused)
            )
        });
    }
    lines
}

fn node_json(node: &Node, opts: &Options) -> Option<Value> {
    if opts.dirs_only && !matches!(node.kind, Kind::Dir { .. }) {
        return None;
    }
    let path = node.rel.display().to_string();
    let mut value = match &node.kind {
        Kind::Dir { children, totals } => {
            let mut dir = json!({
                "type": "directory",
                "name": node.name,
                "path": path,
                "files": totals.files,
                "lines": totals.lines,
                "bytes": totals.bytes,
                "files_uncounted": totals.uncounted,
                "lines_complete": totals.uncounted == 0,
                "changes_below": !node.git.is_empty(),
                "hidden_entries": node.hidden_entries,
            });
            dir["inventory_complete"] = json!(node.inventory == InventoryState::Complete);
            if node.inventory != InventoryState::Complete {
                if node.inventory == InventoryState::Incomplete {
                    dir["observed"] = json!(totals);
                }
                for field in ["files", "lines", "bytes", "files_uncounted"] {
                    dir[field] = Value::Null;
                }
                dir["lines_complete"] = json!(false);
            }
            if let Some(cut) = node.cut {
                dir["expanded"] = json!(false);
                dir["reason"] = json!(cut_text(cut));
            } else {
                let contents: Vec<Value> =
                    children.iter().filter_map(|c| node_json(c, opts)).collect();
                dir["contents"] = Value::Array(contents);
            }
            dir
        }
        Kind::File(lines) => {
            let mut file = json!({
                "type": "file",
                "name": node.name,
                "path": path,
                "size": node.size,
                "line_state": line_state(*lines),
            });
            match lines {
                Lines::Text(n) => file["lines"] = json!(n),
                Lines::Binary => file["binary"] = json!(true),
                _ => {}
            }
            file
        }
        Kind::Link { target, state } => {
            let mut link = json!({
            "type": "link",
            "name": node.name,
            "path": path,
            "target": target.to_string_lossy(),
            "broken": *state == LinkState::Broken,
            });
            if target.to_str().is_none() {
                link["target_bytes"] = json!(target.as_os_str().as_bytes());
            }
            link
        }
        Kind::Other => json!({ "type": "other", "name": node.name, "path": path }),
    };
    if !node.git.is_empty() {
        let key = if matches!(node.kind, Kind::Dir { .. }) {
            "changes_below_codes"
        } else {
            "git"
        };
        value[key] = json!(node.git);
    }
    value["reshown"] = json!(node.reshown);
    if node.rel.to_str().is_none() {
        value["path_bytes"] = json!(node.rel.as_os_str().as_bytes());
    }
    if let Some(mtime) = node.mtime {
        value["modified"] = json!(utc(mtime));
    }
    if let Some(note) = &node.note {
        value["note"] = json!(note);
    }
    Some(value)
}

pub(crate) fn json(out: &mut impl Write, listings: &[Listing], opts: &Options) -> Result<()> {
    let mut items = Vec::new();
    for listing in listings {
        if let Some(mut node) = node_json(&listing.root, opts) {
            node["name"] = json!(listing.label);
            items.push(node);
        }
        let report = &listing.report;
        if opts.report {
            items.push(json!({
                "type": "report",
                "root": listing.label,
                "level": report.level,
                "directories": report.totals.dirs,
            "files": report.totals.files,
            "represented": report.totals,
            "listed": listed_totals(&listing.root, opts),
            "reshown": report.reshown_inventory,
                "lines": report.totals.lines,
                "bytes": report.totals.bytes,
                "files_uncounted": report.totals.uncounted,
                "lines_complete": report.totals.uncounted == 0 && !report.inventory_incomplete,
                "inventory_complete": !report.inventory_incomplete,
                "inventory": report.inventory_mode.name(),
                "ignore_rules": if report.rules_off.is_some() { "off" } else { "honored" },
                "hidden": {
                    "ignore_rules": hidden_paths(report, "ignore"),
                    "dotfiles": hidden_paths(report, "dotfile"),
                    "tree_toml": hidden_paths(report, "config"),
                    "excluded": hidden_paths(report, "excluded"),
                    "not_matching_pattern": hidden_paths(report, "pattern").len(),
                },
                "omissions": report.omissions.iter().map(|omission| {
                    let mut record = json!({
                        "path": omission.path.to_string_lossy(),
                        "category": omission.category,
                        "source": omission.source,
                        "pattern": omission.pattern,
                        "reveal": omission.reveal,
                    });
                    if omission.path.to_str().is_none() {
                        record["path_bytes"] = json!(omission.path.as_os_str().as_bytes());
                    }
                    record
                }).collect::<Vec<_>>(),
                "shown_by_tree_toml": report.shown,
                "not_expanded": {
                    "level": report.level_cuts,
                    "budget": report.budget_cuts,
                    "collapsed": report.config_cuts,
                },
                "budget": report.budget,
                "git_deleted": report.deleted.iter().map(|(path, code)| {
                    let mut record = json!({"path": path.to_string_lossy(), "git": code});
                    if path.to_str().is_none() {
                        record["path_bytes"] = json!(path.as_os_str().as_bytes());
                    }
                    record
                }).collect::<Vec<_>>(),
                "git_error": report.git_error,
                "errors": report.unreadable,
                "root_path": report.root.to_string_lossy(),
                "count": report.count.map(crate::args::Count::name),
                "read_limit": report.read_limit,
                "content_bytes_read": report.content_bytes_read,
                "lines_uncounted": {
                    "not_shown": report.not_shown,
                    "read_limit": report.read_limited,
                    "too_large": report.too_large,
                    "unreadable": report.unreadable_files,
                },
                "nested_git_markers": report.nested_repos.iter()
                    .map(|path| {
                        let mut marker = json!({"path": path.to_string_lossy()});
                        if path.to_str().is_none() {
                            marker["path_bytes"] = json!(path.as_os_str().as_bytes());
                        }
                        marker
                    }).collect::<Vec<_>>(),
                "git_marker_scope": "unvalidated .git entries in enumerated directories; includes presentation-collapsed descendants; excludes ignored and unscanned subtrees and bare repositories",
                "read_limit_scope": "per_root",
                "configs": report.configs.iter().map(|(path, unused)| json!({
                    "path": path.display().to_string(),
                    "unused": unused,
                })).collect::<Vec<_>>(),
                "summary": footer(report, &listing.root, opts),
                }));
        }
    }
    serde_json::to_writer(&mut *out, &Value::Array(items))?;
    writeln!(out)?;
    Ok(())
}

fn listed_totals(node: &Node, opts: &Options) -> Value {
    let mut dirs = 0_u64;
    let mut files = 0_u64;
    let mut pending = vec![node];
    while let Some(parent) = pending.pop() {
        if parent.cut.is_some() {
            continue;
        }
        if let Kind::Dir { children, .. } = &parent.kind {
            for child in children {
                match child.kind {
                    Kind::Dir { .. } => {
                        dirs += 1;
                        pending.push(child);
                    }
                    Kind::File(_) if !opts.dirs_only => files += 1,
                    _ => {}
                }
            }
        }
    }
    json!({"directories": dirs, "files": files})
}

fn hidden_paths(report: &Report, category: &str) -> Vec<String> {
    report
        .omissions
        .iter()
        .filter(|o| o.category == category)
        .map(|o| o.path.to_string_lossy().into_owned())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn footer_budget_preserves_errors_and_exact_json_details() {
        let report = Report {
            unreadable: vec!["failure ".repeat(2000)],
            omissions: (0..10_000)
                .map(|index| crate::provenance::Omission {
                    path: format!("{index}/{}", "long".repeat(100)).into(),
                    category: "ignore".into(),
                    source: ".ignore".into(),
                    pattern: format!("{}{}", index % 25, "pattern".repeat(100)),
                    reveal: "tree --no-ignore".into(),
                })
                .collect(),
            ..Report::default()
        };
        let root = Node {
            name: ".".into(),
            rel: "".into(),
            kind: Kind::Dir {
                children: Vec::new(),
                totals: Totals::default(),
            },
            git: Vec::new(),
            note: None,
            size: 0,
            mtime: None,
            cut: Some(Cut::Budget),
            hidden_entries: 0,
            reshown: false,
            inventory: InventoryState::Complete,
            summarized: false,
        };
        let rows = footer(&report, &root, &Options::default());
        assert!(
            rows.iter().map(|row| row.len() + 1).sum::<usize>() <= 8192,
            "footer including newlines must fit 8192 UTF-8 bytes"
        );
        assert!(
            rows.iter().any(|row| row.starts_with("errors:")),
            "errors reserved"
        );
        assert!(
            rows.iter()
                .any(|row| row.starts_with("errors:") && row.len() >= 500),
            "samples with remainder annotations cannot consume the error reservation"
        );
        assert!(
            rows.iter().any(|row| row.starts_with("legend:")),
            "legend reserved"
        );
        assert!(
            rows.iter().any(|row| row.contains("tree -J")),
            "detail guidance reserved"
        );
        assert_eq!(report.omissions.len(), 10_000, "exact records retained");
    }

    #[test]
    fn human_sizes() {
        assert_eq!(human(9), "9 B");
        assert_eq!(human(1023), "1023 B");
        assert_eq!(human(1024), "1.0 KiB");
        assert_eq!(human(6656), "6.5 KiB");
        assert_eq!(human(64 * 1024 * 1024), "64.0 MiB");
    }

    #[test]
    fn utc_formats_known_instants() {
        let at = |secs| UNIX_EPOCH + std::time::Duration::from_secs(secs);
        assert_eq!(utc(at(0)), "1970-01-01 00:00 UTC");
        assert_eq!(utc(at(951_782_400)), "2000-02-29 00:00 UTC");
        // Reference: `date -u -d @1795405339`.
        assert_eq!(utc(at(1_795_405_339)), "2026-11-23 03:42 UTC");
    }

    #[test]
    fn escapes_control_characters_only() {
        // cspell:ignore ünïcode
        assert_eq!(escape("plain"), "plain");
        assert_eq!(escape("ünïcode ✓"), "ünïcode ✓");
        assert_eq!(escape("a\nb"), "a\\nb");
        assert_eq!(escape("\u{1b}[31m"), "\\u{1b}[31m");
        assert_eq!(escape("del\u{7f}"), "del\\u{7f}");
    }
}
