#!/bin/bash
# Checks the shell, git and container-VM defaults: zsh options, git config, global ignore,
# the timeout shim, VM sizing, and that tc-clean only touches old running Testcontainers containers.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# zsh options
zsh -fc "source '$repo/config/zsh/options.zsh'; [[ -o interactive_comments ]] && [[ -o share_history ]] && [[ \$HISTSIZE -ge 100000 ]]" \
  || fail "options.zsh did not set interactive_comments, share_history and a long history"
zsh -fc "source '$repo/config/zsh/options.zsh'; [[ ! -o inc_append_history ]]" \
  || fail "inc_append_history must stay off: share_history already appends"

# git config
cfg="$repo/git/gitconfig"
git config --file "$cfg" --list >/dev/null || fail "git/gitconfig does not parse"
want() { [ "$(git config --file "$cfg" --get "$1")" = "$2" ] || fail "git config $1 is not $2"; }
want rerere.enabled true
want rebase.autoSquash true
want rebase.updateRefs true
want merge.conflictStyle zdiff3
want pull.ff only
want push.autoSetupRemote true
want fetch.prune true
want diff.algorithm histogram
want alias.pushf 'push --force-with-lease --force-if-includes'
git config --file "$cfg" --get-regexp '^includeif' | grep -q 'Amartha' || fail "the Amartha includeIf was lost"

# global ignore, linked by install.sh
for pat in '.DS_Store' '*.orig' '*.rej'; do grep -qxF "$pat" "$repo/git/ignore" || fail "git/ignore lacks $pat"; done
grep -q 'git/ignore' "$repo/install.sh" || fail "install.sh does not link git/ignore"

# timeout shim
mkdir -p "$work/stub"
out=$(PATH="$work/emptybin" /bin/sh "$repo/bin/timeout" 5 true 2>&1 || true)
case "$out" in *'brew install coreutils'*) ;; *) fail "timeout shim does not explain the missing gtimeout" ;; esac
printf '#!/bin/sh\necho "gtimeout $*"\n' > "$work/stub/gtimeout"; chmod +x "$work/stub/gtimeout"
[ "$(PATH="$work/stub:$PATH" /bin/sh "$repo/bin/timeout" 5 true)" = "gtimeout 5 true" ] || fail "timeout shim does not exec gtimeout"

# VM sizing and packages
grep -q '^memory = 12288' "$repo/config/containers/containers.conf" || fail "containers.conf does not size new machines"
for f in coreutils temporal golangci-lint libpq; do grep -qw "$f" "$repo/setup/macos.sh" || fail "setup/macos.sh does not install $f"; done

# tc-clean: stub podman with one old and one fresh running container, plus a dead one that must survive
now=$(date +%s)
cat > "$work/stub/podman" <<STUB
#!/bin/sh
case "\$1" in
  ps)
    case "\$*" in
      *"status=exited"*) echo dead1 ;;
      *"--filter id="*) echo "  \${*##*id=}  img  Up" ;;
      *) printf 'old1\nfresh1\n' ;;
    esac ;;
  inspect)
    case "\$*" in *old1*) echo $((now - 3600)) ;; *fresh1*) echo $((now - 30)) ;; esac ;;
  rm) shift; echo "\$*" >> "$work/removed" ;;
  network) : ;;
esac
STUB
chmod +x "$work/stub/podman"
: > "$work/removed"
PATH="$work/stub:$PATH" zsh -fc "source '$repo/config/zsh/podman.zsh'; tc-clean --yes" >/dev/null
[ "$(cat "$work/removed")" = "-f old1" ] || fail "tc-clean removed '$(cat "$work/removed")' instead of only old1"
: > "$work/removed"
PATH="$work/stub:$PATH" zsh -fc "source '$repo/config/zsh/podman.zsh'; tc-clean --yes --dead" >/dev/null
grep -q '^-f old1$' "$work/removed" && grep -q '^-f dead1$' "$work/removed" || fail "tc-clean --dead did not remove the dead container"
grep -q fresh1 "$work/removed" && fail "tc-clean removed a container younger than 10 minutes"
PATH="$work/stub:$PATH" zsh -fc "source '$repo/config/zsh/podman.zsh'; tc-clean --bogus" >/dev/null 2>&1 && fail "tc-clean accepted an unknown flag"

# get-keys: exports nothing unless every read succeeds, and says which one failed
mkdir -p "$work/op"
cat > "$work/op/op" <<'STUB'
#!/bin/sh
[ "$1" = whoami ] && exit 0
[ "$1" = read ] || exit 1
case "$2" in *Gemini*) [ -n "$FAIL_GEMINI" ] && exit 1 ;; esac
echo "value-for-$2"
STUB
chmod +x "$work/op/op"
out=$(PATH="$work/op:$PATH" zsh -fc "source '$repo/config/zsh/ai.zsh'; get-keys && echo \"\$ANTHROPIC_API_KEY\"" 2>&1)
case "$out" in *'value-for-op://Private/Anthropic/credential'*) ;; *) fail "get-keys did not export the keys: $out" ;; esac
out=$(FAIL_GEMINI=1 PATH="$work/op:$PATH" zsh -fc "source '$repo/config/zsh/ai.zsh'; get-keys; echo \"rc=\$? set=\${ANTHROPIC_API_KEY:+yes}\"" 2>&1)
case "$out" in *'could not read: Gemini'*'rc=1 set=') ;; *) fail "get-keys did not fail cleanly on a missing item: $out" ;; esac

# .zshrc keeps PATH free of duplicates
dups=$(zsh -fc 'PATH=/a:/b:/a; source "$1"; print -r -- "$PATH"' _ "$repo/shell/.zshrc" 2>/dev/null | tr ':' '\n' | sort | uniq -d)
[ -z "$dups" ] || fail "PATH has duplicates after sourcing .zshrc: $dups"

# agent instructions
grep -q '^## Shell and tooling' "$repo/global/AGENTS.md" || fail "global/AGENTS.md lacks the Shell and tooling section"
if grep -q $'\xe2\x80\x94' "$repo/global/AGENTS.md"; then fail "global/AGENTS.md contains an em dash"; fi
printf 'Dev environment checks passed.\n'
