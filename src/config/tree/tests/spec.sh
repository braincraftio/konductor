#!/usr/bin/env bash
# src/config/tree/tests/spec.sh
# Executable specification for the Konductor `tree`. Usage: spec.sh <tree-binary>
#
# Runs every assertion against the given binary on a generated fixture
# repository and exits non-zero if any fails, listing each failure. The same
# script runs against the built renderer locally and during Nix install checks.
#
# Requires on PATH: git, rg, jq.
#
# SC2016: `bash -c '...' _ ARGS` bodies are single-quoted so $1, $2, and $out
# expand in the child shell from its positional arguments, not here.
# SC2312: command substitutions supply the output under assertion; a failing
# tree run yields output the assertion rejects, so the check fails visibly.
# shellcheck disable=SC2016,SC2312
set -uo pipefail

TREE="${1:?usage: spec.sh <tree-binary>}"
command -v git rg jq > /dev/null || {
    echo "spec.sh: git, rg, and jq are required" >&2
    exit 2
}

FIX="$(mktemp -d)"
trap 'chmod -R u+w "$FIX"; command rm -r "$FIX"' EXIT
export HOME="${FIX}/home" GIT_CONFIG_NOSYSTEM=1
unset NO_COLOR CLICOLOR_FORCE
mkdir -p "${HOME}"

FAILURES=()
check() {
    local name="$1"
    shift
    if "$@"; then echo "ok   ${name}"; else
        echo "FAIL ${name}"
        FAILURES+=("${name}")
    fi
}
# has TEXT PATTERN / lacks TEXT PATTERN: fixed-string assertions on output.
has() { grep -qF -- "$(tr -s ' ' <<< "$2")" <<< "$(tr -s ' ' <<< "$1")"; }
lacks() { grep -q main.rs <<< "$1" && ! grep -qF -- "$2" <<< "$1"; }

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------
R="${FIX}/repo"
mkdir -p "${R}"/{src/a/b/c/d/e/f/g,dev,target,bulk,.github,ver}
printf 'fn main() {\n    println!("x");\n}\n' > "${R}/src/main.rs"
printf 'one\ntwo\nthree\n' > "${R}/src/a/b/c/d/e/f/g/deep.txt"
printf 'x\n' > "${R}/dev/new.txt"
printf 'artifact\n' > "${R}/target/out.bin"
printf 'secret=1\n' > "${R}/.envrc"
printf 'on: push\n' > "${R}/.github/ci.yml"
printf 'ignored-by-dotignore\n' > "${R}/scratch.log"
printf 'nested\n' > "${R}/bulk/y.log"
printf 'nested\n' > "${R}/src/x.log"
printf '\x00\x01\x02binary' > "${R}/blob.dat"
printf 'no trailing newline' > "${R}/partial.txt"
for i in $(seq -w 1 40); do printf 'row %s\n' "${i}" > "${R}/bulk/f${i}.txt"; done
for n in 1 2 10; do printf 'v\n' > "${R}/ver/f${n}"; done
printf 'target/\n' > "${R}/.gitignore"
printf '*.log\n' > "${R}/.ignore"
ln -s / "${R}/escape"
ln -s does-not-exist "${R}/dangling"
printf 'evil\n' > "${R}/evil"$'\n'"── fake.rs"

git -C "${R}" init -q
git -C "${R}" -c user.name=t -c user.email=t@t add .gitignore .ignore src bulk ver blob.dat partial.txt .github .envrc escape dangling
git -C "${R}" -c user.name=t -c user.email=t@t commit -qm fixture
printf '// edited\n' >> "${R}/src/main.rs"
git -C "${R}" rm -q --cached ver/f1
git -C "${R}" add -N "${R}/evil"$'\n'"── fake.rs"

run() { (cd "${R}" && "${TREE}" "$@" 2>&1); }

OUT="$(run)"
OUT_A="$(run -a)"
echo "--- default output (assertions run against this and the flag variants)"
printf '%s\n' "${OUT}"
echo "---"

# ---------------------------------------------------------------------------
# 1. Correct with no flags; 2. same content in terminal and pipe
# ---------------------------------------------------------------------------
check "default run lists the tree" has "${OUT}" 'main.rs'
check "piped listing has no ANSI escapes" bash -c 'grep -q main.rs <<<"$1" && ! grep -q $'"'"'\x1b'"'"' <<<"$1"' _ "${OUT}"
check "no default depth limit (depth-8 file listed)" has "${OUT}" 'deep.txt'
check "root row is the path given (.)" grep -Eq '^ *[0-9]+ +\* +\.$' <<< "${OUT}"
check "GNU drawing characters" grep -q '├── \|└── ' <<< "${OUT}"
check "directories carry a trailing slash" has "${OUT}" '── src/'

# ---------------------------------------------------------------------------
# 3. Nothing lost silently
# ---------------------------------------------------------------------------
check "footer groups ignore-rule entries with provenance" has "${OUT}" 'hidden  ignore  3  .ignore: *.log  bulk/y.log, scratch.log, src/x.log'
check "footer counts dotfiles and names their rule" has "${OUT}" 'hidden  dotfile  4  tree default: .*  .envrc, .github/, .gitignore, .ignore'
check "-a lists dotfiles" has "${OUT_A}" '── .envrc'
check "-a removes the dotfile footer" lacks "${OUT_A}" 'hidden  dotfile'

OUT_L2="$(run --inventory full -L 2)"
check "-L 2 replaces the default depth (deep.txt not listed)" lacks "${OUT_L2}" 'deep.txt'
check "-L 2 marks the cut directory with its totals" grep -Eq '^ *3 .*▸ a/  1 file, ' <<< "${OUT_L2}"
check "depth labels are not repeated on rows" bash -c '! grep -qF "[-L " <<<"$1"' _ "${OUT_L2}"
check "-L 2 footer reports the cut" has "${OUT_L2}" 'collapsed  1  -L: 2'

# ---------------------------------------------------------------------------
# 4. Bounded output
# ---------------------------------------------------------------------------
OUT_B="$(run --inventory full --budget 20)"
check "--budget collapses the largest directory" grep -Eq '^ *40 .*▸ bulk/  \[budget\]' <<< "${OUT_B}"
check "--budget footer reports the collapse" has "${OUT_B}" '--budget: 20'
check "--budget keeps small directories expanded" has "${OUT_B}" 'main.rs'

# ---------------------------------------------------------------------------
# 5. GNU command line, unsupported input is an error
# ---------------------------------------------------------------------------
check "unknown flag exits non-zero" bash -c '! (cd "$1" && "$2" --definitely-not-a-flag >/dev/null 2>&1)' _ "${R}" "${TREE}"
check "unknown flag names itself on stderr" bash -c '(cd "$1" && "$2" --definitely-not-a-flag 2>&1 >/dev/null) | grep -q definitely-not-a-flag' _ "${R}" "${TREE}"
check "-L with a non-number exits non-zero" bash -c '! (cd "$1" && "$2" -L x >/dev/null 2>&1)' _ "${R}" "${TREE}"
check "-d lists directories only" bash -c 'out="$(cd "$1" && "$2" -d)"; grep -q "── src/" <<<"$out" && ! grep -q main.rs <<<"$out"' _ "${R}" "${TREE}"
check "-P keeps matching files only" bash -c 'out="$(cd "$1" && "$2" -P "*.rs")"; grep -q "── main.rs" <<<"$out" && ! grep -q "── partial.txt" <<<"$out"' _ "${R}" "${TREE}"
check "-I hides matching entries and counts them" bash -c 'out="$(cd "$1" && "$2" -I bulk)"; ! grep -q "── bulk/" <<<"$out" && grep -qE "hidden +excluded +1 +-I: bulk +bulk/" <<<"$out"' _ "${R}" "${TREE}"
check "-f prints full paths" has "$(run -f)" '── ./src/main.rs'
check "--noreport drops the footer" lacks "$(run --noreport)" 'directories, '
check "-C forces color into a pipe" bash -c 'grep -q $'"'"'\x1b\['"'"' <<<"$1"' _ "$(run -C)"
check "-v sorts digit runs by value" bash -c 'out="$(cd "$1" && "$2" -v ver)"; [[ "$(grep -o "f[0-9]*$" <<<"$out" | tr "\n" ,)" == "f1,f2,f10," ]]' _ "${R}" "${TREE}"
check "default sort is byte order" bash -c 'out="$(cd "$1" && "$2" ver)"; [[ "$(grep -o "f[0-9]*$" <<<"$out" | tr "\n" ,)" == "f1,f10,f2," ]]' _ "${R}" "${TREE}"
check "--no-ignore lists ignore-rule entries and says so" bash -c 'out="$(cd "$1" && "$2" --no-ignore)"; grep -q "── target/" <<<"$out" && grep -q "── scratch.log" <<<"$out" && grep -qF "ignore rules: off (--no-ignore)" <<<"$out"' _ "${R}" "${TREE}"
check "--version exits zero" bash -c '(cd "$1" && "$2" --version >/dev/null)' _ "${R}" "${TREE}"
check "--raw runs eza" bash -c '(cd "$1" && "$2" --raw --version 2>&1) | grep -qi eza' _ "${R}" "${TREE}"

# ---------------------------------------------------------------------------
# 6. GNU output shape: summary line
# ---------------------------------------------------------------------------
check "summary line with line total" grep -Eq '^[0-9]+ director(y|ies), [0-9]+ files?, [0-9]+ lines?$' <<< "${OUT}"

# ---------------------------------------------------------------------------
# 7. Ignore parity with rg
# ---------------------------------------------------------------------------
check "file set equals rg --files" bash -c 'diff <(cd "$1" && "$2" -J | jq -r ".. | objects | select(.type == \"file\") | .path" | LC_ALL=C sort) <(cd "$1" && rg --files | LC_ALL=C sort)' _ "${R}" "${TREE}"
check "-a file set equals rg --files --hidden" bash -c 'diff <(cd "$1" && "$2" -a -J | jq -r ".. | objects | select(.type == \"file\") | .path" | LC_ALL=C sort) <(cd "$1" && rg --files --hidden | grep -v "^.git/" | LC_ALL=C sort)' _ "${R}" "${TREE}"

# ---------------------------------------------------------------------------
# 8. Deterministic; 9. machine-readable
# ---------------------------------------------------------------------------
check "two runs are byte-identical" bash -c 'grep -q main.rs <<<"$1" && [[ "$1" == "$(cd "$2" && "$3")" ]]' _ "${OUT}" "${R}" "${TREE}"
check "-J emits Konductor JSON with a report object" bash -c '(cd "$1" && "$2" -J) | jq -e ".[0].type == \"directory\" and .[-1].type == \"report\" and (.[-1].lines | type == \"number\")" >/dev/null' _ "${R}" "${TREE}"

# ---------------------------------------------------------------------------
# Per-entry information: line counts, binary, git status
# ---------------------------------------------------------------------------
check "file line count (total lines)" grep -Eq '^ *4 .*── main.rs$' <<< "${OUT}"
check "final line without newline counts" grep -Eq '^ *1 .*── partial.txt$' <<< "${OUT}"
check "binary file has a distinct line state" grep -Eq '^ *bin .*── blob.dat$' <<< "${OUT}"
check "directory totals" grep -Eq '^ *7 .*── src/  \[hidden: 1\]$' <<< "${OUT}"
check "git: unstaged modification shows both columns" grep -Eq '^ *4   M .*── main.rs$' <<< "${OUT}"
check "git: directory carries a separate aggregate marker" grep -Eq '^ *7   \* .*── src/  \[hidden: 1\]$' <<< "${OUT}"
check "git: untracked files retain their status under directories" grep -Eq '^ *1  \?\? .*── new.txt$' <<< "${OUT}"
check "git: every code of a path is kept (staged deletion, still on disk)" has "${OUT}" 'git: ?? | D␠'

# ---------------------------------------------------------------------------
# 11. Safe: names are escaped; symlinks are listed, never followed
# ---------------------------------------------------------------------------
check "control characters in names are escaped" has "${OUT}" '── evil\n── fake.rs'
check "an escaped name cannot forge an entry" bash -c 'grep -q main.rs <<<"$1" && ! grep -q "^── fake.rs\|^├── fake.rs\|^└── fake.rs" <<<"$1"' _ "${OUT}"
check "symlink shown with target, not followed" has "${OUT}" '── escape -> /'
check "symlink target contents absent" lacks "${OUT}" '── etc/'
check "broken symlink is marked" has "${OUT}" '── dangling -> does-not-exist (broken)'

# ---------------------------------------------------------------------------
# .tree.toml: one file, visibility then presentation
# ---------------------------------------------------------------------------
C="${FIX}/configured"
cp -a "${R}" "${C}"
mkdir -p "${C}/vendor/lib" "${C}/node_modules/pkg"
printf 'a\nb\n' > "${C}/vendor/lib/v.txt"
printf 'module\n' > "${C}/node_modules/pkg/index.js"
printf 'vendor/\n' >> "${C}/.gitignore"
cat > "${C}/.tree.toml" << 'TOML'
ignore = [
  "bulk/",
  "never-matches/",
  "!target/",
  "!vendor/",
]

[defaults]
level = 1
inventory = "full"

["target/"]
collapse = true
note = "build output"

["src/"]
note = "sources"
TOML
runc() { (cd "${C}" && "${TREE}" "$@" 2>&1); }
CFG="$(runc)"
CFG_L="$(runc -L 9)"

check "config: [defaults] level applies" grep -Eq '^ *7   \* .*▸ src/.*# sources' <<< "${CFG}"
check "config: -L overrides [defaults] level" bash -c 'grep -q "── main.rs" <<<"$1" && ! grep -q "not expanded: -L" <<<"$1"' _ "${CFG_L}"
check "config: section note shown" has "${CFG_L}" '  # sources'
check "config: ! shows an ignored directory, collapsed by its section" has "${CFG_L}" '▸ target/  [.tree.toml]  # build output'
check "config: ! shows an ignored directory in full" bash -c 'grep -q "── vendor/" <<<"$1" && grep -Eq "^ *2 .*── v.txt" <<<"$1"' _ "${CFG_L}"
check "config: re-shown paths are reported" has "${CFG_L}" 're-shown  2  .tree.toml  target/ inventory not scanned, vendor/ 1 file 4 B'
check "config: ignore hides a visible path and counts it" bash -c '! grep -q "── bulk/" <<<"$1" && grep -qE "hidden +config +1 +.tree.toml: bulk/ +bulk/" <<<"$1"' _ "${CFG_L}"
check "config: node_modules visible without gitignore entry" has "${CFG_L}" '── node_modules/'
check "config: footer names the file and unused patterns" has "${CFG_L}" "config: .tree.toml; unused patterns: ignore[1] 'never-matches/'"

printf 'gitignore = false\nignore = ["node_modules/"]\n' > "${C}/.tree.toml"
OFF="$(runc)"
check "config: gitignore = false lists ignore-rule entries" bash -c 'grep -q "── target/" <<<"$1" && grep -q "── scratch.log" <<<"$1"' _ "${OFF}"
check "config: gitignore = false is stated in the footer" has "${OFF}" 'ignore rules: off (.tree.toml gitignore = false)'
check "config: ignore still hides with gitignore = false" bash -c '! grep -q "── node_modules/" <<<"$1" && grep -qE "hidden +config +1 +.tree.toml: node_modules/ +node_modules/" <<<"$1"' _ "${OFF}"
check "config: --ignore overrides gitignore = false" bash -c 'out="$(cd "$1" && "$2" --ignore)"; grep -q "── main.rs" <<<"$out" && ! grep -q "── target/" <<<"$out"' _ "${C}" "${TREE}"

printf 'ignore = ["*.txt", "!keep.txt"]\n' > "${C}/.tree.toml"
printf 'k\n' > "${C}/keep.txt"
check "config: later ! line wins, gitignore precedence" bash -c 'out="$(cd "$1" && "$2")"; grep -q "── keep.txt" <<<"$out" && ! grep -q "── partial.txt" <<<"$out"' _ "${C}" "${TREE}"

# Deliberately invalid keys exercise configuration diagnostics.
# cspell:ignore gitignre ncolapse colapse
printf 'gitignre = true\n' > "${C}/.tree.toml"
check "config: unknown key is an error naming the key" bash -c '! out="$(cd "$1" && "$2" 2>&1)" && grep -q gitignre <<<"$out"' _ "${C}" "${TREE}"
printf '["src/"]\ncolapse = true\n' > "${C}/.tree.toml"
check "config: unknown section attribute is an error" bash -c '! out="$(cd "$1" && "$2" 2>&1)" && grep -q colapse <<<"$out"' _ "${C}" "${TREE}"

# ---------------------------------------------------------------------------
# Adversarial: an ignore-file name that is a directory contributes no rules
# (ripgrep crates/ignore dir.rs create_gitignore: partial error, non-fatal)
# ---------------------------------------------------------------------------
D="${FIX}/ignore-is-a-directory"
mkdir -p "${D}/.ignore"
printf 'x\n' > "${D}/.ignore/inner"
printf 'x\n' > "${D}/a.txt"
OUT_D="$(cd "${D}" && "${TREE}" 2>&1)"
check "ignore-name directory is classified as a dotfile" has "${OUT_D}" 'hidden  dotfile  1  tree default: .*  .ignore/'
check "ignore-name directory is not a disagreement" bash -c 'grep -q a.txt <<<"$1" && ! grep -q disagreement <<<"$1"' _ "${OUT_D}"

# ---------------------------------------------------------------------------
# Footer scale: bounded rows, outlier widths, base path, nested repositories
# ---------------------------------------------------------------------------
W="${FIX}/workspace"
mkdir -p "${W}"
for n in $(seq -w 1 30); do
    mkdir -p "${W}/repo${n}/.git" "${W}/repo${n}/src"
    printf 'gen-%s/\n' "${n}" > "${W}/repo${n}/.gitignore"
    mkdir "${W}/repo${n}/gen-${n}"
    printf 'x\n' > "${W}/repo${n}/src/lib.rs"
done
printf '%s\n' "$(printf 'x%.0s' $(seq 1 200))" > "${W}/repo01/.ignore"
touch "${W}/repo01/$(printf 'x%.0s' $(seq 1 200))"
OUT_W="$(cd "${W}" && "${TREE}" 2>&1)"
check "footer: hidden rows are bounded" bash -c '(( $(grep -c "^hidden " <<<"$1") <= 22 ))' _ "${OUT_W}"
check "footer: remainder points at JSON" grep -Eq '^hidden +ignore +… [0-9]+ more in [0-9]+ groups' <<< "${OUT_W}"
check "footer: one long pattern does not pad other rows" bash -c '! grep "^hidden  ignore" <<<"$1" | grep -v "xxxxxxxxxx" | grep -q "   \{60,\}"' _ "${OUT_W}"
check "footer: states the base of relative paths" has "${OUT_W}" "paths relative to ${W}"
check "footer: nested git markers are reported" grep -Eq '^.git markers +30 nested' <<< "${OUT_W}"
check "JSON: nested git markers are listed" bash -c '(cd "$1" && "$2" -J) | jq -e ".[-1].nested_git_markers | length == 30" >/dev/null' _ "${W}" "${TREE}"

# ---------------------------------------------------------------------------
# Work bounds: --count and --read-limit
# ---------------------------------------------------------------------------
check "collapse detail uses singular file" has "$(run --inventory full -L 1)" '▸ dev/  1 file, 2 B'
OUT_S="$(run --inventory full -L 1 --count shown)"
check "--count shown: collapsed directory lines are uncounted" grep -Eq '^ *— .*▸ bulk/  40 files' <<< "${OUT_S}"
check "--count shown: listed files are counted" grep -Eq '^ *1 .*── partial.txt$' <<< "${OUT_S}"
check "--count shown: footer names the cause" grep -Eq '^lines: incomplete; [0-9]+ files not listed \(--count shown\)' <<< "${OUT_S}"
OUT_R="$(run --read-limit 8)"
check "--read-limit: footer names the limit" grep -Eq 'past --read-limit 8 B' <<< "${OUT_R}"
check "--read-limit: totals degrade to N+" grep -Eq '^ *[0-9]+\+ +\* +\.$' <<< "${OUT_R}"
check "--count rejects unknown modes, listing valid ones" bash -c '! out="$(cd "$1" && "$2" --count most 2>&1)" && grep -qF "all, shown, none" <<<"$out"' _ "${R}" "${TREE}"

# ---------------------------------------------------------------------------
echo
if ((${#FAILURES[@]})); then
    echo "${#FAILURES[@]} failed:"
    printf '  %s\n' "${FAILURES[@]}"
    exit 1
fi
echo "all passed"
