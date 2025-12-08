#!/usr/bin/env sh
set -e

# Script inspired and based on the Gitflow Vscode plugin
# Serhioromano.vscode-gitflow
# https://marketplace.visualstudio.com/items?itemName=Serhioromano.vscode-gitflow
#
# Author: Julien Jean (https://www.linkedin.com/in/julienjean-nice/)
#

#############################################
# Helpers
#############################################

error() {
  echo "❌ $1"
  case "$2" in
  release) usage_release ;;
  hotfix) usage_hotfix ;;
  feature) usage_feature ;;
  bugfix) usage_bugfix ;;
  develop) usage_develop ;;
  *) usage ;;
  esac
  exit 1
}

usage_release() {
  echo ""
  echo "RELEASE:"
  echo "  ./gitflow release start <X.Y.0>    # Start a release (PATCH = 0)"
  echo "  ./gitflow release auto             # Auto: MAJOR.(MINOR+1).0"
  echo "  ./gitflow release finish           # Merge->main, tag, FF->develop"
  echo "  ./gitflow release delete           # Delete current release branch"
  echo "  ./gitflow release rebase           # Rebase release onto develop"
  echo "  ./gitflow release compare          # Compare release/* with main & develop"
  echo ""
  echo "Notes:"
  echo "  - Versions must follow strict SemVer X.Y.Z"
  exit 1
}

usage_hotfix() {
  echo ""
  echo "HOTFIX:"
  echo "  ./gitflow hotfix start <X.Y.Z>     # Start a hotfix (PATCH > 0)"
  echo "  ./gitflow hotfix auto              # Auto: MAJOR.MINOR.(PATCH+1)"
  echo "  ./gitflow hotfix finish            # Merge->main, tag, FF->develop"
  echo "  ./gitflow hotfix delete            # Delete current hotfix branch"
  echo "  ./gitflow hotfix rebase            # Rebase hotfix onto main"
  echo "  ./gitflow hotfix compare           # Compare hotfix/* with main"
  echo ""
  echo "Notes:"
  echo "  - Versions must follow strict SemVer X.Y.Z"
  exit 1
}

usage_feature() {
  echo ""
  echo "FEATURE:"
  echo "  ./gitflow feature start <name>     # Start a feature branch"
  echo "  ./gitflow feature finish           # Merge feature/* into develop"
  echo "  ./gitflow feature delete           # Delete current feature branch"
  echo "  ./gitflow feature rebase           # Rebase feature onto develop"
  echo "  ./gitflow feature compare          # Compare feature/* with develop"
  echo ""
  echo "Notes:"
  echo "  - Branch names are sanitized automatically."
  exit 1
}

usage_bugfix() {
  echo ""
  echo "BUGFIX:"
  echo "  ./gitflow bugfix start <name>      # Start a bugfix branch"
  echo "  ./gitflow bugfix finish            # Merge bugfix/* into develop"
  echo "  ./gitflow bugfix delete            # Delete current bugfix branch"
  echo "  ./gitflow bugfix rebase            # Rebase bugfix onto develop"
  echo "  ./gitflow bugfix compare           # Compare bugfix/* with develop"
  echo ""
  echo "Notes:"
  echo "  - Branch names are sanitized automatically."
  exit 1
}

usage_develop() {
  echo ""
  echo "DEVELOP:"
  echo "  ./gitflow develop                  # Interactive develop menu"
  echo "  ./gitflow develop merge-main       # Merge origin/main → develop"
  echo "  ./gitflow develop restore          # Recreate develop from main"
  echo "  ./gitflow develop compare          # Compare develop with main"
  echo ""
  echo "Notes:"
  echo "  - develop is protected and must never diverge."
  exit 1
}

usage() {
  echo "Usage:"
  echo "  ./gitflow <type> <action> [...args]"
  echo ""

  if [ ! -z "$1" ]; then
    echo "$(usage_release)"
    echo "$(usage_hotfix)"
    echo "$(usage_feature)"
    echo "$(usage_bugfix)"
    echo "$(usage_develop)"
    echo ""

  else

    echo "Types:"
    echo "  release   hotfix   feature   bugfix   develop"
    echo ""
  fi

  echo "Notes:"
  echo "  - 'help' or '?' at any position shows this help."
  echo "  - Versions must follow strict SemVer X.Y.Z"
  echo "  - Branch names for feature/bugfix are sanitized."
  exit 1
}

sanitize_branch() {
  name="$1"

  # lowercase
  name="$(printf "%s" "$name" | tr '[:upper:]' '[:lower:]')"

  # replace spaces & consecutive spaces by underscore
  name="$(printf "%s" "$name" | tr ' ' '_')"

  # remove accents
  name="$(printf "%s" "$name" | iconv -f utf8 -t ascii//translit 2>/dev/null)"

  # allow only a-z0-9_-
  name="$(printf "%s" "$name" | sed 's/[^a-z0-9_-]//g')"

  # collapse multiple underscores
  name="$(printf "%s" "$name" | sed 's/_\+/_/g')"

  # trim underscores at start/end
  name="$(printf "%s" "$name" | sed 's/^_//; s/_$//')"

  printf "%s" "$name"
}

compare_branch() {
  LOCAL="$1"
  REMOTE="$2"

  git fetch origin >/dev/null 2>&1 || true

  AHEAD_BEHIND=$(git rev-list --left-right --count "$LOCAL"...origin/"$REMOTE")
  AHEAD=$(echo "$AHEAD_BEHIND" | awk '{print $1}')
  BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $2}')

  echo ""
  echo "[COMPARE] $LOCAL ↔ origin/$REMOTE"
  echo "  Ahead :  $AHEAD commit(s)"
  echo "  Behind:  $BEHIND commit(s)"

  if [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -eq 0 ]; then
    echo "  → Branches are perfectly aligned."
  elif [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -eq 0 ]; then
    echo "  → $LOCAL is ahead of $REMOTE."
  elif [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -gt 0 ]; then
    echo "  → $LOCAL is behind $REMOTE."
  else
    echo "  → Divergence detected (both ahead & behind)."
  fi
}

#############################################
# Version bump (SED ONLY)
#############################################

bump_version_sed() {
  VERSION="$1"

  # Custom or others to define
  if [ -f ___other_config.json ]; then
    echo "[GITFLOW] bump for ___other_config.json (not implemented)"
  fi

  # NodeJS
  if [ -f package.json ]; then
    # The version field must exist
    if ! grep -q '"version"' package.json; then
      echo "❌ package.json found but no version field"
      return 1
    fi

    # Clean replacement via sed
    sed -i -E \
      "s/\"version\"[[:space:]]*:[[:space:]]*\"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$VERSION\"/" \
      package.json

    echo "[GITFLOW] package.json version bumped to $VERSION"

    # Add files
    git add package.json 2>/dev/null || true
    [ -f package-lock.json ] && git add package-lock.json || true
    [ -f pnpm-lock.yaml ] && git add pnpm-lock.yaml || true
    [ -f yarn.lock ] && git add yarn.lock || true
  fi

  # Commit auto
  if ! git diff --cached --quiet; then
    git commit -m "Version bump to $VERSION" --no-verify || true
  fi
}

#############################################
# PARSE ARGUMENTS
#############################################

TYPE="$1"
ACTION="$2"
VERSION="$3"

[ -z "$TYPE" ] && usage

# Interactive if type only
if [ -z "$ACTION" ] &&
  { [ "$TYPE" = "hotfix" ] || [ "$TYPE" = "release" ] || [ "$TYPE" = "feature" ] || [ "$TYPE" = "bugfix" ] || [ "$TYPE" = "develop" ]; }; then
  ACTION="__interactive"
fi

# TYPES allowed
case "$TYPE" in
release | hotfix | feature | bugfix | develop) ;;
help | ?) clear && usage 1 ;;
*)
  error "Invalid type '$TYPE'. Allowed: release, hotfix, feature, bugfix, develop"
  ;;
esac

# ACTIONS allowed
case "$ACTION" in
start | finish | auto | delete | rebase | merge-main | restore | compare | __interactive) ;;
help | ?)

  case "$TYPE" in
  release) usage_release ;;
  hotfix) usage_hotfix ;;
  feature) usage_feature ;;
  bugfix) usage_bugfix ;;
  develop) usage_develop ;;
  *) clear && usage ;;
  esac
  ;;
*)
  error "Invalid action '$ACTION'. Allowed: start, finish, auto, delete, rebase, merge-main, restore, compare" "$TYPE"
  ;;
esac

#############################################
# RELEASE / HOTFIX AUTO
#############################################

if [ "$ACTION" = "auto" ]; then

  if [ "$TYPE" = "hotfix" ]; then
    LAST_TAG="$(git tag -l | sort -V | tail -n 1)"

    printf "%s" "$LAST_TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
      error "No valid SemVer tag found on repository"

    MAJOR="$(printf "%s" "$LAST_TAG" | cut -d'.' -f1)"
    MINOR="$(printf "%s" "$LAST_TAG" | cut -d'.' -f2)"
    PATCH="$(printf "%s" "$LAST_TAG" | cut -d'.' -f3)"

    PATCH=$((PATCH + 1))
    VERSION="$MAJOR.$MINOR.$PATCH"

    echo "[GITFLOW] Auto hotfix -> $VERSION"
    "$0" hotfix start "$VERSION"
    exit 0
  fi

  if [ "$TYPE" = "release" ]; then
    LAST_TAG="$(git tag -l | sort -V | tail -n 1)"

    printf "%s" "$LAST_TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
      error "No valid SemVer tag found on repository"

    MAJOR="$(printf "%s" "$LAST_TAG" | cut -d'.' -f1)"
    MINOR="$(printf "%s" "$LAST_TAG" | cut -d'.' -f2)"

    # NEXT release = MAJOR.(MINOR+1).0
    MINOR=$((MINOR + 1))
    VERSION="$MAJOR.$MINOR.0"

    echo "[GITFLOW] Auto release -> $VERSION"
    "$0" release start "$VERSION"
    exit 0
  fi

fi

#############################################
# START (release or hotfix)
#############################################

if [ "$ACTION" = "start" ]; then

  if [ "$TYPE" = "release" ] || [ "$TYPE" = "hotfix" ]; then

    # Check Version and SemVer
    [ -z "$VERSION" ] && error "Missing version for '$TYPE start'"
    printf "%s" "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || error "Invalid version '$VERSION' (expected X.Y.Z)"

    MAJOR="$(printf "%s" "$VERSION" | cut -d'.' -f1)"
    MINOR="$(printf "%s" "$VERSION" | cut -d'.' -f2)"
    PATCH="$(printf "%s" "$VERSION" | cut -d'.' -f3)"

    if [ "$TYPE" = "release" ] && [ "$PATCH" -ne 0 ]; then
      error "Invalid version '$VERSION' for release (PATCH must be 0 for releases)"
    fi

    if [ "$TYPE" = "hotfix" ]; then
      # PATCH must not be 0 (already enforced)
      if [ "$PATCH" -eq 0 ]; then
        error "Invalid version '$VERSION' for hotfix (PATCH cannot be 0)"
      fi

      # Check that the MAJOR.MINOR exists in repo tags
      EXISTING_BASE_TAG=$(git tag -l "${MAJOR}.${MINOR}.*" | sort -V | head -n 1)

      if [ -z "$EXISTING_BASE_TAG" ]; then
        error "Invalid hotfix '$VERSION' — base version ${MAJOR}.${MINOR}.X does not exist"
      fi
    fi

    # ---- BEFORE HOOK ----
    echo "[HOOK BEFORE] $TYPE start $VERSION"
    # Place your pre-start actions here
    # ---------------------------------

    echo "[GITFLOW] Starting $TYPE $VERSION"
    git flow "$TYPE" start "$VERSION"

    # Bump version
    bump_version_sed "$VERSION"

    # ---- AFTER HOOK ----
    echo "[HOOK AFTER] $TYPE start $VERSION"
    # Place your post-start actions here
    # ----------------------------------

    echo "[GITFLOW] $TYPE $VERSION successfully started."
    exit 0
  fi

  if [ "$TYPE" = "feature" ] || [ "$TYPE" = "bugfix" ]; then
    [ -z "$VERSION" ] && error "Missing branch name for $TYPE start"

    CLEAN_NAME="$(sanitize_branch "$VERSION")"

    [ -z "$CLEAN_NAME" ] && error "Invalid branch name after sanitize"

    BRANCH="$TYPE/$CLEAN_NAME"

    echo "[GITFLOW] Starting $BRANCH"
    git checkout -b "$BRANCH" develop || error "Failed creating branch"
    git push -u origin "$BRANCH" || true

    echo "[GITFLOW] $BRANCH successfully started."
    exit 0
  fi

fi

#############################################
# AUTO CHECKOUT (called when only TYPE is given)
#############################################

if [ "$ACTION" = "__interactive" ]; then

  # Determine branches
  case "$TYPE" in
  hotfix) BRANCHES=$(git branch -r | grep -E 'origin/hotfix/' | sed 's#origin/##') ;;
  release) BRANCHES=$(git branch -r | grep -E 'origin/release/' | sed 's#origin/##') ;;
  feature) BRANCHES=$(git branch -r | grep -E 'origin/feature/' | sed 's#origin/##') ;;
  bugfix) BRANCHES=$(git branch -r | grep -E 'origin/bugfix/' | sed 's#origin/##') ;;
  develop)
    echo ""
    echo "[GITFLOW] Available develop actions:"
    echo ""
    echo "1) develop             (checkout develop)"
    echo "2) develop merge-main  (merge origin/main → develop)"
    echo "3) develop restore     (delete + recreate develop from main)"
    echo ""
    printf "Your choice (1-3): "
    read choice
    case "$choice" in
    1)
      git checkout develop || error "Cannot checkout develop"
      exit 0
      ;;
    2)
      echo "[GITFLOW] Merging main → develop"
      git checkout develop || error "Cannot checkout develop"
      git fetch origin || true
      git merge origin/main || error "Merge failed"
      git push || error "Push failed"
      exit 0
      ;;
    3)
      echo "⚠️ WARNING: This will DELETE & RECREATE develop identical to main."
      printf "Proceed? (y/N): "
      read ans
      case "$ans" in
      y | Y | yes | YES) ;;
      *) exit 0 ;;
      esac

      git checkout main &&
        git branch -D develop &&
        git push origin --delete develop &&
        git fetch --prune &&
        git checkout -b develop &&
        git push -u origin develop

      echo "[GITFLOW] develop restored from main."
      exit 0
      ;;
    *)
      error "Invalid choice"
      ;;
    esac
    ;;

  *)
    usage
    ;;
  esac

  echo ""
  echo "[GITFLOW] - Available $TYPE branches:"
  echo ""

  i=1
  CHOICES=""

  for b in $BRANCHES; do
    echo "$i) $b"
    CHOICES="$CHOICES $b"
    i=$((i + 1))
  done

  echo "$i) main"
  CHOICES="$CHOICES main"
  i=$((i + 1))

  echo "$i) develop"
  CHOICES="$CHOICES develop"
  COUNT=$i

  echo ""
  printf "Your choice (1-%s): " "$COUNT"
  read choice

  printf "%s" "$choice" | grep -Eq '^[0-9]+$' || error "Invalid selection"
  [ "$choice" -lt 1 ] && error "Invalid selection"
  [ "$choice" -gt "$COUNT" ] && error "Invalid selection"

  SELECTED=$(echo "$CHOICES" | awk -v n="$choice" '{print $n}')

  echo ""
  echo "[GITFLOW] Checkout → $SELECTED"
  git checkout "$SELECTED" || error "Cannot checkout $SELECTED"

  exit 0
fi

#############################################
# COMPARE
#############################################

if [ "$ACTION" = "compare" ]; then

  if [ "$TYPE" = "release" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    case "$CURRENT_BRANCH" in
    release/*) ;;
    *) error "You must be on a release/* branch to use compare." ;;
    esac

    echo "[GITFLOW] Comparing $CURRENT_BRANCH"
    compare_branch "$CURRENT_BRANCH" "main"
    compare_branch "$CURRENT_BRANCH" "develop"
    exit 0
  fi

  if [ "$TYPE" = "hotfix" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    case "$CURRENT_BRANCH" in
    hotfix/*) ;;
    *) error "You must be on a hotfix/* branch to use compare." ;;
    esac

    echo "[GITFLOW] Comparing $CURRENT_BRANCH"
    compare_branch "$CURRENT_BRANCH" "main"
    exit 0
  fi

  if [ "$TYPE" = "feature" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    case "$CURRENT_BRANCH" in
    feature/*) ;;
    *) error "You must be on a feature/* branch to use compare." ;;
    esac

    echo "[GITFLOW] Comparing $CURRENT_BRANCH"
    compare_branch "$CURRENT_BRANCH" "develop"
    exit 0
  fi

  if [ "$TYPE" = "bugfix" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    case "$CURRENT_BRANCH" in
    bugfix/*) ;;
    *) error "You must be on a bugfix/* branch to use compare." ;;
    esac

    echo "[GITFLOW] Comparing $CURRENT_BRANCH"
    compare_branch "$CURRENT_BRANCH" "develop"
    exit 0
  fi

  if [ "$TYPE" = "develop" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    [ "$CURRENT_BRANCH" = "develop" ] || error "You must be on develop to use compare."

    echo "[GITFLOW] Comparing develop"
    compare_branch "develop" "main"
    exit 0
  fi

fi

#############################################
# FINISH (release or hotfix)
#############################################

if [ "$ACTION" = "finish" ]; then

  if [ "$TYPE" = "release" ] || [ "$TYPE" = "hotfix" ]; then

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

    case "$CURRENT_BRANCH" in
    release/*) TYPE="release" ;;
    hotfix/*) TYPE="hotfix" ;;
    *) error "You must be on a release/* or hotfix/* branch to finish. Current: $CURRENT_BRANCH" ;;
    esac

    VERSION="$(printf "%s" "$CURRENT_BRANCH" | cut -d'/' -f2)"
    [ -z "$VERSION" ] && error "Unable to extract version from branch name"

    printf "%s" "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
      error "Invalid version format: $VERSION"

    echo "[GITFLOW] Finishing $TYPE $VERSION"

    # BEFORE MERGING: ensure branch is NOT behind main
    TARGET="main"

    AHEAD_BEHIND=$(git rev-list --left-right --count "$CURRENT_BRANCH"...origin/$TARGET)
    AHEAD=$(echo "$AHEAD_BEHIND" | awk '{print $1}')
    BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $2}')

    if [ "$BEHIND" -gt 0 ]; then
      echo ""
      echo "⚠️  WARNING: Branch '$CURRENT_BRANCH' is BEHIND $TARGET by $BEHIND commits."
      echo "   Finishing now will break the GitFlow process."
      echo "   A merge from '$TARGET' into '$CURRENT_BRANCH' is required."
      echo ""
      printf "Proceed with merge? (y/N): "
      read ans

      case "$ans" in
      y | Y | yes | YES)
        echo "[GITFLOW] Merging $TARGET into $CURRENT_BRANCH..."
        git fetch origin || true
        git merge "origin/$TARGET" || {
          echo "❌ Merge failed — resolve conflicts, then run finish again."
          exit 1
        }
        echo "[GITFLOW] Merge completed."
        ;;
      *)
        echo "[GITFLOW] Finish aborted. Branch is behind $TARGET — merge refused."
        exit 1
        ;;
      esac
    fi

    # 1) main <- squash merge
    git checkout main || error "Checkout main failed"
    git pull --ff-only || error "Pull main failed"
    git merge --squash "$CURRENT_BRANCH" || echo "[GITFLOW] squash merge produced no changes"

    # 1.1) Commit UNIQUEMENT si nécessaire
    if ! git diff --cached --quiet; then
      echo "[GITFLOW] Commit final: $TYPE: $VERSION"
      git commit -m "$TYPE: $VERSION" || error "Failed to commit release on main"
    else
      echo "[GITFLOW] Nothing to commit — skipping commit."
    fi

    # 2) Tag
    git tag -a "$VERSION" -m "Finish $TYPE: $VERSION" || error "Failed to create tag"

    # 3) Push main + tag
    git push origin main || error "Failed pushing main"
    git push origin "$VERSION" || error "Failed pushing tag"

    # 4) develop <- main (FF-only only)
    git checkout develop || error "Checkout develop failed"
    git pull --ff-only || error "Pull develop failed"

    AHEAD="$(git rev-list --left-right --count develop...main | awk '{print $1}')"

    if [ "$AHEAD" -eq 0 ]; then
      git merge --ff-only main || error "FF merge failed"
      git push origin develop || error "Push develop failed"
    else
      echo "[GITFLOW] develop ahead by $AHEAD commits — skipping merge"
    fi

    # 5) Delete release/hotfix branch
    git branch -d "$CURRENT_BRANCH" || true
    git push origin --delete "$CURRENT_BRANCH" || true

    echo "[GITFLOW] $TYPE $VERSION successfully finished."

    exit 0

  fi

  if [ "$TYPE" = "feature" ] || [ "$TYPE" = "bugfix" ]; then

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

    case "$CURRENT_BRANCH" in
    feature/*)
      [ "$TYPE" = "feature" ] || error "Use: ./gitflow feature finish"
      ;;
    bugfix/*)
      [ "$TYPE" = "bugfix" ] || error "Use: ./gitflow bugfix finish"
      ;;
    *)
      error "You must be on a feature/* or bugfix/* branch to finish."
      ;;
    esac

    echo "[GITFLOW] Finishing $CURRENT_BRANCH → develop"

    git fetch origin || true

    BEHIND=$(git rev-list --right-only --count "$CURRENT_BRANCH"...origin/develop)

    if [ "$BEHIND" -gt 0 ]; then
      echo "⚠️  $CURRENT_BRANCH is BEHIND develop by $BEHIND commits."
      printf "Merge develop into branch first? (y/N): "
      read ans
      case "$ans" in
      y | Y | yes | YES)
        git merge origin/develop || {
          echo "❌ Merge failed — resolve conflicts then rerun finish."
          exit 1
        }
        ;;
      *)
        error "Finish aborted."
        ;;
      esac
    fi

    git checkout develop || error "Cannot checkout develop"
    git pull --ff-only || error "Cannot pull develop"

    if git merge --ff-only "$CURRENT_BRANCH" 2>/dev/null; then
      echo "[GITFLOW] Fast-forward merge into develop"
    else
      echo "[GITFLOW] Performing merge commit"
      git merge "$CURRENT_BRANCH" || error "Merge failed"
    fi

    git push origin develop || error "Failed pushing develop"

    # cleanup
    git branch -d "$CURRENT_BRANCH" || true
    git push origin --delete "$CURRENT_BRANCH" || true

    echo "[GITFLOW] $CURRENT_BRANCH successfully finished."
    exit 0
  fi

fi

#############################################
# DEVELOP COMMANDS
#############################################

if [ "$TYPE" = "develop" ]; then

  # develop interactive → checkout develop
  if [ "$ACTION" = "__interactive" ]; then
    echo "[GITFLOW] Checkout develop"
    git checkout develop || error "Cannot checkout develop"
    exit 0
  fi

  # develop merge-main
  if [ "$ACTION" = "merge-main" ]; then
    echo "[GITFLOW] Merging main → develop"
    git checkout develop
    git fetch origin
    git merge origin/main || error "Merge failed"
    git push
    exit 0
  fi

  # develop restore
  if [ "$ACTION" = "restore" ]; then

    echo "⚠️ WARNING: This will DELETE & RECREATE develop identical to main."
    printf "Proceed? (y/N): "
    read ans
    case "$ans" in y | Y | yes | YES) ;; *) exit 0 ;; esac

    git checkout main &&
      git branch -D develop &&
      git push origin --delete develop &&
      git fetch --prune &&
      git checkout -b develop &&
      git push -u origin develop &&
      git checkout main

    echo "[GITFLOW] develop restored from main."
    exit 0
  fi

fi

#############################################
# DELETE (release or hotfix)
#############################################

if [ "$ACTION" = "delete" ]; then

  if [ "$TYPE" = "release" ] || [ "$TYPE" = "hotfix" ]; then

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

    case "$CURRENT_BRANCH" in
    release/*)
      [ "$TYPE" = "release" ] || error "You must use: ./gitflow release delete"
      ;;
    hotfix/*)
      [ "$TYPE" = "hotfix" ] || error "You must use: ./gitflow hotfix delete"
      ;;
    *)
      error "You must be on a release/* or hotfix/* branch to delete it. Current: $CURRENT_BRANCH"
      ;;
    esac

    BRANCH_NAME="$CURRENT_BRANCH"

    echo "[GITFLOW] Deleting branch $BRANCH_NAME"

    # Delete local branch
    git checkout develop 2>/dev/null || git checkout main || true
    git branch -D "$BRANCH_NAME" || true

    # Delete remote branch
    git push origin --delete "$BRANCH_NAME" || true

    echo "[GITFLOW] Branch $BRANCH_NAME deleted."
    exit 0
  fi

  if [ "$TYPE" = "feature" ] || [ "$TYPE" = "bugfix" ]; then

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

    case "$CURRENT_BRANCH" in
    feature/*)
      [ "$TYPE" = "feature" ] || error "Use: ./gitflow feature delete"
      ;;
    bugfix/*)
      [ "$TYPE" = "bugfix" ] || error "Use: ./gitflow bugfix delete"
      ;;
    *)
      error "You must be on a feature/* or bugfix/* branch to delete it. Current: $CURRENT_BRANCH"
      ;;
    esac

    BRANCH_NAME="$CURRENT_BRANCH"

    echo "[GITFLOW] Deleting branch $BRANCH_NAME"

    # Delete local branch
    git checkout develop 2>/dev/null || git checkout main || true
    git branch -D "$BRANCH_NAME" || true

    # Delete remote branch
    git push origin --delete "$BRANCH_NAME" || true

    echo "[GITFLOW] Branch $BRANCH_NAME deleted."
    exit 0
  fi

fi

#############################################
# REBASE (release or hotfix)
#############################################

if [ "$ACTION" = "rebase" ]; then

  if [ "$TYPE" = "release" ] || [ "$TYPE" = "hotfix" ]; then

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

    case "$CURRENT_BRANCH" in
    hotfix/*)
      [ "$TYPE" = "hotfix" ] || error "Use: ./gitflow hotfix rebase"
      TARGET="main"
      ;;
    release/*)
      [ "$TYPE" = "release" ] || error "Use: ./gitflow release rebase"
      TARGET="develop"
      ;;
    *)
      error "You must be on a release/* or hotfix/* branch to rebase. Current: $CURRENT_BRANCH"
      ;;
    esac

    echo "[GITFLOW] You are about to rebase:"
    echo "         Branch:  $CURRENT_BRANCH"
    echo "         Onto:    $TARGET"
    echo ""
    echo "⚠️  WARNING: Rebasing rewrites history and can cause conflicts."
    echo "   Only continue if you fully understand the implications."
    echo ""

    printf "Confirm rebase? (y/N): "
    read ans
    case "$ans" in
    y | Y | yes | YES) ;;
    *)
      echo "[GITFLOW] Rebase cancelled."
      exit 0
      ;;
    esac

    echo "[GITFLOW] Rebasing $CURRENT_BRANCH onto $TARGET"

    git fetch origin || true
    git checkout "$CURRENT_BRANCH" || error "Cannot stay on current branch"
    git rebase "origin/$TARGET" || error "Rebase failed"

    echo "[GITFLOW] Rebase complete."
    exit 0
  fi

  if [ "$TYPE" = "feature" ] || [ "$TYPE" = "bugfix" ]; then

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    case "$CURRENT_BRANCH" in
    feature/* | bugfix/*) ;;
    *) error "You must be on a feature/* or bugfix/* branch to rebase." ;;
    esac

    echo "[GITFLOW] Rebasing $CURRENT_BRANCH onto develop"
    git fetch origin
    git rebase origin/develop || error "Rebase failed"

    echo "[GITFLOW] Rebase complete."
    exit 0
  fi

fi
