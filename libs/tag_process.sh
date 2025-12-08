#!/usr/bin/env sh

# BASE_DIR="$(dirname "$(realpath "$0")")/libs"
# . "$BASE_DIR/changelog.sh"

check_init_inital_release() {
	local INITIAL_TAG="0.1.0"

	## Checks if there is at least one remote tag, otherwise initializes tag INITIAL_TAG
	if [ "$(git ls-remote --tags origin | grep 'refs/tags/' | wc -l)" -eq 0 ]; then
		sed -i "s/\"version\": *\"[0-9]\+\.[0-9]\+\.[0-9]\+\"/\"version\": \"$INITIAL_TAG\"/" package.json || true

		make_changelog_json -f "$INITIAL_TAG"
		make_changelog_markdown

		git add -f package.json || true
		git commit -m "release: $INITIAL_TAG" --no-verify || true
		git tag -fa "$INITIAL_TAG" -m "release: $INITIAL_TAG" || true
		git push -f origin "$INITIAL_TAG" || true
		git push -f --set-upstream origin "$(git rev-parse --abbrev-ref HEAD)" || true

		sync_main_and_develop

	fi
}

gitflow_create_metadata() {
	FN_STATUS=1

	# Skip if all metadata files already exist
	if [ -f "$PATH_GITFLOW_TYPE" ] && [ -f "$PATH_GITFLOW_TAG_VERSION" ] && [ -f "$PATH_GITFLOW_START_HASH" ]; then
		increment_logs "[SKIP] Gitflow files exist !"
		return 0
	fi

	local VERSION="$1"
	local TYPE
	local GITFLOW_START_HASH

	# Check if the version is in semantic format X.Y.Z
	if ! printf '%s\n' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
		increment_logs "[ERROR] Invalid semantic version ($VERSION) → expected X.Y.Z"
		exit 1
	fi

	# Abort if tag already exists
	if git rev-parse "refs/tags/$VERSION" >/dev/null 2>&1; then
		increment_logs "[ERROR] Tag $VERSION already exists → aborting"
		git checkout main
		exit 0
	fi

	GITFLOW_START_HASH=$(git rev-parse HEAD)

	# Detect TYPE (release/hotfix)
	case "$CURRENT_BRANCH" in
	release/*) TYPE="release" ;;
	hotfix/*) TYPE="hotfix" ;;
	*)
		increment_logs "[SKIP] Unknown branch type ($CURRENT_BRANCH) → TYPE not detected"
		return
		;;
	esac

	# Log metadata (with your increment_logs)
	increment_logs "[INFO] Branch=$CURRENT_BRANCH"
	increment_logs "[INFO] TYPE=$TYPE"
	increment_logs "[INFO] VERSION=$VERSION"
	increment_logs "[INFO] START_HASH=$GITFLOW_START_HASH"

	# Persist metadata files
	echo "$TYPE" >"$PATH_GITFLOW_TYPE" || true
	echo "$VERSION" >"$PATH_GITFLOW_TAG_VERSION" || true
	echo "$GITFLOW_START_HASH" >"$PATH_GITFLOW_START_HASH" || true

	git add -f "$PATH_GITFLOW_TYPE" "$PATH_GITFLOW_TAG_VERSION" "$PATH_GITFLOW_START_HASH" || true

	make_changelog_json -f "$VERSION"
	make_changelog_markdown

	git commit -m "chore: create metadata $VERSION" --no-verify || true

	FN_STATUS=0

}

gitflow_init_metadata() {

	local CURRENT_BRANCH="$1"

	if echo "$CURRENT_BRANCH" | grep -qE '^(release|hotfix)/[0-9]+\.[0-9]+\.[0-9]+$'; then
		local EXPORTED_TYPE=$(printf "%s" "$CURRENT_BRANCH" | cut -d'/' -f1)
		local EXPORTED_VERSION=$(printf "%s" "$CURRENT_BRANCH" | cut -d'/' -f2)
		local SCORE=0

		{ [ ! -f "$PATH_GITFLOW_TYPE" ] || [ "$(cat "$PATH_GITFLOW_TYPE" 2>/dev/null)" != "$EXPORTED_TYPE" ]; } && SCORE=$((SCORE + 1))
		{ [ ! -f "$PATH_GITFLOW_TAG_VERSION" ] || [ "$(cat "$PATH_GITFLOW_TAG_VERSION" 2>/dev/null)" != "$EXPORTED_VERSION" ]; } && SCORE=$((SCORE + 1))
		{ [ ! -f "$PATH_GITFLOW_START_HASH" ]; } && SCORE=$((SCORE + 1))

		if [ "$SCORE" -gt 0 ]; then
			increment_logs "[post checkout] metadata mismatch (score=$SCORE) for $CURRENT_BRANCH"

			if git rev-parse "refs/tags/$EXPORTED_VERSION" >/dev/null 2>&1; then
				increment_logs "[post checkout] tag $EXPORTED_VERSION already exists → skip gitflow_create_metadata"
				# TODO redirect to main
			else
				gitflow_create_metadata "$EXPORTED_VERSION"
			fi
		fi
	fi
}

gitflow_attempt_ffmerge_and_prune_branch() {
	local LAST_COMMIT_MSG="$1"

	if [ -f "$PATH_NP_GITFLOW_TRIGGER_MERGE_MAIN_TO_DEVELOP" ]; then
		local GITFLOW_FULL_BRANCH=$(cat "$PATH_NP_GITFLOW_TRIGGER_MERGE_MAIN_TO_DEVELOP" 2>/dev/null || echo "")

		if echo "$LAST_COMMIT_MSG" | grep -Eq '^(release|hotfix): [0-9]+\.[0-9]+\.[0-9]+$' && [ "$CURRENT_BRANCH" = "main" ]; then

			# Check real divergence
			set -- $(git rev-list --left-right --count main...develop)
			MAIN_ONLY=$1
			DEVELOP_ONLY=$2

			if [ "$MAIN_ONLY" -gt 0 ] && [ "$DEVELOP_ONLY" -gt 0 ]; then
				# True divergence -> DO NOT TOUCH
				increment_logs "[GITFLOW] Divergence: main=$MAIN_ONLY develop=$DEVELOP_ONLY -> skipping ff-only merge."
			else
				# No real divergence -> ff-only is safe
				git checkout develop && git merge --ff-only main && git checkout main || true
			fi

			rm -f "$PATH_NP_GITFLOW_TRIGGER_MERGE_MAIN_TO_DEVELOP" || true

			# Force the deletion of hotfix branch (gitflow issue)
			git branch -D "$GITFLOW_FULL_BRANCH" || true

		fi
	fi
}

gitflow_finalize_main_merge() {
	local GITFLOW_START_HASH="$1"

	# Require all metadata files
	if [ ! -f "$PATH_GITFLOW_TYPE" ] || [ ! -f "$PATH_GITFLOW_TAG_VERSION" ] || [ ! -f "$PATH_GITFLOW_START_HASH" ]; then
		return 1
	fi

	# Check SHA1 hash
	if echo "$GITFLOW_START_HASH" | grep -Eq '^[0-9a-fA-F]{40}$'; then

		make_changelog_markdown

		rm -f "$PATH_GITFLOW_START_HASH" "$PATH_GITFLOW_TAG_VERSION" "$PATH_GITFLOW_TYPE" || true
		git add -f "$PATH_GITFLOW_START_HASH" "$PATH_GITFLOW_TAG_VERSION" "$PATH_GITFLOW_TYPE" || true

		echo "$GITFLOW_TYPE/$GITFLOW_VERSION" >"$PATH_NP_GITFLOW_TRIGGER_MERGE_MAIN_TO_DEVELOP" || true
		echo "$GITFLOW_VERSION" >"$PATH_NP_GITFLOW_CURRENT_TAG" || true

		git commit -m "$GITFLOW_TYPE: $GITFLOW_VERSION" --no-verify || true

	fi
}

gitflow_push_forced_current_tag() {

	local TAG_FILE="$PATH_NP_GITFLOW_CURRENT_TAG"

	[ ! -f "$TAG_FILE" ] && return 0

	local GITFLOW_CURRENT_TAG
	GITFLOW_CURRENT_TAG=$(cat "$TAG_FILE" 2>/dev/null || echo "")

	# Strictly check X.Y.Z
	printf "%s" "$GITFLOW_CURRENT_TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || return 1

	# Check that the tag exists locally
	if [ "x$(git tag -l "$GITFLOW_CURRENT_TAG")" != "x" ]; then
		rm -f "$TAG_FILE" || true
		git push --force origin "$GITFLOW_CURRENT_TAG"
	fi

	return 0
}
