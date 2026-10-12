# Interactive convenience. Make/scripts use PATH shims from install.sh
# (~/.local/bin/docker -> bin/docker) because aliases are not inherited.
if command -v podman >/dev/null 2>&1; then
  export PODMAN_COMPOSE_WARNING_LOGS=false
  alias docker='podman'
  alias docker-compose='podman-compose'
fi

# Container VM health. A full Podman VM shows up as a very high load average and as tests that time
# out in code that is fine; the usual cause is Testcontainers left behind (Ryuk, its reaper, cannot
# run under Podman, so nothing removes them).
if command -v podman >/dev/null 2>&1; then
  podman-health() {
    echo "VM memory (MB): $(podman machine ssh 'free -m' 2>/dev/null | awk '/^Mem:/{print "total "$2", used "$3", available "$7}')"
    echo "VM load       : $(podman machine ssh 'cut -d" " -f1-3 /proc/loadavg' 2>/dev/null)   (healthy: under about 8)"
    echo "running       : $(podman ps -q 2>/dev/null | wc -l | tr -d ' ') containers"
    echo "test (running): $(podman ps -q --filter label=org.testcontainers=true 2>/dev/null | wc -l | tr -d ' ') with org.testcontainers, anything above 0 outside a test run is a leak"
    echo "test (dead)   : $(podman ps -aq --filter label=org.testcontainers=true --filter status=exited --filter status=created 2>/dev/null | wc -l | tr -d ' ') exited or created (disk only)"
    echo "by image      :"; podman ps --format '{{.Image}}' 2>/dev/null | sed 's|.*/||' | sort | uniq -c | sort -rn | head -6 | sed 's/^/  /'
  }

  # tc-clean [--yes] [--dead]
  # Stops RUNNING Testcontainers containers older than 10 minutes (a fresh one may belong to a test run
  # that has just started). It lists them and asks first; --yes skips the question. --dead also deletes
  # exited and created ones, which cost disk only and may belong to any project.
  tc-clean() {
    local yes=0 dead=0 arg id created victims=() now=$(date +%s)
    for arg in "$@"; do
      case "$arg" in
        --yes) yes=1 ;;
        --dead) dead=1 ;;
        *) echo "usage: tc-clean [--yes] [--dead]" >&2; return 2 ;;
      esac
    done
    for id in $(podman ps -q --filter label=org.testcontainers=true 2>/dev/null); do
      created=$(podman inspect --format '{{.Created.Unix}}' "$id" 2>/dev/null) || continue
      [ -n "$created" ] && [ "$created" -le $(( now - 600 )) ] && victims+=("$id")
    done
    if [ ${#victims[@]} -eq 0 ]; then
      echo "no running Testcontainers containers older than 10 minutes"
    else
      echo "running Testcontainers containers older than 10 minutes:"
      for id in "${victims[@]}"; do podman ps --filter "id=$id" --format '  {{.ID}}  {{.Image}}  {{.Status}}'; done
      if [ $yes -eq 0 ]; then
        read -q "?stop and remove ${#victims[@]} container(s)? [y/N] " || { echo; return 1; }
        echo
      fi
      podman rm -f "${victims[@]}" >/dev/null && echo "removed ${#victims[@]}"
    fi
    if [ $dead -eq 1 ]; then
      local gone; gone=($(podman ps -aq --filter label=org.testcontainers=true --filter status=exited --filter status=created 2>/dev/null))
      [ ${#gone[@]} -gt 0 ] && podman rm -f "${gone[@]}" >/dev/null && echo "removed ${#gone[@]} dead"
    fi
    podman network prune -f --filter label=org.testcontainers=true >/dev/null 2>&1
    return 0
  }
fi
