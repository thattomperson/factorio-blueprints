#!/usr/bin/env node
// Prepend a section for the current info.json version to changelog.txt (Factorio's in-game format),
// built from the conventional commits since the previous tag. Run by commit-and-tag-version after it
// has bumped info.json and written CHANGELOG.md (see .versionrc.json), or by hand:
//   node tools/factorio-changelog.mjs [--dry-run]
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const SEPARATOR = "-".repeat(99);
const CATEGORIES = [
  // [conventional type, Factorio changelog category] in display order
  ["breaking", "Changes"],
  ["feat", "Features"],
  ["perf", "Optimizations"],
  ["fix", "Bugfixes"],
];

const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();

function previousTag() {
  try {
    return execFileSync("git", ["describe", "--tags", "--abbrev=0", "--match", "v*"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null; // no tags yet: use the whole history
  }
}

function parse(subject, body) {
  const m = /^(\w+)(?:\([^)]*\))?(!)?:\s*(.+)$/.exec(subject);
  if (!m) return null;
  const [, type, bang, text] = m;
  const breaking = Boolean(bang) || /^BREAKING[ -]CHANGE:/m.test(body);
  return { type, text, breaking };
}

function sentence(text) {
  const t = text.trim();
  const s = t.charAt(0).toUpperCase() + t.slice(1);
  return /[.!?]$/.test(s) ? s : s + ".";
}

export function buildSection(version, date, commits) {
  const groups = new Map(CATEGORIES.map(([, cat]) => [cat, []]));
  for (const { subject, body } of commits) {
    const c = parse(subject, body);
    if (!c) continue;
    if (c.breaking) groups.get("Changes").push("Breaking: " + sentence(c.text));
    else {
      const entry = CATEGORIES.find(([type]) => type === c.type);
      if (entry) groups.get(entry[1]).push(sentence(c.text));
    }
  }
  const lines = [SEPARATOR, `Version: ${version}`, `Date: ${date}`];
  let any = false;
  for (const [, cat] of CATEGORIES) {
    const items = groups.get(cat);
    if (!items.length) continue;
    any = true;
    lines.push(`  ${cat}:`);
    for (const item of items) lines.push(`    - ${item}`);
  }
  if (!any) lines.push("  Changes:", "    - Maintenance release.");
  return lines.join("\n") + "\n";
}

function main() {
  const dryRun = process.argv.includes("--dry-run");
  const { version } = JSON.parse(readFileSync("info.json", "utf8"));
  const existing = readFileSync("changelog.txt", "utf8");
  if (new RegExp(`^Version: ${version.replace(/\./g, "\\.")}$`, "m").test(existing)) {
    console.log(`changelog.txt already has ${version}; leaving it alone.`);
    return;
  }
  const tag = previousTag();
  const range = tag ? [`${tag}..HEAD`] : [];
  const raw = git("log", ...range, "--no-merges", "--format=%s%x1f%b%x1e");
  const commits = raw
    .split("\x1e")
    .map((r) => r.trim())
    .filter(Boolean)
    .map((r) => {
      const [subject, body = ""] = r.split("\x1f");
      return { subject: subject.trim(), body };
    });
  const date = new Date().toISOString().slice(0, 10);
  const section = buildSection(version, date, commits);
  if (dryRun) {
    process.stdout.write(section);
    return;
  }
  writeFileSync("changelog.txt", section + existing);
  console.log(`changelog.txt: added ${version} from ${commits.length} commit(s) since ${tag ?? "the beginning"}.`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
