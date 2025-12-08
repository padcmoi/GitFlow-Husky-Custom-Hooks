#!/usr/bin/env sh

env() {
	local SOURCE_FOLDER=".husky/meta"

	mkdir -p "$SOURCE_FOLDER"

	PATH_CHANGELOG_JSON="$SOURCE_FOLDER/.changelog.json"
	PATH_GITFLOW_TAG_VERSION="$SOURCE_FOLDER/.gitflow_tag_version"
	PATH_GITFLOW_TYPE="$SOURCE_FOLDER/.gitflow_branch_type"
	PATH_GITFLOW_START_HASH="$SOURCE_FOLDER/.gitflow_start_hash_squash"

	PATH_NP_GITFLOW_CURRENT_TAG=".git/GITFLOW_CURRENT_TAG"
	PATH_NP_GITFLOW_TRIGGER_MERGE_MAIN_TO_DEVELOP=".git/GITFLOW_TRIGGER_MERGE_MAIN_TO_DEVELOP"

}

common_libs() {
	env

	# Shared metadata to export
	GITFLOW_VERSION=$(cat "$PATH_GITFLOW_TAG_VERSION" 2>/dev/null || echo "")
	GITFLOW_TYPE=$(cat "$PATH_GITFLOW_TYPE" 2>/dev/null || echo "chore")
	GITFLOW_START_HASH=$(cat "$PATH_GITFLOW_START_HASH" 2>/dev/null || echo "")
	CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	CURRENT_HASH=$(git rev-parse HEAD)
	CURRENT_COMMIT_MSG="$(git show -s --no-show-signature --pretty=format:%s HEAD 2>/dev/null || true)"
	LOG_FILE=".husky/logs/husky-$(basename "$0").$(date '+%Y-%m-%d').log"
	LAST_COMMIT_MSG=""
	LAST_TAG=""

	if [ -f .git/MERGE_HEAD ]; then
		MERGE_REF=$(cat .git/MERGE_HEAD)
		LAST_COMMIT_MSG=$(git log -1 --format="%s" "$MERGE_REF")
		LAST_TAG=$(git describe --tags --abbrev=0 "$MERGE_REF" 2>/dev/null || echo 'No tag found')
	else
		LAST_COMMIT_MSG=$(git log -1 --format="%s")
		LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo 'No tag found')
	fi

	# Exec fn
	log_sequence

	apply_gitflow_config

}

auto_push() {
	# Publish branch if no upstream
	if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
		git push -u origin "$CURRENT_BRANCH" || true
	fi

	# Push only if local commits exist
	if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 && [ -n "$(git log @{u}..HEAD 2>/dev/null)" ]; then
		git push -f || true
	fi

	# # Push tags
	# git push origin --tags || true

}

increment_logs() {
	local scriptname logfile

	scriptname="$(basename "$0")"
	logfile=".husky/logs/__${scriptname}.$(date '+%Y-%m-%d').log"

	mkdir -p .husky/logs

	echo "$1" >>"$logfile"
}

log_sequence() {

	mkdir -p .husky/logs

	purge_old_husky_logs ".husky/logs"

	tags=$(git tag --sort=-creatordate)

	latest_tag=$(echo "$tags" | head -n1)
	prev_tag=$(echo "$tags" | sed -n '2p')

	echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') - \"$(basename "$0")\" | $LAST_COMMIT_MSG | $CURRENT_BRANCH" >>".husky/logs/_sequence.$(date '+%Y-%m-%d').log"

	{
		echo "------------------------------"
		echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') "
		echo "Current:" :
		echo "- Hook      	: $(basename "$0")"
		echo "- User      	: $(git config user.name) <$(git config user.email)>"
		echo "- commit 			: $LAST_COMMIT_MSG"
		echo "- branch 			: $CURRENT_BRANCH"
		echo "- Tag    			: $LAST_TAG"
		echo "------------------------------"
	} >>"$LOG_FILE"

}

purge_old_husky_logs() {
	log_dir="$1"
	now_ts="$(date +%s)"
	max_age_days=7
	max_age_seconds=$((max_age_days * 86400))

	for file in "$log_dir"/*.log; do
		[ -e "$file" ] || continue

		filename="$(basename -- "$file")"

		# Extract date YYYY-MM-DD
		log_date="$(echo "$filename" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
		[ -z "$log_date" ] && continue

		# Convert YYYY-MM-DD → timestamp
		file_ts="$(date -d "$log_date" +%s 2>/dev/null)" || continue

		age_seconds=$((now_ts - file_ts))

		if [ "$age_seconds" -gt "$max_age_seconds" ]; then
			echo "Suppression ( > 7 jours ) : $file"
			rm -f -- "$file"
		fi
	done
}

apply_gitflow_config() {
	local TYPE=$(cat "$PATH_GITFLOW_TYPE" 2>/dev/null || echo "")

	# If GitFlow is NOT configured THEN initialize
	if ! git config --get gitflow.branch.master >/dev/null; then

		increment_logs "[GITFLOW] Forced initialization…"

		# git config gitflow.feature.enabled true
		# git config gitflow.bugfix.enabled true
		# git config gitflow.release.enabled true
		# git config gitflow.hotfix.enabled true
		# git config gitflow.support.enabled true

		git config gitflow.branch.master "main"
		git config gitflow.branch.develop "develop"
		git config gitflow.prefix.feature "feature/"
		git config gitflow.prefix.bugfix "bugfix/"
		git config gitflow.prefix.release "release/"
		git config gitflow.prefix.hotfix "hotfix/"
		git config gitflow.prefix.support "support/"
		git config gitflow.prefix.versiontag ""
		git config gitflow.path.hooks ".husky/_"

		git flow init -f -d || true

		increment_logs "[GITFLOW] OK"
	fi

	# Always force these parameters to be applied
	git config --global gitflow.feature.base develop
	git config --global gitflow.bugfix.base develop
	git config --global gitflow.release.base develop
	git config --global gitflow.hotfix.base main
	git config gitflow.feature.base develop
	git config gitflow.bugfix.base develop
	git config gitflow.release.base develop
	git config gitflow.hotfix.base main

	# Configure GitFlow finish behavior for release/hotfix:
	# disables interactive steps, prevents automatic merges,
	# controls push actions, tag handling, and squash strategy.
	if [ "$TYPE" = "hotfix" ] || [ "$TYPE" = "release" ]; then
		git config pull.rebase false || true

		git config gitflow.$TYPE.finish.fetch false || true
		git config gitflow.$TYPE.finish.push false || true
		git config gitflow.$TYPE.finish.keep false || true
		git config gitflow.$TYPE.finish.keepremote false || true
		git config gitflow.$TYPE.finish.keeplocal false || true
		git config gitflow.$TYPE.finish.notag false || true
		git config gitflow.$TYPE.finish.nobackmerge false || true
		git config gitflow.$TYPE.finish.squash true || true

		git config gitflow.$TYPE.finish.pushproduction true || true
		git config gitflow.$TYPE.finish.pushdevelop true || true
		git config gitflow.$TYPE.finish.pushtag true || true
		git config gitflow.$TYPE.finish.ff-master false || true
		git config gitflow.$TYPE.finish.nodevelopmerge true || true
	fi
}

sync_main_and_develop() {
	local CURRENT
	CURRENT=$(git rev-parse --abbrev-ref HEAD)

	increment_logs "merges the 2 branches at initialization"

	case "$CURRENT" in
	develop)
		git checkout main
		git reset --hard origin/develop
		git push --force-with-lease
		;;
	main)
		git checkout develop
		git reset --hard origin/main
		git push --force-with-lease
		;;
	*) ;;
	esac
}
