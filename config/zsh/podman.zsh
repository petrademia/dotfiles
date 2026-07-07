if command -v podman >/dev/null 2>&1; then
  alias docker='podman'
  alias docker-compose='podman compose'
fi
