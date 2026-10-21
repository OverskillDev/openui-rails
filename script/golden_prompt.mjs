// Dumps the system prompt the reference generator (@openuidev/lang-core) emits
// for a LibrarySpec JSON file, so test/library/prompt_test.rb can compare the
// Ruby generator byte for byte.
//
//   node script/golden_prompt.mjs <lang-core-dist-dir> <spec.json> [options.json]
//
// Requires a local build of thesysdev/openui (pnpm install && pnpm --filter
// @openuidev/lang-core build). Output goes to stdout.
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const [dist, specPath, optionsPath] = process.argv.slice(2);
if (!dist || !specPath) {
  console.error("usage: node script/golden_prompt.mjs <lang-core-dist-dir> <spec.json> [options.json]");
  process.exit(2);
}
const require = createRequire(import.meta.url);
const core = require(resolve(dist, "index.cjs"));
const library = JSON.parse(readFileSync(specPath, "utf8"));
const promptOptions = optionsPath ? JSON.parse(readFileSync(optionsPath, "utf8")) : undefined;
process.stdout.write(core.generateSystemPrompt({ library, promptOptions }));
