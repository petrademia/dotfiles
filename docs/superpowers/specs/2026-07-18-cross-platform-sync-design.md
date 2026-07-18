# Cross-Platform Setup Synchronization Design

## Goal

Make macOS, Windows, and WSL provide a consistent working environment without forcing identical applications onto operating systems where they do not belong.

Success means:

- macOS and Windows provide the same selected cross-platform desktop workflows.
- WSL provides the same command-line development and AI workflows.
- WSL reuses Windows desktop applications instead of installing duplicate Linux GUI applications.
- Shared agent instructions, AI commands, editor configuration, and Git safeguards are installed on every supported environment.
- Every package identifier is verified before it is added.

## Platform responsibilities

### macOS

macOS owns its native desktop applications, Homebrew packages, shell configuration, and local developer runtimes.

Pending additions to retain:

- Zen Browser
- Google Drive
- OneDrive

macOS-only utilities such as CotEditor, AppCleaner, Finder tools, DisplayLink, Rectangle, and DockDoor remain macOS-only.

### Windows

Windows owns all desktop and graphical applications used by Windows and WSL:

- Shared browser baseline: Chrome, Firefox Developer Edition, Brave, Vivaldi, Floorp, and Zen
- Microsoft Edge as the native Windows browser
- Google Drive and OneDrive
- Cursor, Visual Studio Code, and JetBrains Toolbox
- Slack and Discord
- Podman Desktop

Existing extra browsers and applications may remain installed, but synchronization will not add every macOS application merely for numerical parity.

Windows also owns host integrations such as Windows Terminal, PowerToys, firewall rules, and Windows application startup.

### WSL

WSL remains a command-line development environment:

- Git, GitHub CLI, and Atlassian CLI
- Go, Rust, Node.js, Python, Java, C, and C++ toolchains
- Neovim and terminal utilities
- Claude, Codex, OpenCode, Copilot, Z.ai, Playwright, and related AI tooling
- Shared agent instructions, commands, skills, Git configuration, and commit hooks

WSL must reuse Windows GUI applications and storage:

- Open projects in Windows Cursor, Visual Studio Code, or JetBrains through WSL integration.
- Access Windows cloud storage through mounted Windows paths such as `/mnt/c/Users/<user>/`.
- Use Windows browsers for links and authentication.
- Use the Windows Podman Desktop engine rather than installing a second independent desktop stack in WSL.

## Shared configuration architecture

The current `install.sh` cannot be run unchanged in WSL because it links macOS-specific zsh and Java configuration. Shared assets must therefore be separated from OS-specific shell configuration.

Create an OS-neutral installer boundary for:

- `global/AGENTS.md`
- Claude global instructions and RTK reference
- Neovim configuration
- Cursor CLI configuration
- `/grammar` and `/leetcode` commands and skills
- Go private-module environment
- Global Git include configuration
- Git hooks that remove AI attribution

macOS may continue to install zsh configuration from `config/zsh`.

WSL installs only Linux-safe shell configuration plus the shared assets.

Windows receives PowerShell equivalents for shared file links or copies and Git configuration. Windows must not depend on Bash to complete setup.

## Package synchronization

### Windows Node bootstrap

After installing `fnm`, the Windows setup must initialize it and install an LTS Node.js release before running `npm`. This prevents the current behavior where npm-based AI tools are silently skipped on a fresh Windows installation.

### Atlassian CLI

Install `atlassian-cli` on all three platforms:

- Homebrew on macOS
- Official Linux installer, Homebrew, or Cargo on WSL
- Official Windows binary or Cargo on Windows

The implementation must use a supported upstream installation method and preserve the separate Jira and Bitbucket credentials documented in the global agent instructions.

### Windows desktop applications

Verified Windows package identifiers for the newly requested host applications:

- `Zen-Team.Zen-Browser`
- `Google.GoogleDrive`
- `Microsoft.OneDrive`

The implementation must verify identifiers for other Windows additions before editing the package list.

OneDrive may already be present on Windows. Its setup step must remain idempotent and skip an installed copy.

### Containers

Do not install duplicate container engines merely for parity.

- macOS uses Podman Desktop installed by its supported package.
- Windows uses Podman Desktop and its engine.
- WSL interoperates with the Windows host setup where practical.

If Windows-to-WSL Podman interoperability cannot be configured reliably by the setup script, document the required one-time connection step instead of installing an unrelated fallback.

## Error handling and idempotency

- Existing installations must be detected and skipped.
- An unavailable optional desktop application must not abort installation of unrelated applications.
- Missing mandatory development tooling must produce a visible failure or warning, not a silent skip.
- Steps requiring an interactive administrator password must state that requirement.
- WSL must not modify Windows host configuration except through an explicit host-side setup step.

## Verification

Static verification:

- Validate shell syntax with `bash -n` or `zsh -n`.
- Parse the PowerShell script with the PowerShell parser when available.
- Check that every referenced source file exists.
- Search for stale package names and duplicated configuration blocks.

Runtime verification on each platform:

- Confirm versions for Git, Go, Rust, Node.js, Python, Java, Neovim, GitHub CLI, Atlassian CLI, Claude, and Codex.
- Confirm AI commands and skills resolve from their expected locations.
- Confirm global Git include and hooks are active.
- Confirm Windows host applications are installed or explicitly skipped as already present.
- Confirm WSL can access Windows-mounted cloud storage and launch the chosen Windows editor workflow.

## Non-goals

- Installing macOS-only applications on Windows or WSL.
- Installing Linux GUI duplicates inside WSL.
- Making package lists numerically identical.
- Introducing a generated cross-platform package manifest or configuration framework.
- Automatically signing users into desktop applications or cloud storage.
