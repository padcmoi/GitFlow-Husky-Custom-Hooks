#!/usr/bin/env node
/* eslint-disable no-undef */
/* eslint-disable @typescript-eslint/no-require-imports */

const fs = require("fs");
const { execSync } = require("child_process");
const prettier = require("prettier");

function readArgOrExit(idx, name) {
  const v = process.argv[idx];
  if (!v) {
    console.error(`Missing ${name}`);
    process.exit(1);
  }
  return v;
}

const VERSION = readArgOrExit(2, "version (ex: 1.2.0)");
const JSON_PATH = readArgOrExit(3, "path to changelog.json");

function sanitizeJsonString(str) {
  str = str.replace(/^\s*,\s*$/gm, "");
  str = str.replace(/,\s*([\]}])/g, "$1");
  return str;
}

function loadJson(path) {
  if (!fs.existsSync(path)) {
    return {
      title: null,
      description: "This file lists the changes by version.",
      tags: [],
    };
  }
  const raw = fs.readFileSync(path, "utf8");
  try {
    return JSON.parse(raw);
  } catch {
    const fixed = sanitizeJsonString(raw);
    const parsed = JSON.parse(fixed);
    fs.writeFileSync(path, JSON.stringify(parsed, null, 2) + "\n", "utf8");
    return parsed;
  }
}

async function saveJson(path, data) {
  const rawJson = JSON.stringify(data, null, 2);
  const config = (await prettier.resolveConfig(path)) || {};
  const prettyJson = await prettier.format(rawJson, {
    ...config,
    parser: "json",
    filepath: path,
  });
  fs.writeFileSync(path, prettyJson, "utf8");
}

function runGit(cmd) {
  return execSync(cmd, { encoding: "utf8" }).trim();
}

function parseVersionString(str) {
  if (!str) return null;
  const clean = str.replace(/^v/, "");
  const match = clean.match(/^(\d+)\.(\d+)(?:\.(\d+))?$/);
  if (!match) return null;
  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = match[3] ? Number(match[3]) : 0;
  return {
    major,
    minor,
    patch,
    normalized: `${major}.${minor}.${patch}`,
  };
}

function getSemverTags() {
  let out;
  try {
    out = runGit("git tag");
  } catch {
    return [];
  }
  if (!out.trim()) return [];
  const names = out
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
  const tags = [];
  for (const name of names) {
    const info = parseVersionString(name);
    if (!info) continue;
    tags.push({
      name,
      major: info.major,
      minor: info.minor,
      patch: info.patch,
      normalized: info.normalized,
    });
  }
  return tags;
}

function isLess(a, b) {
  if (a.major !== b.major) return a.major < b.major;
  if (a.minor !== b.minor) return a.minor < b.minor;
  return a.patch < b.patch;
}

function findPrevTag(tags, target) {
  let prev = null;
  for (const t of tags) {
    if (isLess(t, target)) {
      if (!prev || isLess(prev, t)) {
        prev = t;
      }
    }
  }
  return prev;
}

function getCommitsForVersion(version) {
  const targetInfo = parseVersionString(version);
  const tags = getSemverTags();

  let range;

  if (targetInfo && tags.length > 0) {
    const current = tags.find((t) => t.normalized === targetInfo.normalized);
    if (current) {
      const prev = findPrevTag(tags, current);
      range = prev ? `${prev.name}..${current.name}` : current.name;
    } else {
      const prev = findPrevTag(tags, targetInfo);
      if (prev) {
        range = `${prev.name}..HEAD`;
      } else {
        const base = runGit("git rev-list --max-parents=0 HEAD | tail -n1");
        range = `${base}..HEAD`;
      }
    }
  } else {
    const base = runGit("git rev-list --max-parents=0 HEAD | tail -n1");
    range = `${base}..HEAD`;
  }

  let out = "";
  try {
    out = runGit(`git log ${range} --pretty=format:%s`);
  } catch {
    return [];
  }
  if (!out.trim()) return [];
  return out
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
}

// Add    -> feat, docs
// Change -> fix, revert
// Remove -> remove
function classifyCommits(commits) {
  const add = [];
  const change = [];
  const remove = [];

  for (const msg of commits) {
    const match = msg.match(/^(\w+)(\(([^)]+)\))?:\s*(.+)$/);
    if (!match) continue;

    const type = match[1].toLowerCase();
    const scope = match[3] || "";
    const subject = match[4].trim();

    const formatted = scope ? `(${scope}) ${subject}` : subject;

    switch (type) {
      case "feat":
      case "docs":
        add.push(formatted);
        break;
      case "fix":
      case "revert":
        change.push(formatted);
        break;
      case "remove":
        remove.push(formatted);
        break;
    }
  }

  return { add, change, remove };
}

function parseSemver(v) {
  const clean = v.replace(/^v/, "");
  const parts = clean.split(".");
  return {
    major: parseInt(parts[0] || "0", 10) || 0,
    minor: parseInt(parts[1] || "0", 10) || 0,
    patch: parseInt(parts[2] || "0", 10) || 0,
  };
}

function sortTagsDesc(tags) {
  return [...tags].sort((a, b) => {
    const va = parseSemver(a.version);
    const vb = parseSemver(b.version);
    if (va.major !== vb.major) return vb.major - va.major;
    if (va.minor !== vb.minor) return vb.minor - va.minor;
    return vb.patch - va.patch;
  });
}

(async () => {
  const json = loadJson(JSON_PATH);
  if (!Array.isArray(json.tags)) json.tags = [];

  const commits = getCommitsForVersion(VERSION);
  const { add, change, remove } = classifyCommits(commits);

  const today = new Date().toISOString().slice(0, 10);

  const otherTags = json.tags.filter((t) => t.version !== VERSION);

  const newTag = {
    version: VERSION,
    date: today,
    add,
    change,
    remove,
  };

  const mergedTags = sortTagsDesc([...otherTags, newTag]);

  json.tags = mergedTags;

  await saveJson(JSON_PATH, json);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
