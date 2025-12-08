#!/usr/bin/env sh

get_range_for_version() {
	local VERSION="$1"
	local VERSION_CLEAN
	VERSION_CLEAN=$(printf "%s" "$VERSION" | sed 's/^v//')

	# list of valid tags
	local TAGS
	TAGS=$(git tag)

	# clean and sort semver tags
	local MATCHING=""
	while IFS= read -r t; do
		case "$t" in
		[0-9]*.[0-9]*.[0-9]*)
			if [ "${t#v}" = "$VERSION_CLEAN" ] || [ "$t" = "$VERSION_CLEAN" ]; then
				MATCHING="$t"
			fi
			;;
		esac
	done <<EOF
$TAGS
EOF

	# get the first commit
	local FIRST
	FIRST=$(git rev-list --max-parents=0 HEAD | tail -n1)

	# if exact tag found → detect the previous one
	if [ -n "$MATCHING" ]; then
		local PREV=""
		# search for the previous semver tag exactly like the script
		while IFS= read -r t; do
			case "$t" in
			[0-9]*.[0-9]*.[0-9]*)
				if dpkg --compare-versions "${t#v}" lt "${VERSION_CLEAN}"; then
					PREV="$t"
				fi
				;;
			esac
		done <<EOF
$TAGS
EOF

		if [ -n "$PREV" ]; then
			printf "%s..%s" "$PREV" "$MATCHING"
		else
			printf "%s" "$MATCHING"
		fi
		return
	fi

	local PREV2=""
	while IFS= read -r t; do
		case "$t" in
		[0-9]*.[0-9]*.[0-9]*)
			if dpkg --compare-versions "${t#v}" lt "${VERSION_CLEAN}"; then
				PREV2="$t"
			fi
			;;
		esac
	done <<EOF
$TAGS
EOF

	if [ -n "$PREV2" ]; then
		printf "%s..HEAD" "$PREV2"
	else
		printf "%s..HEAD" "$FIRST"
	fi
}

make_changelog_json() {

	FN_RETURN=1

	local VERSION=""
	local FORCE=""

	# $1 can be either the version or a flag
	case "$1" in
	-f | -F | [fF][oO][rR][cC][eE])
		FORCE="force"
		VERSION="$2"
		;;
	*)
		VERSION="$1"
		FORCE="$2"
		;;
	esac

	# block if empty
	if [ -z "$VERSION" ]; then
		increment_logs "make_changelog BLOCKED: missing version"
		return 0
	fi

	# block if not strict SemVer X.Y.Z
	if ! printf "%s" "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
		increment_logs "make_changelog BLOCKED: invalid semver ($VERSION)"
		return 0
	fi

	local RANGE=$(get_range_for_version "$VERSION")
	local COMMITS=$(git log $RANGE --pretty=format:%s)
	local RELEVANT=$(printf "%s\n" "$COMMITS" | grep -E '^(feat|fix|docs|revert|remove)(\(|:)' || true)

	if printf '%s' "$FORCE" | grep -qiE '^-f$|^force$' || [ -n "$RELEVANT" ]; then
		increment_logs "make_changelog OK with $VERSION"
		node .husky/libs/update-changelog-json.js "$VERSION" "$PATH_CHANGELOG_JSON" || true
	fi

	if ! git diff --quiet -- "$PATH_CHANGELOG_JSON"; then
		FN_RETURN=0
	fi
}

make_changelog_markdown() {
	if [ -f "$PATH_CHANGELOG_JSON" ]; then
		node .husky/libs/json-to-changelog.js "$PATH_CHANGELOG_JSON" CHANGELOG.md || true

		if git status --porcelain "$PATH_CHANGELOG_JSON" CHANGELOG.md |
			grep -qE '^[?][?] |^ M |^M  |^A  '; then
			git add -f "$PATH_CHANGELOG_JSON" CHANGELOG.md || true
			FN_RETURN=0 # ok
		else
			FN_RETURN=2 # no staging
		fi
	else
		FN_RETURN=1 # $PATH_CHANGELOG_JSON missing
	fi

	increment_logs "make_changelog_markdown with code $FN_RETURN"
}
