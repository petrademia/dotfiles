@echo off
REM PATH shim for legacy `docker-compose` callers.
where podman >nul 2>&1
if errorlevel 1 (
  echo docker-compose: podman not found (install Podman or real Docker) 1>&2
  exit /b 127
)
podman compose %*
