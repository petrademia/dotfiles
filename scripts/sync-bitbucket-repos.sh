#!/usr/bin/env bash
set -e

WORKSPACE="${WORKSPACE:-Amartha}"

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
            fi
        else
            echo "Syncing [$PROJECT_NAME] -> $REPO_NAME"
            if (cd "$LOCAL_PATH" && git fetch origin &>/dev/null); then
                DEFAULT_BRANCH=$(cd "$LOCAL_PATH" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
                [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=$(cd "$LOCAL_PATH" && git rev-parse --abbrev-ref HEAD)
                (cd "$LOCAL_PATH" && git branch -f "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" &>/dev/null) && \
                    echo "  Fast-forwarded $DEFAULT_BRANCH" && \
                    (cd "$LOCAL_PATH" && graphify . --backend claude --no-docs --no-viz &>/dev/null &)
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
