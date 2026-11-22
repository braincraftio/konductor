# Condensed command output (rtk)

Shell commands run through `rtk`, which condenses their output: passing tests collapse to a count,
diffs and logs are shortened, long lists are capped. Exit codes are unchanged.

When the full output is required — reading every line, quoting exact text, reviewing a complete diff
before a commit — retrieve it rather than infer it:

- `atuin_output` (Atuin MCP) returns the captured output of a command by its history ID;
  `atuin_history` finds the ID.
- `rtk bypass <command>` runs one command unfiltered.

The rtk recall store is disabled; `rtk recall` hints do not appear.
