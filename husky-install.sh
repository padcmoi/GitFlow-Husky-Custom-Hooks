#!/usr/bin/env sh

. "$(dirname "$0")/libs/common.sh" 2>/dev/null || true
common_libs 2>/dev/null || true

. "$(dirname "$0")/libs/commit_rules.sh" 2>/dev/null || true
. "$(dirname "$0")/libs/tag_process.sh" 2>/dev/null || true
. "$(dirname "$0")/libs/changelog.sh" 2>/dev/null || true

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
		}
	done <"$src"

	rm -f "$src"
done

# create shortcut for gitflow commands
cat >gitflow <<'EOF'
#!/usr/bin/env sh
set -e

sh .husky/libs/gitflow.sh "$@"
EOF
chmod +x gitflow

# commit everything present without push (push is incompatible here)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
	git add .
	git commit -m "chore: Install husky custom hooks" --no-verify
	echo "Install husky custom hooks"
fi

# reinstall husky
npx husky .husky

# generate the first tag if needed
check_init_inital_release
