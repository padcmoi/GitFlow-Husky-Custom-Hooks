#!/usr/bin/env sh

. "$(dirname "$0")/libs/common.sh" 2>/dev/null || true
common_libs 2>/dev/null || true

. "$(dirname "$0")/libs/commit_rules.sh" 2>/dev/null || true
. "$(dirname "$0")/libs/tag_process.sh" 2>/dev/null || true
. "$(dirname "$0")/libs/changelog.sh" 2>/dev/null || true

FILES_TO_ADD=""

add_file() {
	case " $FILES_TO_ADD " in
	*" $1 "*) ;;
	*) FILES_TO_ADD="$FILES_TO_ADD $1" ;;
	esac
}

# remove the folder to avoid crashes
[ -d ".husky/_" ] && rm -R .husky/_

# create git files and merge if needed
for f in .gitattributes .gitconfig .gitignore; do
	src=".husky/${f}.husky"
	dest="$f"
	[ -f "$src" ] || continue
	[ -f "$dest" ] || touch "$dest"
	while IFS= read -r line; do
		grep -Fxq "$line" "$dest" 2>/dev/null || {
			[ -n "$(tail -c1 "$dest" 2>/dev/null)" ] && printf "\n\n" >>"$dest"
			echo "$line" >>"$dest"
			add_file "$dest"
		}
	done <"$src"

	rm -f "$src"
done

# create shortcut for gitflow commands
tmp_gitflow="$(mktemp)"
cat >"$tmp_gitflow" <<'EOF'
#!/usr/bin/env sh
set -e

sh .husky/libs/gitflow.sh "$@"
EOF

# checks if these essential scripts are present and if not, generates empty scripts
npm pkg get scripts --json | grep -q '"format"' || npm pkg set scripts.format="echo 'script does not exist'"
npm pkg get scripts --json | grep -q '"lint"' || npm pkg set scripts.lint="echo 'script does not exist'"

if [ ! -f "gitflow" ] || ! cmp -s "$tmp_gitflow" "gitflow" 2>/dev/null; then
	mv "$tmp_gitflow" "gitflow"
	chmod +x gitflow
	add_file "gitflow"
else
	rm -f "$tmp_gitflow"
	chmod +x gitflow 2>/dev/null || true
fi

# Add commitlint with the recommended configuration for proper Husky operation
if [ ! -f "commitlint.config.cjs" ]; then
	cat >commitlint.config.cjs <<'EOF'
/* eslint-disable no-undef */
module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "header-max-length": [2, "always", 100],
    "type-enum": [
      2,
      "always",
      [
        "fix",
        "feat",
        "docs",
        "style",
        "refactor",
        "perf",
        "test",
        "chore",
        "build",
        "ci",
        "revert",
        "remove",

        //
      ],
    ],
    "scope-enum": [1, "always", ["api1", "api2", "db", "ui", "core"]],
    "subject-empty": [2, "never"],
  },
};
EOF
	add_file "commitlint.config.cjs"
fi

# commit
if [ -n "$FILES_TO_ADD" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
	git add $FILES_TO_ADD
	git add package.json
	git commit -m "chore: Install husky custom hooks" --no-verify
	echo "Install husky custom hooks"
fi

# reinstall husky
npx husky .husky

# generate the first tag if needed
check_init_inital_release
