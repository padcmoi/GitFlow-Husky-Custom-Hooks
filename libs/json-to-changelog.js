#!/usr/bin/env node
/* eslint-disable no-undef */
/* eslint-disable @typescript-eslint/no-require-imports */

const fs = require("fs");
const prettier = require("prettier");

function readArgOrExit(idx, name) {
  const v = process.argv[idx];
  if (!v) {
    console.error(`Missing ${name}`);
    process.exit(1);
  }
  return v;
}

const JSON_PATH = readArgOrExit(2, "path to changelog.json");
const MD_PATH = process.argv[3] || "CHANGELOG.md";

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
    return JSON.parse(fixed);
  }
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

function formatDate(dateStr) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return dateStr;

  const day = String(d.getDate()).padStart(2, "0");
  const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const month = monthNames[d.getMonth()];
  const year = d.getFullYear();

  return `${day} ${month} ${year}`;
}

const data = loadJson(JSON_PATH);
const title = data.title || "CHANGELOG";
const description = data.description || "";
const tags = Array.isArray(data.tags) ? sortTagsDesc(data.tags) : [];

const lines = [];

lines.push(`# ${title}`, "");

if (description) {
  lines.push(description.trim(), "");
}

for (const tag of tags) {
  const niceDate = formatDate(tag.date);
  const dateSuffix = niceDate ? ` (${niceDate})` : "";

  lines.push(`## v${tag.version}${dateSuffix}`, "");

  const blocks = [
    ["Add", tag.add || []],
    ["Change", tag.change || []],
    ["Remove", tag.remove || []],
  ];

  for (const [sectionTitle, items] of blocks) {
    lines.push(`### ${sectionTitle}`, "");
    if (!items.length) {
      lines.push("-");
    } else {
      for (const item of items) {
        lines.push(`- ${item}`);
      }
    }
    lines.push("");
  }
}

while (lines.length && lines[lines.length - 1].trim() === "") {
  lines.pop();
}

(async () => {
  const content = lines.join("\n") + "\n";
  const config = (await prettier.resolveConfig(MD_PATH)) || {};
  const pretty = await prettier.format(content, {
    ...config,
    parser: "markdown",
    filepath: MD_PATH,
  });
  fs.writeFileSync(MD_PATH, pretty, "utf8");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
