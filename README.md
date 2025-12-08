# GitFlow Husky Custom Hooks

This repository contains only custom Git hooks for Husky, usable as a git submodule.

## Repository Structure

- **Custom Git hooks** at the root:
  - applypatch-msg
  - commit-msg
  - post-applypatch
  - post-checkout
  - post-commit
  - post-merge
  - post-rewrite
  - pre-applypatch
  - pre-auto-gc
  - pre-commit
  - pre-merge-commit
  - pre-push
  - pre-rebase
  - prepare-commit-msg
- **Shell scripts** in `libs/`:
  - changelog.sh
  - commit_rules.sh
  - common.sh
  - gitflow.sh
  - json-to-changelog.js
  - tag_process.sh
  - update-changelog-json.js
- **Metadata** in `meta/`:
  - .changelog.json

## Usage

This repository is designed to be integrated as a git submodule in your projects to automate commit rules, changelog, and tag management via Husky.

## Installation

1. Install all required dependencies:

```bash
pnpm add -D husky @commitlint/cli @commitlint/config-conventional eslint lint-staged prettier @eslint/js @padcmoi/gitflow-husky-custom-hooks@github:padcmoi/GitFlow-Husky-Custom-Hooks#main --ignore-scripts
```

2. Add the `postinstall` script:

Option A — Edit `package.json` manually:

```json
"scripts": {
  "postinstall": "cp -R node_modules/@padcmoi/gitflow-husky-custom-hooks/. .husky/ 2>/dev/null && sh .husky/husky-install.sh && git push"
}
```

Option B — Use the pnpm command:

```bash
pnpm pkg set scripts.postinstall="cp -R node_modules/@padcmoi/gitflow-husky-custom-hooks/. .husky/ 2>/dev/null && sh .husky/husky-install.sh && git push"
```

3. Complete the installation:

```bash
pnpm install
```

## License

See the `LICENSE` file.
