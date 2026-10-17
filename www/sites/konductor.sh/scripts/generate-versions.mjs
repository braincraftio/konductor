import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../../../", import.meta.url));
const destination = new URL("../src/data/", import.meta.url);
const output = execFileSync(
  "nix",
  ["build", ".#versions-json", "--no-link", "--print-out-paths", "--no-update-lock-file"],
  { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }
).trim();
mkdirSync(destination, { recursive: true });
// Store files are read-only. Replace atomically with a writable generated file
// so consecutive builds also work after an earlier copy from the Nix store.
const temporary = new URL(`versions.${process.pid}.json.tmp`, destination);
writeFileSync(temporary, readFileSync(output));
renameSync(temporary, new URL("versions.json", destination));
