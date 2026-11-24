//! Konductor `tree`: tree-compatible options and drawing over ripgrep's
//! ignore rules, with per-entry line counts, git status, per-repository
//! `.tree.toml` configuration, and a footer accounting for every entry not
//! listed. Specification: tests/spec.sh.

mod args;
mod config;
mod git;
mod provenance;
mod render;
mod walk;

use std::ffi::OsString;
use std::io::{self, ErrorKind, Write};
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitCode};

use anyhow::{Context, Result};

use crate::args::Command as Cli;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed pipe (`tree | head`) ends the listing; it is not an error.
        Err(err)
            if err
                .downcast_ref::<io::Error>()
                .is_some_and(|e| e.kind() == ErrorKind::BrokenPipe) =>
        {
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("tree: {err:#}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<()> {
    let opts = match args::parse(std::env::args_os().skip(1).collect())? {
        Cli::Help => {
            print!("{}", args::HELP);
            return Ok(());
        }
        Cli::Version => {
            println!("tree (konductor) {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        Cli::Raw(rest) => return raw(rest),
        Cli::List(opts) => opts,
    };
    if opts.init {
        return config::initialize(std::path::Path::new(&opts.roots[0]));
    }
    if opts.print_config {
        return walk::print_config(&opts);
    }
    let listings = opts
        .roots
        .iter()
        .map(|root| walk::build(root, &opts))
        .collect::<Result<Vec<_>>>()?;
    let mut out = io::BufWriter::new(io::stdout().lock());
    if opts.json {
        render::json(&mut out, &listings, &opts)?;
    } else {
        render::text(&mut out, &listings, &opts, render::color(opts.color))?;
    }
    out.flush()?;
    Ok(())
}

/// `--raw`: `eza --tree` with the remaining arguments. Nix builds bake eza's
/// store path; other builds use PATH.
fn raw(rest: Vec<OsString>) -> Result<()> {
    let eza = option_env!("KONDUCTOR_TREE_EZA").unwrap_or("eza");
    let err = Command::new(eza).arg("--tree").args(rest).exec();
    Err(err).with_context(|| format!("--raw: cannot run {eza}"))
}
