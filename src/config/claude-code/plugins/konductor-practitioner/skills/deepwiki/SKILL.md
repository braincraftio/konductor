---
name: deepwiki
description: Prompt engineering discipline for DeepWiki MCP queries. Use when querying mcp__plugin_konductor_deepwiki__ask_question, mcp__plugin_konductor_deepwiki__read_wiki_structure, or mcp__plugin_konductor_deepwiki__read_wiki_contents. Also use when the task requires understanding a GitHub repository's internals — architecture, module system, API surface, integration contracts, failure modes — that training-data recall cannot reliably provide. NOT for questions answerable by reading a local file or running a command.
---

# DeepWiki — high-performance RAG query engineering

## What DeepWiki is

DeepWiki is a **vector-embeddings RAG application with an LLM synthesis
frontend**. It indexes GitHub repositories at HEAD of the default branch. The
index contains source code, inline comments, docstrings, test files, README
content, and directory structure — all at the most recent commit. It is
**stateless** — it does not remember prior queries, does not have conversation
context, and responds independently to each query.

It is **not**: a search engine, a documentation site, a changelog database, a
version matrix, a CI log aggregator, or a chatbot with memory. It cannot answer
questions about historical versions, release diffs, dependency compatibility
matrices, or anything not present in the current HEAD source.

## The retrieval mechanism

Vector embeddings match on **term proximity in embedding space**. Every distinct
technical token in the query is a retrieval anchor that pulls chunks from the
indexed source. The more precise, distinct, and domain-specific the tokens, the
more relevant the retrieved chunks, the richer the LLM's synthesis context.

Short vague queries retrieve shallow generic chunks from README-level content.
Long dense queries packed with exact identifiers retrieve deep specific chunks
from implementation files, test assertions, and inline comments — the material
that contains what you don't already know.

**The query IS the retrieval function.** There is no search refinement, no
follow-up, no "can you look deeper." Each query independently determines what
chunks the LLM sees. A weak query cannot be rescued by a follow-up — it must
be rewritten.

## The one rule

**Dump everything you know into the query.** Every piece of accumulated context
— source code you've read, identifiers you've found, errors you've observed,
claims you believe, alternatives you've considered — is retrieval fuel. The
query is not a question to a person; it is a retrieval key into an embedding
index. Longer, denser, more identifier-rich queries outperform shorter ones
unconditionally. There is no circumstance where lazy wording outperforms precise
wording in vector retrieval.

## What belongs in every query

### 1. Exact identifiers from the codebase

Function names, option paths, file paths, module names, attribute names, CLI
flags, config keys, struct fields, CRD field names, error constants, test
names. Each one is a high-precision retrieval anchor that matches against source
code with minimal ambiguity.

```
# WEAK — matches README intros
How does the module system work?

# STRONG — matches implementation files
systemd.user.services attrset, buildService function in modules/systemd.nix,
lib.generators.toINI, WantedBy Install section symlink creation in
~/.config/systemd/user/default.target.wants/, home.activation.reloadSystemd,
sd-switch service diffing between generations, startServices default behavior
```

### 2. Concrete artifacts inlined

The actual source code, the actual config, the actual error output, the actual
command invocations. These are dense with retrievable tokens. Do not summarize
an artifact when you can inline it — the summary loses the identifiers the
embeddings would have matched on.

```
# WEAK
The frolic script checks for flake.nix and exits if missing.

# STRONG
The frolic CLI is a writeShellApplication wrapping a 36-line bash script:
  shell="${1:-default}"
  script=".direnv/frolic-${shell}.sh"
  if [[ ! -f "flake.nix" ]]; then
    echo "frolic: no flake.nix in $PWD" >&2
    exit 1
  fi
  nix print-dev-env --profile ".direnv/frolic-${shell}-profile" "$flake_ref" > "$tmp"
```

### 3. Error messages verbatim

Error strings are high-signal retrieval keys. They match against issue
trackers, commit messages that fixed the error, source code that emits the
error, and comments documenting the failure mode.

```
"libc.so.6: version GLIBC_2.42 not found (required by rm)"
"undefined symbol: __nptl_change_stack_perm, version GLIBC_PRIVATE"
"Failed to set up PAM session: exit code 224"
```

### 4. Adjacent technologies named explicitly

Every technology in the dependency chain, named with its exact identifiers.
Each one pulls chunks from a different part of the index. Missing one means
missing the retrieval neighborhood that contains the integration contract.

```
# For a direnv+nix devshell caching query, name ALL of:
direnv, nix print-dev-env, writeShellApplication, home-manager,
systemd.user.services, mkEnableOption, extraSpecialArgs, xdg.configFile,
home.file, home.packages, WantedBy, Restart, StartLimitBurst, nix-direnv,
programs.direnv, flake inputs, homeModules
```

### 5. Multiple phrasings of key concepts

Redundant phrasings hit different embedding neighborhoods. The index may
contain the concept described one way in a README, another way in a code
comment, another way in a test name.

```
"devshell caching", "materialized shell scripts", "direnv nix integration",
"persistent nix environments", "nix print-dev-env output caching"
```

### 6. Statements with claims asking for correction

"I believe X works by Y mechanism" retrieves differently than "how does X
work?" — every word in the claim is a retrieval anchor that matches against the
actual implementation. The RAG system retrieves chunks that confirm, correct, or
extend the claim.

```
# WEAK
How does home-manager manage systemd services?

# STRONG
I believe home-manager's systemd.user.services attrset is translated to
systemd unit files by the buildService function in modules/systemd.nix using
lib.generators.toINI. The WantedBy Install section creates a symlink in
~/.config/systemd/user/default.target.wants/. home-manager switch triggers
home.activation.reloadSystemd which uses sd-switch to diff old vs new
generations and start/stop/restart changed services. I believe startServices
is enabled by default and home-manager does NOT set StartLimitBurst or
StartLimitIntervalSec. Correct or extend this understanding.
```

### 7. What you already read/tried

Telling the system what you've examined prevents it from wasting synthesis on
ground you've covered and focuses retrieval on the gaps.

```
I read the upstream flake.nix — it exposes packages.${system}.frolic and
homeModules.frolic. I read the homeModule source at modules/home-manager/default.nix
— it uses programs.frolic with mkEnableOption, installs via home.packages, and
places frolic-extension.sh via xdg.configFile. It does NOT create any systemd
service. I read the CLI script at scripts/frolic.sh — 36 lines, no subcommand
dispatch, treats first arg as shell name.
```

### 8. Specific questions requiring cross-file synthesis

After dumping all context, ask questions that cannot be answered by reading a
single file — questions that require the RAG system to synthesize across
multiple retrieved chunks from different parts of the codebase.

```
How does the activation lifecycle interact with the WantedBy symlink creation?
Does the unit start immediately on home-manager switch, or does it wait for
the next login? What happens to a running service when the unit file changes
between generations?
```

## What does NOT belong in queries

- **Version numbers and commit hashes** — DeepWiki indexes current HEAD, not
  release history. Version numbers are not in the index. Function names, option
  paths, and error strings are. Citing "v1.18.5" adds noise; citing
  `--direct-routing-device` adds signal.
- **"How does X work?"** — retrieves README introductions, not implementation.
- **"What are best practices for X?"** — retrieves blog-post-level generic
  advice that may not reflect the actual codebase.
- **Questions answerable by reading one local file** — use the Read tool. DeepWiki
  is for cross-file synthesis across a repository you cannot fully read locally.
- **Changelog / migration questions** — "what changed between v2 and v3" is not
  in the HEAD index.
- **Dependency compatibility matrices** — "does X version A work with Y version
  B" requires release metadata DeepWiki does not index.

## Query structure patterns

### Pattern A — investigate a specific failure

```
[Full technical context: platform, config, dependency chain]
[Concrete artifacts: source code, config files, error output — inlined]
[What was observed vs what was expected]
[What was already read/tried — with file paths]
[Specific questions requiring cross-file synthesis]
```

### Pattern B — understand an integration surface

```
[Component A: exact API surface, exact identifiers, exact behavior observed]
[Component B: exact API surface, exact identifiers, exact behavior observed]
[The integration point: what A expects from B, what B provides to A]
[Specific claims about how they interact, asking for correction/extension]
[Edge case questions at the integration boundary]
```

### Pattern C — evaluate approaches

```
[Problem statement with full constraints — inlined artifacts]
[Approach 1: specific implementation sketch, claimed tradeoffs]
[Approach 2: specific implementation sketch, claimed tradeoffs]
[Approach N: ...]
[Questions requiring implementation-level knowledge to rank them]
[Request for file paths, function names, test names as evidence]
```

### Pattern D — map an unfamiliar subsystem

```
[What I know: exact entry points found, exact files read — cited]
[What I don't know: specific gaps, not vague "how it works"]
[Adjacent systems I know: exact identifiers from neighboring code]
[Request: file paths, function names, data flow, lifecycle, test names]
```

These compose. A real query often combines B + A (understand the integration,
then investigate why it fails) or D + C (map the subsystem, then evaluate
approaches within it).

## Multi-repo queries

`ask_question` accepts `repoName` as a string or array. Use an array when the
question spans multiple repositories — the synthesis draws from all indexed
sources simultaneously.

```python
repoName: ["systemd/systemd", "containers/podman", "moby/moby"]
```

Use multi-repo when: the question involves an integration contract between
projects (e.g., how systemd user services work inside containers requires
systemd's implementation AND container runtimes' systemd support). Do not
use multi-repo for unrelated questions — it dilutes retrieval precision.

## Pre-query reconnaissance

Before formulating a deep query, use the structure and content tools to orient:

1. `read_wiki_structure` — learn what topics are indexed, discover section names
   that become retrieval anchors in your query
2. `read_wiki_contents` — read specific sections to harvest exact identifiers,
   function names, and file paths to embed in your query

This is scouting, not research. The ask_question query is the research. Scout
to gather ammunition for the query, not to answer the question directly from
summaries.

## The research workflow

1. **Read local source first** — clone or nix store path. Harvest identifiers,
   read the code, understand what you can understand locally. DeepWiki does not
   replace reading source; it extends it to cross-file synthesis you cannot do
   by reading files one at a time.

2. **Scout the wiki** — `read_wiki_structure` → `read_wiki_contents` on
   relevant sections. Harvest more identifiers, discover file paths and module
   names you missed.

3. **Formulate the query** — dump everything: local source you read, identifiers
   you found, claims you formed, errors you observed, artifacts inlined, gaps
   identified. Apply the structure patterns above.

4. **Evaluate the response** — did it surface information you did not already
   know? If it only confirmed what you knew, the query was too narrow or too
   pre-loaded with conclusions. Reformulate with broader scope, more gap
   questions, fewer claims.

5. **Follow references** — the response cites file paths, function names, test
   names. Read those locally. The new information becomes context for the next
   query if needed.

6. **Iterate** — each round adds identifiers and understanding. The queries
   get denser and more precise. Stop when the response stops surfacing new
   information.

## Query length

There is no maximum useful length. The frolic query that produced the best
results in this harness was ~600 words with inlined source code, full module
definitions, systemd unit specs, and 12 specific questions. The Ceph NVMe
queries that produced precise protocol-level answers were 200-400 words each
but packed with exact function names, flag names, and protocol identifiers.

**Measure density, not length.** A 100-word query with 30 exact identifiers
outperforms a 500-word query with 5 identifiers and 400 words of prose.

## Anti-patterns

| Anti-pattern | Why it fails | Correct |
|---|---|---|
| "How does X work?" | Retrieves README intros | Inline artifacts + specific claims + gap questions |
| "What are best practices?" | Retrieves generic advice | Name the specific decision with constraints |
| Short vague question | Few retrieval anchors = shallow chunks | Dense identifiers = deep implementation chunks |
| Citing version numbers | Not in the HEAD index | Cite function names, option paths, error strings |
| Asking without reading source first | No identifiers to embed in query | Read locally, harvest identifiers, then query |
| Pre-loaded conclusion seeking confirmation | Confirmation bias in retrieval | State claims AND ask for correction/extension |
| Summarizing artifacts instead of inlining | Summary loses retrievable tokens | Inline the source code, config, error output |
| Follow-up "can you look deeper" | Stateless — each query independent | Rewrite the query with more context |
| Using DeepWiki for a local file read | Adds latency, retrieves approximation | Read tool for local, DeepWiki for cross-file synthesis |
| Asking about historical versions | HEAD-only index | Ask about current implementation, check git log locally for history |
| Multiple unrelated questions in one query | Dilutes retrieval across topics | One coherent topic per query |
| Wiki structure/content reads as the research | Summaries, not source synthesis | Scout tools gather ammunition; ask_question is the research |

## MCP tool reference

```
mcp__plugin_konductor_deepwiki__read_wiki_structure
  repoName: "owner/repo"
  → list of indexed topics and sections

mcp__plugin_konductor_deepwiki__read_wiki_contents
  repoName: "owner/repo"
  → full documentation content for a repository

mcp__plugin_konductor_deepwiki__ask_question
  repoName: "owner/repo" | ["owner/repo", "owner/repo2"]
  question: "<the dense, identifier-rich, artifact-inlined query>"
  → AI-synthesized answer grounded in the repository's source code
```
