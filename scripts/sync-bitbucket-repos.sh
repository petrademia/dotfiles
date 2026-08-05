#!/usr/bin/env bash
set -e

WORKSPACE="${WORKSPACE:-Amartha}"

# True when the repo has no commits yet (unborn branch / empty clone).
# Never call bare `git rev-parse HEAD` here - it prints a fatal on empty repos.
has_commits() {
    git -C "$1" rev-parse --verify --quiet HEAD >/dev/null 2>&1
}

# Resolve the remote default branch without assuming a local HEAD exists
# (empty Bitbucket repos / unfinished clones have no HEAD).
default_branch() {
    local dir="$1"
    local branch=""

    branch=$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^refs/remotes/origin/@@') || true

    if [ -z "$branch" ]; then
        git -C "$dir" remote set-head origin -a &>/dev/null || true
        branch=$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null \
            | sed 's@^refs/remotes/origin/@@') || true
    fi

    if [ -z "$branch" ]; then
        branch=$(git -C "$dir" branch -r --format='%(refname:short)' 2>/dev/null \
            | sed -n 's|^origin/||p' \
            | grep -vx 'HEAD' \
            | head -n1) || true
    fi

    # Only touch local HEAD when the repo actually has commits.
    if [ -z "$branch" ] && has_commits "$dir"; then
        branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || true
        [ "$branch" = "HEAD" ] && branch=""
    fi

    printf '%s' "$branch"
}

# Get credentials from 1Password or env var
if [ -z "$AUTH_CREDS" ]; then
    if command -v op >/dev/null 2>&1; then
        BITBUCKET_USER=$(op read "op://Personal/Amartha Bitbucket PR Review/username" 2>/dev/null)
        BITBUCKET_PASS=$(op read "op://Personal/Amartha Bitbucket PR Review/credential" 2>/dev/null)
        AUTH_CREDS="${BITBUCKET_USER}:${BITBUCKET_PASS}"
        if [ -z "$BITBUCKET_USER" ] || [ -z "$BITBUCKET_PASS" ]; then
            echo "Could not read Bitbucket credentials from 1Password."
            echo "Create item named 'Amartha Bitbucket PR Review' in Personal vault with username and credential fields"
            exit 1
        fi
    else
        echo "1Password CLI not found. Install op or export AUTH_CREDS."
        exit 1
    fi
fi

echo "Fetching repositories from Bitbucket workspace: $WORKSPACE"

URL="https://api.bitbucket.org/2.0/repositories/${WORKSPACE}?sort=-updated_on&pagelen=100"
PAGE=1

while [ -n "$URL" ]; do
    echo "Fetching page $PAGE..."

    RESPONSE_FILE=$(mktemp)
    curl -s -u "$AUTH_CREDS" "$URL" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))" > "$RESPONSE_FILE"

    jq -c '.values[]' < "$RESPONSE_FILE" | while read -r repo; do
        [ -z "$repo" ] || [ "$repo" = "null" ] && continue

        PROJECT_NAME=$(jq -r '.project.name // empty' <<< "$repo")
        REPO_NAME=$(jq -r '.name // empty' <<< "$repo")
        SSH_CLONE_URL=$(jq -r '.links.clone[] | select(.name=="ssh") | .href // empty' <<< "$repo")

        [ -z "$PROJECT_NAME" ] || [ -z "$REPO_NAME" ] || [ -z "$SSH_CLONE_URL" ] && continue

        # PascalCase conversion
        CLEAN_PROJECT_NAME=$(echo "$PROJECT_NAME" | sed 's/[-_\/]/ /g' | awk '{
            for(i=1;i<=NF;i++) $i = toupper(substr($i,1,1)) substr($i,2)
        } 1' | tr -d ' ')

        TARGET_DIR="${CLEAN_PROJECT_NAME}Projects"
        [ ! -d "$TARGET_DIR" ] && echo "Creating $TARGET_DIR" && mkdir -p "$TARGET_DIR"

        LOCAL_PATH="$TARGET_DIR/$REPO_NAME"

        if [ ! -d "$LOCAL_PATH" ]; then
            echo "Cloning [$PROJECT_NAME] -> $LOCAL_PATH"
            if git clone "$SSH_CLONE_URL" "$LOCAL_PATH"; then
                (cd "$LOCAL_PATH" && graphify . --backend claude --no-docs --no-viz &>/dev/null &)
            else
                echo "  Clone failed (empty remote or auth/network error)"
            fi
        else
            echo "Syncing [$PROJECT_NAME] -> $REPO_NAME"
            if ! git -C "$LOCAL_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                echo "  Skipping: not a git repo"
            elif ! git -C "$LOCAL_PATH" fetch origin --prune &>/dev/null; then
                echo "  Fetch failed"
            else
                DEFAULT_BRANCH=$(default_branch "$LOCAL_PATH")
                if [ -z "$DEFAULT_BRANCH" ]; then
                    echo "  Skipping: empty repo (no remote/default branch yet)"
                elif ! git -C "$LOCAL_PATH" show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
                    echo "  Skipping: origin/$DEFAULT_BRANCH missing after fetch"
                else
                    CURRENT=$(git -C "$LOCAL_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                    UPDATED=0
                    if [ "$CURRENT" = "$DEFAULT_BRANCH" ]; then
                        # Cannot `branch -f` the checked-out branch; ff-merge instead.
                        if git -C "$LOCAL_PATH" merge --ff-only "origin/$DEFAULT_BRANCH" &>/dev/null; then
                            UPDATED=1
                        fi
                    elif git -C "$LOCAL_PATH" branch -f "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" &>/dev/null; then
                        UPDATED=1
                    fi

                    if [ "$UPDATED" -eq 1 ]; then
                        echo "  Fast-forwarded $DEFAULT_BRANCH"
                        if has_commits "$LOCAL_PATH"; then
                            (cd "$LOCAL_PATH" && graphify . --backend claude --no-docs --no-viz &>/dev/null &)
                        fi
                    else
                        echo "  Could not update local $DEFAULT_BRANCH (dirty tree or non-ff history?)"
                    fi
                fi
            fi
        fi
        echo "------------------------------------------------"
    done

    # Get next page URL
    URL=$(jq -r '.next // empty' < "$RESPONSE_FILE")
    PAGE=$((PAGE + 1))
    rm -f "$RESPONSE_FILE"
done

echo "Sync complete."
