// Runs `binary --debug-doc-eval` over many items in parallel chunks.
// items: [{ commands: string, blocks: number }]. Returns, per item, the
// array of output blocks, or { refused: reason }.
import fs from "node:fs";
import path from "node:path";
import { run, pool, JOBS } from "../../lib.mjs";
import { parseBlocks } from "./doc-text.mjs";

export async function evalItems(bin, items, dir, { chunkBytes = 200_000, chunkItems = 40 } = {}) {
  fs.mkdirSync(dir, { recursive: true });
  const chunks = [];
  let cur = [], size = 0;
  items.forEach((item, i) => {
    cur.push(i);
    size += item.commands.length;
    if (size > chunkBytes || cur.length >= chunkItems) {
      chunks.push(cur);
      cur = [];
      size = 0;
    }
  });
  if (cur.length) chunks.push(cur);
  const results = new Array(items.length);
  const runList = async (idx, file) => {
    fs.writeFileSync(file, idx.map((i) => items[i].commands).join(""));
    return run(bin, ["--debug-doc-eval", file], { timeout: 300_000 });
  };
  await pool(chunks, JOBS, async (chunk, ci) => {
    const r = await runList(chunk, path.join(dir, `chunk${ci}.txt`));
    if (r.status === 0) {
      const blocks = parseBlocks(r.stdout);
      let at = 0;
      for (const i of chunk) {
        results[i] = blocks.slice(at, at + items[i].blocks);
        at += items[i].blocks;
      }
      return;
    }
    for (const i of chunk) {
      const r1 = await runList([i], path.join(dir, `chunk${ci}-${i}.txt`));
      results[i] = r1.status === 0 ? parseBlocks(r1.stdout)
        : { refused: r1.stderr.toString().trim() || `exit ${r1.status} ${r1.signal ?? ""}` };
    }
  });
  return results;
}

// first difference of two strings, for reports
export function showDiff(expected, actual, width = 50) {
  let i = 0;
  while (i < expected.length && expected[i] === actual[i]) i++;
  return `at ${i}\n  expected: ${JSON.stringify(expected.slice(Math.max(0, i - width), i + width))}\n  binary:   ${JSON.stringify(actual.slice(Math.max(0, i - width), i + width))}`;
}
