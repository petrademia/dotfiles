#!/usr/bin/env bash
# Updates an installed Hermes Agent with its own updater. Used by setup/macos.sh and setup/wsl.sh.
#
# Exit status:
#   0   already current, or the update left the version unchanged
#   10  updated
#   20  skipped: the install has local changes or commits, which an update could disturb
#   1   the check or the update failed
#
# HERMES_CHANNEL (default stable) is passed as --channel for this run only. It does not rewrite the
# channel stored in Hermes's config; use HERMES_CHANNEL=main to follow the branch tip.
set -uo pipefail

channel=${HERMES_CHANNEL:-stable}

if ! hermes_cmd=$(command -v hermes); then
  echo "Hermes Agent is not installed" >&2
  exit 1
fi

info=$("$hermes_cmd" --version 2>/dev/null || true)
before=$(printf '%s\n' "$info" | sed -n '1p')
dir=$(printf '%s\n' "$info" | sed -n 's/^Install directory: //p' | sed -n '1p')

worktree=""
local_commits=""
if [ -n "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  worktree=$(git -C "$dir" status --porcelain --untracked-files=all \
    -- . ':(exclude).install_method' 2>/dev/null || echo "unavailable")
  if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    ahead=$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null \
      | awk '{ print $2 }')
    [ "$ahead" = "0" ] || local_commits=1
  elif [ -z "$(git -C "$dir" tag --points-at HEAD 2>/dev/null)" ] \
    && [ -z "$(git -C "$dir" branch -r --contains HEAD 2>/dev/null)" ]; then
    # No upstream branch: the stable channel checks out a release detached. That holds no local
    # commits when HEAD is a tagged release or is already on a remote branch; anything else is local.
    local_commits=1
  fi
fi
if [ -n "$worktree" ] || [ -n "$local_commits" ]; then
  echo "Warning: Hermes Agent has local changes or commits; update skipped to preserve them" >&2
  exit 20
fi

if ! check=$("$hermes_cmd" update --check --channel "$channel"); then
  printf '%s\n' "$check"
  echo "Warning: Hermes Agent update check failed" >&2
  exit 1
fi
if printf '%s\n' "$check" | grep -Eq '^✓ (Already up to date\.|Up to date with the latest release \()'; then
  echo "[-] Hermes Agent is current. Skipping..."
  exit 0
fi

# Read-only: shows running services and how an update restarts them.
"$hermes_cmd" update --plan --channel "$channel" || true

# --yes keeps setup from stopping at a prompt. It accepts config migrations, so Hermes's own
# pre-update backup setting (updates.pre_update_backup) still applies; it is not forced here because a
# full backup zips the whole Hermes home, which is several GB.
if ! "$hermes_cmd" update --yes --channel "$channel"; then
  echo "Warning: Hermes Agent update failed" >&2
  exit 1
fi

after=$("$hermes_cmd" --version 2>/dev/null | sed -n '1p' || true)
if [ -z "$before" ] || [ -z "$after" ]; then
  echo "Warning: could not verify Hermes Agent version" >&2
  exit 1
fi
[ "$before" = "$after" ] && exit 0
exit 10
