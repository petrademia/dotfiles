@echo off
REM PATH shim so Make/cmd find `docker` without PowerShell aliases.
where podman >nul 2>&1
if errorlevel 1 (
  echo docker: podman not found (install Podman or real Docker) 1>&2
  exit /b 127
)
podman %*
