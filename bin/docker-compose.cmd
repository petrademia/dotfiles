@echo off
REM PATH shim for legacy `docker-compose` callers.
where podman-compose >nul 2>&1
if not errorlevel 1 (
  podman-compose %*
  exit /b %ERRORLEVEL%
)
where podman >nul 2>&1
if errorlevel 1 (
  echo docker-compose: podman not found (install Podman or real Docker) 1>&2
  exit /b 127
)
podman compose %*
