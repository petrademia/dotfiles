# Dotfiles

## Installation

Each platform prints an install/update/skip/failure summary.

**What the summary means**

- **Installed** - newly provisioned on this run.
- **Skipped** - already present; setup did not reinstall or upgrade it.
- **Updated** - rare; only when a helper still needs a real version bump
  (for example Warp/EjectLens when the installed build differs).
- **Failed: 0** - everything required is present or was installed successfully.

Setup is provision-first, not a daily updater. Use `brew upgrade` on macOS,
UniGetUI, `scoop update *`, or `winget upgrade` when you want package upgrades.
Windows setup only prepares the WSL *host* (distro + user); run the Linux stack
separately inside Ubuntu.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh -o setup.sh && bash setup.sh
```

Apply macOS defaults and login items with:

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

The macOS bootstrap ensures a small login-item allowlist:

- 1Password
- Rectangle
- MonitorControl
- Scroll Reverser
- Google Drive
- OneDrive
- Deskflow
- Alfred
- Raycast

Apps that are not installed are skipped.

To make Raycast replace Spotlight for `⌘Space`:

1. Open Raycast settings with `⌘,`.
2. Select **General**.
3. Set **Raycast Hotkey** to `⌘Space`.
4. If macOS reports a conflict, disable **Show Spotlight search** under
   **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**.

### Windows

**One command does both phases** (admin is required, not optional):

```powershell
# Normal PowerShell (recommended) - user phase, then one UAC for admin
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex

# Or elevated PowerShell - admin phase, then user phase (non-elevated) automatically
curl.exe -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 -o $env:TEMP\windows.ps1
& $env:TEMP\windows.ps1
```

| How you start | What happens |
|---------------|--------------|
| Normal PS, no flags | User phase → **auto UAC** → admin phase |
| Elevated PS, no flags | Admin phase → **auto** user phase (drops elevation for Winget/Spotify) |
| Re-run when done | Mostly Skipped, no UAC |

Then **reboot** if WSL reported a pending feature change, and run Linux setup in Ubuntu:

```bash
bash ~/dotfiles/setup.sh
```

Opt out of auto-chaining with `-SkipAutoAdmin`. Run one phase only with `-UserPhase` or `-AdminPhase`.

The script sets the CurrentUser execution policy to `RemoteSigned`. If
`irm | iex` is blocked, run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

`setup/windows.ps1` applies the Windows equivalent of
`bootstrap/macos.sh`:

- **Files and input:** show file extensions and hidden files, open File
  Explorer to This PC (not Home), enable End Task on the taskbar, create
  `~/Screenshots`, enable faster key repeat and tap-to-click, disable Sticky
  Keys (Shift five times), and disable Windows three-finger swipe/tap so
  ThreeFingerDrag can own the gesture.
- **Power and navigation:** enable hibernation and add Hibernate to the power
  menu, enable NTFS long paths, and configure Alt+Tab to show windows only
  (not Edge tabs).
- **Start and Search:** more pins than recommendations, hide the Recommended
  section and Store tips, turn off account nags, disable Bing web results, and
  hide the Settings home page plus suggested content inside Settings.
- **Taskbar:** show battery percent; hide Search, Task View, Widgets, Chat,
  Copilot, and Resume; unpin default apps such as Edge, Store, File Explorer,
  Copilot, Mail, Teams, and Xbox.
- **Security:** enable Windows Security SmartScreen and PUA protection, and
  disable Smart App Control.
- **Startup:** use a default-deny policy. Only 1Password, ThreeFingerDrag,
  and Windows Security are enabled because they provide resident security or
  input behavior.
  - Start on demand: TrafficMonitor, window-switcher, Surfshark, Google
    Drive, OneDrive, Everything, and FDM.
  - Disabled at startup: DisplayLink's tray UI, browser helpers (Opera / GX /
    Air, Brave update), Steam, EA / Riot launchers and tray apps, UniGetUI,
    Discord, Slack, WhatsApp, Warp, OpenVPN Connect, Ollama, Spotify, Virtual
    Pet, ASUS Smart Display, Radeon overlay, Mobile devices/Phone Link,
    Copilot, Teams, ChatGPT, Xbox, To Do, and similar launchers or helpers.
- **Drivers and WSL:** keep the DisplayLink driver installed for dock support
  and leave the Riot Vanguard service enabled.

Some settings need elevation and are applied by `-AdminPhase`:

- Hibernation
- NTFS long paths
- HKLM startup
- Smart App Control
- The Widgets policy
- Consumer Features and hiding Start's Recommended section
- WSL host (Virtual Machine Platform, Ubuntu registration)
- DisplayLink driver
- Deskflow firewall rule

Alt+Tab and some taskbar changes may need a logoff or Explorer restart. On
some Windows 11 builds, Widgets (`TaskbarDa`) is ACL-locked; the Feeds policy
is the fallback.

After `windows.ps1`, sign into 1Password and run:

```powershell
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex
```

This configures `gh` and `atlassian-cli` from 1Password when tokens exist.

For optional Bitbucket clone/sync, ensure an SSH agent is running:

```powershell
$s = $env:TEMP\post-setup.ps1
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 -OutFile $s
& $s -SyncBitbucket
```

Windows directory-backed dotfiles are merged without deleting extra user files.

### WSL

The Windows **admin phase** installs or reconciles Ubuntu 24.04 with Winget
`Canonical.Ubuntu.2404` and `ubuntu2404.exe install --root`, then creates a
normal WSL user matching the Windows username. It does **not** run the Linux
package/AI stack; that stays a separate step so Windows re-runs stay fast.

Run `.\setup\windows.ps1 -AdminPhase` (elevated) on a fresh machine. Reboot
and re-run `-UserPhase` if Windows reports a pending feature change. If `wsl`
reports `REGDB_E_CLASSNOTREG`, the admin phase downloads the official
`wsl.msi` and repairs the host inline (no nested UAC prompts).

Inside Ubuntu, run the Linux stack:

```bash
# Prefer the local clone when you have unpushed setup fixes:
bash ~/dotfiles/setup.sh
# Or from GitHub main:
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh | bash
```

On repeat runs, repo-managed items are skipped when already installed. The
package managers used across the platform scripts include:

- Homebrew
- Scoop
- Winget
- npm
- apt
- Rustup
- SDKMAN!
- uv

Version-aware checks also update direct-download tools such as WSL Zellij,
Helix, kubectl, kind, k3d, Windows Warp, and EjectLens. Other vendor
installers remain guarded when they do not expose a safe version check.

## Updating

The setup command handles cloning on a new machine. For an existing clone,
run:

```bash
cd ~/dotfiles
git pull
```

Then run the platform-specific setup again:

- macOS: `./setup.sh` and `zsh bootstrap/macos.sh`
- WSL: `./setup.sh`
- Windows: `.\setup\windows.ps1 -UserPhase` (and `-AdminPhase` when the script says admin work is pending)

## Java

Supported JDK vendors and versions:

- Temurin, Zulu, Corretto, and Liberica: versions 8–25
- Microsoft: versions 11–25

Windows installs this matrix through `bootstrap/java-windows.ps1`.
The script is idempotent. macOS and WSL use standalone scripts that are not
part of `setup.sh`.

macOS (download then run; a TTY is needed for sudo `.pkg` passwords):

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-macos.sh -o /tmp/java-macos.sh
bash /tmp/java-macos.sh
```

```bash
# WSL
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-wsl.sh | bash

# Windows (already run by windows.ps1; safe to re-run)
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-windows.ps1 | iex
```

Switch versions with:

- macOS/WSL: `java-use 21-temurin`
- Windows: `jv temurin21-jdk`

## CLIs

Setup includes:

- `gh`
- `atlassian-cli`
- `wrangler` (Cloudflare Pages/Workers)

Authenticate GitHub with:

```bash
gh auth login
```

### Amartha and Atlassian

On Windows, no GitHub binary is available for `atlassian-cli`. Setup compiles
it with MSVC `link.exe` when present, or with Scoop `gcc` and the GNU Rust
target otherwise. Visual Studio 2022 Build Tools (C++ workload) are installed
so `rustup-msvc` and UniGetUI Rust packages can link.

```bash
atlassian-cli auth login --profile amartha --bitbucket --bearer --workspace Amartha
```

Amartha repository sync:

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh | zsh
```

It uses the 1Password item `Amartha Bitbucket PR Review`.

Atlassian API tokens are per-app and scoped. Keep separate 1Password items:

- `Amartha Jira API`: Jira REST
- `Amartha Bitbucket PR Review`: Bitbucket PR and API

## Git and SSH

SSH credentials for Git operations are separate from the Amartha API tokens.

- `petruswiyadi-Bitbucket`: SSH for Git push

## AI

Available commands:

- `/grammar`
- `/leetcode`
- `/handoff`

These are available in Cursor, Claude, Copilot, Zai, Gemini/Antigravity, and
Codex.

Setup also installs Caveman, ponytail, and [Impeccable](https://github.com/pbakaus/impeccable).
The Impeccable design skills are available globally for Claude, Codex, Cursor,
Gemini, OpenCode, and Pi.

Installed agent clients include:

- Hermes Agent
- Pi Coding Agent
- Oh My Pi (`omp`)
- [Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (`reasonix`)
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`; needs Node 22.19+ or 24+)
- OpenClaw
- Kimi Code CLI
- Antigravity CLI (`agy`)
- [Goose](https://github.com/aaif-goose/goose)

Antigravity desktop (2.0) and Goose desktop are installed on macOS and
Windows. WSL uses the CLI agents (`agy`, `goose`) and reuses the Windows
desktop apps.

Antigravity skills are linked into `~/.gemini/config/skills/`, which works in
Desktop, CLI, and IDE. Product-specific roots (`antigravity/`,
`antigravity-cli/`) are also populated.

Skills with `disable-model-invocation` must be run as slash commands, such as
`/grammar`, rather than auto-selected.

## Local AI

Installed on macOS and Windows:

- Ollama
- LM Studio
- llama.cpp

WSL installs the llama.cpp CLI, maps `ollama` to the Windows CLI when
available, and reuses the Windows Ollama and LM Studio servers.

Models are not downloaded automatically. Start with:

```bash
ollama run llama3.2
```

Use `llama --help` for the WSL installer or `llama-cli --help` for
package-manager builds.

## Troubleshooting and manual steps

### Apps and drivers

- Velja: install from the App Store.
- JetBrains: install through Toolbox.
- [Wavlink drivers](https://www.wavlink.com/en_us/Drivers.html): install manually.
- DisplayLink is included in setup on macOS and Windows; reboot after
  installation.
- If DisplayLink returns Winget error 1603 on Windows, reboot and re-run that
  package ID with elevation.
- Deskflow error 1603 usually means an old VC++ runtime. Setup upgrades
  `Microsoft.VCRedist.2015+.x64` before installing it.

### Windows utilities

- NetSpeedTray and TrafficMonitor Lite provide taskbar network speed.
- Setup adds a Start Menu shortcut and autostart for TrafficMonitor, and turns
  on its taskbar window.
- [ThreeFingerDragOnWindows](https://github.com/ClementGre/ThreeFingerDragOnWindows)
  (`9MSX91WQCM2V`) provides macOS-style three-finger drag. Windows three-finger
  Task View swipes are disabled so it can work.
- [G-Helper](https://github.com/seerge/g-helper) (`seerge.g-helper`) is installed
  for ROG Flow X13 as a lightweight Armoury Crate alternative. Setup installs
  .NET 10 Desktop Runtime first. Do not run G-Helper and Armoury Crate at the
  same time.
- Realtek Audio Control (`9P2B8MCSVPLN`) is the Store mixer for the OEM DCH
  audio driver. Other ASUS support-page apps (GlideX, Dolby, NVIDIA Control
  Panel) stay manual or unused.
- Logitech C920 on this machine: disable **HD Pro Webcam C920** under Device
  Manager → Sound, video and game controllers, and leave **Cameras → HD Pro
  Webcam C920** enabled. The C920 USB mic crashes `Audiosrv` (`0xc0000005`);
  Settings then shows no input or output devices even though Realtek is still
  in Device Manager. Use the dedicated USB microphone instead. WAVLINK
  `TB4 USB Audio` is optional to disable if unused; it is not the crash.

### macOS containers

Podman uses the `applehv` provider through
`config/containers/containers.conf`. This avoids libkrun/
`krunkit --timesync` skew with Podman Desktop. The `[engine]` table also sets
`compose_warning_logs = false` and prefers Homebrew `podman-compose` so
`podman compose` does not loop through the `docker-compose` PATH shim.

New machines inherit that provider. If Podman Desktop keeps trying to start a
leftover libkrun machine, stop or remove that machine.

When Podman is installed, setup links PATH shims (`~/.local/bin/docker` and
`docker-compose`) so Make and other non-interactive tools resolve `docker
compose` without relying on shell aliases. Interactive shells still alias
`docker`/`docker-compose` to Podman. Setup also installs `podman-compose`
(Homebrew on macOS; `uv tool` on Windows/WSL) as the Compose provider behind
`podman compose`.

### Kubernetes

`kubectl`, `kind`, and `k3d` are installed by setup on macOS, Windows, and WSL.
Clusters are not created automatically. When needed, run either:

```bash
kind create cluster
k3d cluster create
```

Podman or Docker must be running first.

## Layout

```
setup.sh setup/   installers (macos.sh, windows.ps1, wsl.sh)
install.sh        symlinks (macOS/WSL; Windows copies via windows.ps1)
bootstrap/        java-*, macos.sh, post-setup.ps1
ai/ git/ go/ cursor/ shell/ bin/ (docker shims) config/ (nvim, zellij, zsh, containers) scripts/
```
