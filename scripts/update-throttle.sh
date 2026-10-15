#!/usr/bin/env bash
# Lets setup skip update checks that ran recently. Each check has a name and a timestamp file.
#
#   update-throttle.sh due <name>    exit 0 when the check should run; exit 1 when it ran recently and
#                                    print how long ago, for the skip message
#   update-throttle.sh mark <name>   record that the check just succeeded (call it only on success, so a
#                                    failed check is retried on the next run)
#
# SETUP_UPDATE_INTERVAL_HOURS  hours between runs of a check (default 12; 0 runs every check every time)
# SETUP_FORCE=1                run every check regardless of the interval
# SETUP_STATE_DIR              where the timestamps live (default ~/.local/state/dotfiles-setup)
set -uo pipefail

state_dir=${SETUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-setup}
interval_hours=${SETUP_UPDATE_INTERVAL_HOURS:-12}

usage() { echo "usage: ${0##*/} due|mark <name>" >&2; exit 2; }
[ $# -eq 2 ] || usage
action=$1
name=$2
case "$name" in ''|*[!A-Za-z0-9._-]*) echo "${0##*/}: invalid name '$name'" >&2; exit 2 ;; esac
case "$interval_hours" in ''|*[!0-9]*) interval_hours=12 ;; esac
file="$state_dir/last-$name"

case "$action" in
  due)
    [ "${SETUP_FORCE:-0}" = 1 ] && exit 0
    [ "$interval_hours" -gt 0 ] || exit 0
    [ -r "$file" ] || exit 0
    last=$(tr -d '[:space:]' < "$file" 2>/dev/null || true)
    case "$last" in ''|*[!0-9]*) exit 0 ;; esac
    now=$(date +%s)
    age=$((now - last))
    # A timestamp in the future (clock change) or an expired one means the check is due.
    [ "$age" -ge 0 ] || exit 0
    [ "$age" -lt $((interval_hours * 3600)) ] || exit 0
    printf '%dh %dm ago\n' $((age / 3600)) $((age % 3600 / 60))
    exit 1
    ;;
  mark)
    mkdir -p "$state_dir" || exit 1
    tmp=$(mktemp "$state_dir/.last-$name.XXXXXX") || exit 1
    date +%s > "$tmp" && mv "$tmp" "$file"
    ;;
  *) usage ;;
esac
