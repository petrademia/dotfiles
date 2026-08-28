# Interactive convenience. Make/scripts use PATH shims from install.sh
# (~/.local/bin/docker -> bin/docker) because aliases are not inherited.
if command -v podman >/dev/null 2>&1; then
  export PODMAN_COMPOSE_WARNING_LOGS=false
  alias docker='podman'
  alias docker-compose='podman-compose'
fi
