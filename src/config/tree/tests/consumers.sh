#!/usr/bin/env bash
# Consumer contracts shared by local verification and the Nix install check.
#
# SC2016: `bash -c '...' _ ARGS` bodies are single-quoted so $1 and $2 expand
# in the child shell from its positional arguments, not here.
# SC2312: command substitutions supply the output under assertion; a failing
# tree run yields output the assertion rejects, so the check fails visibly.
# shellcheck disable=SC2016,SC2312
set -euo pipefail
TREE="${1:?usage: consumers.sh /absolute/path/to/tree}"
FIX="$(mktemp -d)"
trap 'chmod -R u+w "$FIX"; command rm -r "$FIX"' EXIT
export HOME="${FIX}/home" GIT_CONFIG_NOSYSTEM=1
unset NO_COLOR CLICOLOR_FORCE
mkdir -p "${HOME}" "${FIX}/repo/src" "${FIX}/repo/target"
R="${FIX}/repo"
printf '*.qcow2\n' > "${FIX}/.rgignore"
printf '!Dockerfile.qcow2\ntarget/\n' > "${R}/.gitignore"
printf 'one\ntwo\n' > "${R}/src/main.txt"
printf 'image\n' > "${R}/Dockerfile.qcow2"
printf '\0binary' > "${R}/src/binary"
printf 'artifact\n' > "${R}/target/artifact"
git -C "${R}" init -q
git -C "${R}" add .
git -C "${R}" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
printf 'three\n' >> "${R}/src/main.txt"
git -C "${R}" rm --cached -q src/binary
FAILURES=0
check() {
    local name="$1"
    shift
    if "$@"; then
        printf 'ok   %s\n' "${name}"
    else
        printf 'FAIL %s\n' "${name}"
        FAILURES=$((FAILURES + 1))
    fi
}
OUT="$("${TREE}" "${R}")"
JSON="$("${TREE}" -J "${R}")"
check 'global column header' grep -Eq '^ *LINES +GIT +PATH$' <<< "${OUT}"
check 'file lines and porcelain columns' grep -Eq '^ *3 + M .*main.txt' <<< "${OUT}"
check 'binary preserves complete directory total' grep -Eq '^ *3 .*src/' <<< "${OUT}"
check 'binary preserves complete report' jq -e '.[-1].files_uncounted == 0 and .[-1].lines_complete' <<< "${JSON}"
check 'listing explains its markers' grep -F 'legend:' <<< "${OUT}"
check 'binary classification' grep -Eq '^ *bin .*binary' <<< "${OUT}"
check 'parent ignore provenance in text' grep -F '../.rgignore' <<< "${OUT}"
check 'parent ignore pattern in text' grep -F '*.qcow2' <<< "${OUT}"
check 'parent ignore provenance in JSON' jq -e '
  .[-1].omissions | any(.path == "Dockerfile.qcow2"
    and .source == "../.rgignore" and .pattern == "*.qcow2"
    and (.reveal | contains("--no-ignore")))' <<< "${JSON}"
check 'exact multiple git records' jq -e '
  [.. | objects | select(.path? == "src/binary")][0].git == ["??", "D "]' <<< "${JSON}"
check 'deterministic output' test "${OUT}" = "$("${TREE}" "${R}")"
check 'terminal and pipe contain identical information' python3 - "${TREE}" "${R}" << 'PY'
import errno
import os
import pty
import re
import subprocess
import sys

tree, root = sys.argv[1:]
master, slave = pty.openpty()
proc = subprocess.Popen([tree, root], stdout=slave)
os.close(slave)
chunks = []
while True:
    try:
        chunk = os.read(master, 65536)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    chunks.append(chunk)
os.close(master)
assert proc.wait() == 0
terminal = re.sub(rb"\x1b\[[0-9;]*m", b"", b"".join(chunks)).replace(b"\r\n", b"\n")
piped = subprocess.check_output([tree, root])
assert terminal == piped, "terminal and pipe differ beyond ANSI and terminal newline translation"
PY
printf 'one\n' > "${R}/src/"$'invalid\xff'
check 'non-UTF-8 paths retain exact bytes' jq -e '
  [.. | objects | select(.path_bytes? == [115,114,99,47,105,110,118,97,108,105,100,255])] | length == 1' <<< "$("${TREE}" -J "${R}")"
check 'non-UTF-8 names have reversible text escapes' grep -F 'invalid\xff' <<< "$("${TREE}" "${R}")"
rm "${R}/src/"$'invalid\xff'
check 'footer categories have no semicolon wall' bash -c '! grep -q "^hidden:.*;" <<< "$1"' _ "${OUT}"
check 'directory JSON classifies binary without incomplete counts' jq -e '
  [.. | objects | select(.path? == "src")][0].lines_complete == true' <<< "${JSON}"
printf 'secret\n' > "${R}/src/locked"
chmod 000 "${R}/src/locked"
dd if=/dev/zero of="${R}/src/large" bs=1 count=0 seek=67108865 2> /dev/null
STATES="$("${TREE}" -J "${R}")"
check 'unreadable state survives JSON' jq -e '
  [.. | objects | select(.path? == "src/locked")][0].line_state == "unreadable"' <<< "${STATES}"
check 'oversize state survives JSON' jq -e '
  [.. | objects | select(.path? == "src/large")][0].line_state == "too_large"' <<< "${STATES}"
chmod 600 "${R}/src/locked"
rm "${R}/src/locked" "${R}/src/large"
check 'byte sizes with -s' grep -Eq '(^| )14( |$).*main.txt' <<< "$("${TREE}" -s "${R}")"
check 'human sizes with -h' grep -F '14 B' <<< "$("${TREE}" -h "${R}")"
check 'JSON noreport' jq -e 'all(.[]; .type != "report")' <<< "$("${TREE}" -J --noreport "${R}")"
mkdir "${R}/--raw"
check 'double dash protects raw operand' "${TREE}" -- "${R}/--raw"
check 'literal raw directory is not a mode switch' bash -c 'cd "$1" && "$2" -- --raw' _ "${R}" "${TREE}"
check 'initialize config' "${TREE}" --init "${R}"
if [[ -f "${R}/.tree.toml" ]]; then
    BEFORE="$(cat "${R}/.tree.toml")"
    check 'init refuses overwrite' bash -c '! "$1" --init "$2"' _ "${TREE}" "${R}"
    check 'init preserves existing bytes' test "${BEFORE}" = "$(cat "${R}/.tree.toml")"
else
    check 'init creates config' test -f "${R}/.tree.toml"
fi
check 'effective configuration' "${TREE}" --print-config "${R}"
printf '[defaults]\ncount = "none"\n' > "${R}/.tree.toml"
check 'disabled counts survive JSON' jq -e '
  [.. | objects | select(.path? == "src/main.txt")][0].line_state == "not_counted"' <<< "$("${TREE}" -J "${R}")"
check 'flag overrides config with provenance' jq -e '.level.value == 2 and .level.source == "-L"' <<< "$("${TREE}" -L 2 --print-config "${R}")"
printf '[defaults]\nlevel = 1\n["/target/"]\ncollapse = true\nignore_typo = true\n' > "${R}/.tree.toml"
check 'invalid configuration fails' bash -c '! "$1" "$2"' _ "${TREE}" "${R}"
printf 'ignore = ["!target/", "never-matches/"]\n["/target/"]\ncollapse = true\n' > "${R}/.tree.toml"
CFG="$("${TREE}" "${R}")"
check 'collapse marker and reason' grep -Eq '▸ target/.*\[.tree.toml\]' <<< "${CFG}"
check 'stale pattern diagnostic' grep -F 'never-matches/' <<< "${CFG}"
printf 'ignore = ["!target/", "/target/artifact"]\n["/target/"]\ncollapse = true\n' > "${R}/.tree.toml"
check 'collapse preserves visibility rules' jq -e '
  [.. | objects | select(.path? == "target")][0].files == 0' <<< "$("${TREE}" --scan-collapsed -J "${R}")"
check 'reshown paths still honor -I' jq -e '
  [.. | objects | select(.path? == "target")] | length == 0' <<< "$("${TREE}" -I target -J "${R}")"
printf 'hidden\n' > "${R}/target/.hidden"
check 'reshown ancestor covers inherited descendants' jq -e '
  .[-1].shown_by_tree_toml == ["target/"]' <<< "$("${TREE}" -J "${R}")"
mkdir "${R}/hidden-only"
printf 'ignore = ["!target/"]\n["/target/"]\ncollapse = true\n' > "${R}/.tree.toml"
check 'collapsed reshown inventory is explicitly unknown' jq -e '
  [.. | objects | select(.path? == "target")][0] |
  .inventory_complete == false and .files == null and .reshown == true' <<< "$("${TREE}" -J "${R}")"
check 'reshown files do not pollute ordinary totals' jq -e '
  .[-1].files == 2 and .[-1].files_uncounted == 0' <<< "$("${TREE}" -J "${R}")"
printf 'image\n' > "${R}/hidden-only/image.qcow2"
check 'hidden-only directory is annotated' grep -E 'hidden-only/.*\[hidden: 1\]' <<< "$("${TREE}" "${R}")"
check 'hidden boundary count survives JSON' jq -e '
  [.. | objects | select(.path? == "hidden-only")][0].hidden_entries == 1' <<< "$("${TREE}" -J "${R}")"
for n in $(seq 1 30); do touch "${R}/.hidden-${n}"; done
check 'footer caps names with JSON escape hatch' grep -F 'more (tree -J for all)' <<< "$("${TREE}" "${R}")"
check 'valid UTF-8 paths omit raw byte arrays' jq -e '
  [.. | objects | select(.path? == "src/main.txt")][0] | has("path_bytes") | not' <<< "$("${TREE}" -J "${R}")"
check 'directory Git codes have a distinct field' jq -e '
  [.. | objects | select(.path? == "src")][0] | has("git") | not' <<< "$("${TREE}" -J "${R}")"
check 'explicit metadata scan counts the re-shown tree' jq -e '
  [.. | objects | select(.path? == "target")][0] |
  .inventory_complete == true and .files == 2' <<< "$("${TREE}" --scan-collapsed -J "${R}")"
check 'effective rules are ordered parsed records' jq -e '
  .rules.visibility[0].pattern == "!target/" and
  .rules.presentation[0].pattern == "/target/" and
  .rules.presentation[0].collapse == true' <<< "$("${TREE}" --print-config "${R}")"
check 'size provenance names the winning flag' jq -e '
  .sizes.source == "-h" and .sizes.value == "human"' <<< "$("${TREE}" -hs --print-config "${R}")"
mkdir "${FIX}/second"
printf '[defaults]\nlevel = 3\nbudget = 7\n' > "${FIX}/second/.tree.toml"
check 'multiple roots preserve their own effective settings' jq -e '
  [.[] | select(.type == "report")] | length == 2 and
  .[0].level == null and .[0].budget == 12000 and
  .[1].level == 3 and .[1].budget == 7' <<< "$("${TREE}" -J "${R}" "${FIX}/second")"
mkdir -p "${FIX}/invalid-init/"$'invalid\xff'
check 'init tolerates invalid UTF-8 directory names' "${TREE}" --init "${FIX}/invalid-init"
check 'init comments the skipped byte name' grep -F 'invalid\xff' "${FIX}/invalid-init/.tree.toml"
cp "${R}/.git/index" "${FIX}/index"
printf 'corrupt\n' > "${R}/.git/index"
check 'git failure is explicit in text' grep -F 'git: status unavailable' <<< "$("${TREE}" "${R}")"
check 'git failure is explicit in JSON' jq -e '.[-1].git_error | type == "string"' <<< "$("${TREE}" -J "${R}")"
cp "${FIX}/index" "${R}/.git/index"
printf '[z-a]\n*.global-hidden\n' > "${HOME}/global-ignore"
git config --global core.excludesFile "${HOME}/global-ignore"
printf 'hidden\n' > "${R}/file.global-hidden"
check 'malformed global ignores warn without aborting' jq -e '
  .[-1].errors | any(contains("global ignore"))' <<< "$("${TREE}" -J "${R}")"
printf '["/hidden-only/"]\nnote = "boundary note"\n' > "${R}/.tree.toml"
check 'hidden annotation precedes repository note' grep -E 'hidden-only/.*\[hidden: 1\]  # boundary note$' <<< "$("${TREE}" "${R}")"
mkdir -p "${FIX}/outside/child"
printf 'dotfiles = true\n' > "${FIX}/outside/.tree.toml"
check 'non-Git discovery stops at listed root' jq -e '.config == null and .dotfiles.value == false' <<< "$("${TREE}" --print-config "${FIX}/outside/child")"
ln -s $'target\xff' "${R}/byte-link"
check 'symlink target bytes survive text' grep -F 'byte-link -> target\xff' <<< "$("${TREE}" "${R}")"
check 'symlink target bytes survive JSON' jq -e '
  [.. | objects | select(.path? == "byte-link")][0].target_bytes == [116,97,114,103,101,116,255]' <<< "$("${TREE}" -J "${R}")"
printf 'staged\n' > "${R}/staged-delete"
printf 'unstaged\n' > "${R}/unstaged-delete"
git -C "${R}" add staged-delete unstaged-delete
git -C "${R}" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm deletions
git -C "${R}" rm -q staged-delete
rm "${R}/unstaged-delete"
check 'deleted records preserve both porcelain columns' jq -e '
  .[-1].git_deleted |
  any(.path == "staged-delete" and .git == "D ") and
  any(.path == "unstaged-delete" and .git == " D")' <<< "$("${TREE}" -J "${R}")"
check 'small listings use compact metadata columns' grep -E '^LINES  GIT  PATH$' <<< "${OUT}"
check 'empty listing omits unused legend' bash -c '! grep -q "^legend:" <<< "$1"' _ "$("${TREE}" "${R}/--raw")"
check 'routine Git metadata stays out of text footer' bash -c '! grep -q "^hidden  metadata" <<< "$1"' _ "${OUT}"
check 'unscanned inventory explanation occurs only in footer' bash -c '
  ! grep -q "▸ target/.*inventory not scanned" <<< "$1"' _ "${CFG}"
mkdir "${FIX}/disagreement"
printf '[z-a]\n*.omitted\n' > "${FIX}/disagreement/.ignore"
printf 'hidden\n' > "${FIX}/disagreement/file.omitted"
check 'partially invalid ignore file: valid rules credited, bad line reported once' jq -e '
  .[-1] | (.omissions | any(.path == "file.omitted" and .category == "ignore"
    and .source == ".ignore" and .pattern == "*.omitted")) and
  (.omissions | all(.category != "disagreement")) and
  ([.errors[] | select(contains("disagreement/.ignore") and contains("[z-a]"))] | length == 1)' <<< "$("${TREE}" -J "${FIX}/disagreement")"
check 'walker and explainer agree for every omitted boundary' python3 - "${TREE}" "${FIX}" << 'PY'
import json
import pathlib
import subprocess
import sys

tree, fixture = sys.argv[1:]
root = pathlib.Path(fixture) / "parity"
root.mkdir()
(pathlib.Path(fixture) / "home/global-ignore").write_text("*.global\n/parity/anchored\n")
(root / ".git").mkdir()
(root / ".git/info").mkdir()
(root / "nested").mkdir()
(root / ".rgignore").write_text("*.custom\n!keep.custom\n")
(root / ".ignore").write_text("*.local\n")
(root / ".gitignore").write_text("*.gitonly\n")
(root / ".git/info/exclude").write_text("*.excluded\n")
(root / "nested/.ignore").write_text("!keep.local\n")
expected = {
    "a.custom": (".rgignore", "*.custom"),
    "a.local": (".ignore", "*.local"),
    "a.gitonly": (".gitignore", "*.gitonly"),
    "a.excluded": (".git/info/exclude", "*.excluded"),
    "nested/a.local": (".ignore", "*.local"),
    "a.global": ("../home/global-ignore", "*.global"),
    "anchored": ("../home/global-ignore", "/parity/anchored"),
}
visible = {"keep.custom", "nested/keep.local"}
for name in expected.keys() | visible:
    (root / name).write_text("content\n")
report = json.loads(subprocess.check_output([tree, "-aJ", str(root)], cwd=fixture))[-1]
actual = {
    item["path"]: (item["source"], item["pattern"])
    for item in report["omissions"] if item["category"] != "metadata"
}
assert actual == expected, (actual, expected)
assert set(report["hidden"]["ignore_rules"]) == set(expected), report
jj = pathlib.Path(fixture) / "jj-parity"
jj.mkdir()
(jj / ".jj").mkdir()
(jj / ".gitignore").write_text("omitted\n")
(jj / "omitted").write_text("content\n")
report = json.loads(subprocess.check_output([tree, "-aJ", str(jj)]))[-1]
assert any(o["path"] == "omitted" and o["category"] == "ignore"
           and o["source"] == ".gitignore" for o in report["omissions"]), report
PY
mkdir "${FIX}/alignment" "${FIX}/alignment/a" "${FIX}/alignment/long-directory"
printf '["a/"]\nnote = "short note"\n["long-directory/"]\nnote = "long note"\n' > "${FIX}/alignment/.tree.toml"
check 'sibling notes share a column' python3 - "${TREE}" "${FIX}/alignment" << 'PY'
import subprocess
import sys
rows = [row for row in subprocess.check_output(sys.argv[1:], text=True).splitlines()
        if "# short note" in row or "# long note" in row]
assert len(rows) == 2 and len({row.index("#") for row in rows}) == 1, rows
PY
ln -s missing "${R}/tracked-broken"
git -C "${R}" add tracked-broken
git -C "${R}" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm symlink
git -C "${R}" rm --cached -q tracked-broken
check 'existing broken symlink retains staged deletion on its row' jq -e '
  ([.. | objects | select(.path? == "tracked-broken" and .type? == "link")][0].git | index("D ")) != null and
  (.[-1].git_deleted | all(.path != "tracked-broken"))' <<< "$("${TREE}" -J "${R}")"
printf 'dotfiles = true\n' > "${R}/.tree.toml"
check 'Git metadata has no invented counts' python3 - "${TREE}" "${R}" << 'PY'
import json
import subprocess
import sys
tree, root = sys.argv[1:]
row = next(r for r in subprocess.check_output([tree, "-s", root], text=True).splitlines()
           if "▸ .git/" in r)
assert "files" not in row and row.split()[:2] == ["—", "—"], row
node = next(n for n in json.loads(subprocess.check_output([tree, "-J", root]))[0]["contents"]
            if n["path"] == ".git")
assert node["files"] is None and node["bytes"] is None and not node["inventory_complete"], node
PY
check 'direction controls in filenames and notes are escaped' python3 - "${TREE}" "${R}" << 'PY'
import pathlib
import subprocess
import sys
tree, root = sys.argv[1:]
root = pathlib.Path(root)
(root / "name\u202e").write_text("x")
(root / ".tree.toml").write_text('["name*"]\nnote = "note\u202e"\n')
out = subprocess.check_output([tree, str(root)], text=True)
assert "\u202e" not in out and r"name\u{202e}" in out and r"note\u{202e}" in out, out
PY
check 'ignored byte paths retain identity and real parent counts' python3 - "${TREE}" "${R}" << 'PY'
import json
import os
import subprocess
import sys
tree, root = sys.argv[1:]
parent = os.fsencode(root) + b"/parent\xff"
os.mkdir(parent)
with open(parent + b"/hidden\xfe.qcow2", "wb") as f:
    f.write(b"x")
out = subprocess.check_output([tree, root], text=True)
assert r"parent\xff/hidden\xfe.qcow2" in out, out
data = json.loads(subprocess.check_output([tree, "-J", root]))
record = next(o for o in data[-1]["omissions"] if o.get("path_bytes") ==
              list(b"parent\xff/hidden\xfe.qcow2"))
assert record["category"] == "ignore", record
node = next(n for n in data[0]["contents"] if n.get("path_bytes") == list(b"parent\xff"))
assert node["hidden_entries"] == 1, node
PY
check 'inventory states distinguish omitted scans from partial and complete scans' python3 - "${TREE}" "${FIX}" << 'PY'
import json
import pathlib
import subprocess
import sys
tree, fixture = sys.argv[1:]
root = pathlib.Path(fixture) / "inventory-states"
root.mkdir()
(root / ".ignore").write_text("cache/\nother/\n")
(root / ".tree.toml").write_text(
    'ignore = ["!cache/", "!other/"]\n["cache/"]\ncollapse = true\n["other/"]\ncollapse = true\n')
for name in ("cache", "other"):
    (root / name).mkdir()
    (root / name / "file").write_text("data\n")
def inventories(*flags):
    return dict(json.loads(subprocess.check_output([tree, "-J", *flags, str(root)]))[-1]["reshown"])
assert inventories()["cache"] == {"state": "not_scanned"}
out = subprocess.check_output([tree, str(root)], text=True)
assert out.count("--scan-collapsed") == 1 and out.count("inventory not scanned") == 2, out
assert "see errors" not in out, out
complete = inventories("--scan-collapsed")["cache"]
assert complete["state"] == "complete" and complete["totals"]["files"] == 1, complete
locked = root / "cache/locked"
locked.mkdir()
locked.chmod(0)
try:
    partial = inventories("--scan-collapsed")["cache"]
    assert partial["state"] == "incomplete" and partial["totals"]["files"] == 1, partial
    out = subprocess.check_output([tree, "--scan-collapsed", str(root)], text=True)
    assert "inventory incomplete" in out and "inventory not scanned" not in out, out
finally:
    locked.chmod(0o700)
PY
mkdir "${FIX}/init-link"
ln -s missing "${FIX}/init-link/.tree.toml"
check 'init refuses a dangling configuration symlink' bash -c '
  ! "$1" --init "$2" && test -L "$2/.tree.toml" && ! test -e "$2/missing"
' _ "${TREE}" "${FIX}/init-link"
check 'read allowance scope, display priority, large rule sets and redirected rows' python3 - "${TREE}" "${FIX}" << 'PY'
import json
import pathlib
import subprocess
import sys

tree, fixture = sys.argv[1:]
root = pathlib.Path(fixture) / "accounting"
(root / "a").mkdir(parents=True)
(root / "a/file").write_bytes(b"\n\n")
(root / "z").write_bytes(b"x\n")
def listing(*args):
    return json.loads(subprocess.check_output(
        [tree, "--no-config", "--no-ignore", "-J", *args]))
full = listing("--read-limit", "2", str(root))[-1]
shallow = listing("--read-limit", "2", "-L", "1", str(root))[-1]
assert full["lines"] == 2 and shallow["lines"] == 1, (full, shallow)
assert full["content_bytes_read"] == shallow["content_bytes_read"] == 2
multiple = listing("--read-limit", "2", str(root), str(root))
reports = [item for item in multiple if item["type"] == "report"]
assert len(reports) == 2 and all(
    r["content_bytes_read"] == 2 and r["read_limit_scope"] == "per_root"
    for r in reports), reports
for _ in range(3):
    assert listing("--read-limit", "2", str(root))[-1] == full

rules = pathlib.Path(fixture) / "many-rules"
rules.mkdir()
(rules / ".ignore").write_text("".join(f"hidden-{n}\n" for n in range(10_000)))
for n in range(10_000):
    (rules / f"hidden-{n}").touch()
with (pathlib.Path(fixture) / "redirected.txt").open("wb") as output:
    subprocess.run([tree, "-n", str(rules)], stdout=output, check=True)
text = (pathlib.Path(fixture) / "redirected.txt").read_bytes()
assert text.endswith(b"\n") and b"\x1b" not in text and b"\x00" not in text
header, footer = text.split(b"\n\n", 1)
assert len(footer) <= 8192, len(footer)
assert len(header.splitlines()) == 2, header
report = json.loads(subprocess.check_output([tree, "-J", str(rules)]))[-1]
assert sum(o["category"] == "ignore" for o in report["omissions"]) == 10_000
assert b"tree -J" in footer
PY
check 'concurrent mutation keeps read accounting bounded and output parseable' python3 - "${TREE}" "${FIX}" << 'PY'
import json
import pathlib
import subprocess
import sys
import threading

tree, fixture = sys.argv[1:]
root = pathlib.Path(fixture) / "mutation"
root.mkdir()
path = root / "changing"
path.write_bytes(b"x\n")
stop = threading.Event()
def mutate():
    while not stop.is_set():
        path.write_bytes(b"x\n" * 65536)
        path.write_bytes(b"x\n")
worker = threading.Thread(target=mutate)
worker.start()
try:
    for _ in range(8):
        report = json.loads(subprocess.check_output([
            tree, "--no-ignore", "--no-config", "-J",
            "--read-limit", "64K", str(root)], timeout=10))[-1]
        assert report["content_bytes_read"] <= 65536, report
finally:
    stop.set()
    worker.join()
PY
check 'bounded and full inventory scopes, budget, precedence, and unopened subtrees' python3 - "${TREE}" "${FIX}" << 'PY'
import json
import pathlib
import subprocess
import sys

tree, fixture = sys.argv[1:]
root = pathlib.Path(fixture) / "traversal"
(root / "child/deep").mkdir(parents=True)
(root / "child/deep/file").write_text("one\ntwo\n")
(root / "top").write_text("top\n")
(pathlib.Path(fixture) / "home/global-ignore").write_text("")
def listing(*flags):
    return json.loads(subprocess.check_output([tree, "-J", *flags, str(root)]))
for mode in ("all", "shown", "none"):
    data = listing("-L", "1", "--count", mode)
    child = next(n for n in data[0]["contents"] if n["path"] == "child")
    assert child["files"] is None and not child["inventory_complete"], child
    assert data[-1]["inventory"] == "bounded" and not data[-1]["inventory_complete"]
    assert data[-1]["files"] == 1 and data[-1]["content_bytes_read"] <= 4
full = listing("-L", "1", "--inventory", "full")
assert full[-1]["files"] == 2 and full[-1]["lines"] == 3, full
assert full[-1]["inventory_complete"]
assert listing("-L", "1", "--inventory", "full", "--count", "none")[-1]["content_bytes_read"] == 0
budget = listing("--budget", "1")
assert budget[-1]["files"] == 1 and not budget[-1]["inventory_complete"], budget
assert budget[-1]["not_expanded"]["budget"] == 1, budget
assert budget == listing("--budget", "1"), "deterministic budget"
(root / ".tree.toml").write_text('[defaults]\ninventory = "full"\nlevel = 1\n')
assert listing()[-1]["inventory_complete"]
assert not listing("--inventory=bounded")[-1]["inventory_complete"]
settings = json.loads(subprocess.check_output([tree, "--print-config", str(root)]))
assert settings["inventory"] == {"source": ".tree.toml", "value": "full"}, settings
settings = json.loads(subprocess.check_output([tree, "--print-config", "--inventory", "bounded", str(root)]))
assert settings["inventory"] == {"source": "--inventory", "value": "bounded"}, settings
locked = root / "child/deep"
locked.chmod(0)
try:
    assert not listing("--inventory", "bounded")[-1]["errors"], "depth must not open descendants"
    assert listing("--inventory", "full")[-1]["errors"], "full traversal observes unreadable subtree"
finally:
    locked.chmod(0o700)
bad = subprocess.run([tree, "--inventory", "invalid", str(root)], capture_output=True)
assert bad.returncode != 0 and b"bounded, full" in bad.stderr, bad
PY
printf '%s consumer contracts failed\n' "${FAILURES}"
test "${FAILURES}" -eq 0
