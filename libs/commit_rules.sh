#!/usr/bin/env sh

commitlint_error() {
	{
		echo "Your input message: $1"
		echo "❌ Commit rejected: invalid commit message."
		echo ""
		echo "Your commit must follow the Conventional Commit rules:"
		echo ""
		echo "Allowed suffixes:"
		echo "  fix | feat | docs | style | refactor | perf | test | chore | build | ci | revert | remove"
		echo ""
		echo "Scopes:"
		echo "  • Scopes are allowed but not restricted to any specific list."
		echo "  • Use meaningful scopes when relevant (example: api1, core, db, gpt5, etc.)"
		echo ""
		echo "Rules:"
		echo "  • A type is required"
		echo "  • The subject cannot be empty"
		echo "  • Max header length is 100 characters"
		echo ""
		echo "Examples:"
		echo "  feat(api1): add search endpoint"
		echo "  fix(db): wrong transaction isolation"
		echo "  remove(core): deprecated feature cleanup"
		echo "  feat(gpt5): add wonderful messages to husky"
		echo ""
		echo "➡️  See rules: https://www.conventionalcommits.org/"
		echo ""
	} >&2
}

block_direct_commit() {

	local MSG="$1"
	local BRANCH="$(git rev-parse --abbrev-ref HEAD)"

	increment_logs "block_direct_commit Branch: $BRANCH | MSG: $MSG"

	# ----- 1. Only block develop and main -----
	if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "develop" ]; then

		# ---- 2. ONLY allow automatic commits ----

		# release: X.Y.Z
		echo "$MSG" | grep -Eq '^release: [0-9]+\.[0-9]+\.[0-9]+$' && return 0

		# hotfix: X.Y.Z
		echo "$MSG" | grep -Eq '^hotfix: [0-9]+\.[0-9]+\.[0-9]+$' && return 0

		# Version bump to X.Y.Z
		echo "$MSG" | grep -Eq '^Version bump to [0-9]+\.[0-9]+\.[0-9]+$' && return 0

		# Merge tag 'X.Y.Z' into develop
		echo "$MSG" | grep -Eq "^Merge tag ['\"]?[0-9]+\.[0-9]+\.[0-9]+['\"]? into develop$" && return 0

		# Merge branch ... into ... (accepts any)
		echo "$MSG" | grep -Eq "^Merge branch .+ into .+$" && return 0

		# ---- 3. Everything else = BLOCKED ----
		increment_logs "block_direct_commit BLOCKED on $BRANCH | MSG: $MSG"
		echo "❌ Commit blocked: direct commits to $BRANCH are not allowed"
		echo "→ Commit only on feature/*, hotfix/*, release/*"
		return 1
	fi

	# ----- 4. Allowed branches pass -----
	return 0

}

commit_is_internal_allowed() {
	local MSG="$1"

	# Any commit containing "Merge" is automatically allowed
	echo "$MSG" | grep -q "Merge" && return 0

	#  Merge tag from GitFlow finish
	echo "$MSG" | grep -q "Merge tag '" && return 0

	# Merge branch
	echo "$MSG" | grep -qE '^Merge branch .+' && return 0

	#  Version bump
	echo "$MSG" | grep -qE '^Version bump to [0-9]+\.[0-9]+\.[0-9]+$' && return 0

	#  Metadata internal commits
	echo "$MSG" | grep -qE '^chore: create metadata [0-9]+\.[0-9]+\.[0-9]+$' && return 0

	# Release / Hotfix auto commits
	echo "$MSG" | grep -qE '^(release|hotfix): [0-9]+\.[0-9]+\.[0-9]+\b' && return 0

	# Changelog commits
	echo "$MSG" | grep -qi "changelog" && return 0

	return 1
}

commitmsg_guard() {
	local COMMIT_EDITMSG="$1"

	# 1. If internal commit → bypass
	if commit_is_internal_allowed "$COMMIT_EDITMSG"; then
		echo "[commit-msg Bypass] Internal commit allowed → $COMMIT_EDITMSG" >>"$LOG_FILE"
		return 0
	fi

	# 2. If commit contains CHANGELOG.md → bypass
	if git diff --cached --name-only | grep -q "CHANGELOG.md"; then
		echo "[commit-msg Bypass] Contains CHANGELOG.md → allowed" >>"$LOG_FILE"
		return 0
	fi

	# 3. Otherwise → commitlint validation
	if ! ./node_modules/.bin/commitlint --edit "$COMMIT_EDITMSG_FILE" >/dev/null 2>&1; then
		echo "[commit-msg ERROR] Commitlint failed → commit rejected" >>"$LOG_FILE"
		commitlint_error "$COMMIT_EDITMSG"
		return 1
	fi

	return 0
}

validate_commit_type() {
	local MSG="$1"
	local ALLOWED_TYPES="$2" # space separated: "fix feat chore"

	# Internal commits bypass
	commit_is_internal_allowed "$MSG" && return 0

	local TYPE
	TYPE=$(printf "%s" "$MSG" | sed -nE 's/^([a-zA-Z0-9]+)(\(.+\))?:.*/\1/p')

	# If no type extracted → reject
	if [ -z "$TYPE" ]; then
		commitlint_error "$MSG"
		return 1
	fi

	# Check if TYPE is inside allowed list
	for ALLOWED in $ALLOWED_TYPES; do
		if [ "$TYPE" = "$ALLOWED" ]; then
			return 0 # OK
		fi
	done

	# Not allowed → reject
	{
		echo "❌ Commit rejected: type \"$TYPE\" is not allowed on this branch."
		echo ""
		echo "Your input message:"
		echo "  $MSG"
		echo ""
		echo "Allowed types:"
		for A in $ALLOWED_TYPES; do
			echo "  • $A"
		done
		echo ""
	} >&2

	return 1
}
