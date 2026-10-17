import { appendFileSync } from "node:fs";
import semanticRelease from "../../semantic-release/node_modules/semantic-release/index.js";

const result = await semanticRelease();
const outputs = result
  ? {
      new_release: "true",
      version: result.nextRelease.version,
      tag: result.nextRelease.gitTag,
    }
  : { new_release: "false" };

for (const [key, value] of Object.entries(outputs)) {
  appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
}
