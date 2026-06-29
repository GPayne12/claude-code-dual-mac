#!/usr/bin/env bash
#
# ssh-path-fix.sh
# ----------------------------------------------------------------------------
# Run this from the secondary machine to fix the SSH PATH on the primary.
#
# Problem: SSH non-interactive sessions on macOS don't source ~/.zprofile,
# so Homebrew tools (claude, node, brew, gh) disappear from PATH even though
# they're installed. The fix is to write ~/.zshenv on the primary, which IS
# sourced for all zsh sessions including non-interactive SSH.
#
# USAGE (from secondary):
#   PRIMARY_USER=alice PRIMARY_HOST=<tailscale-ip-or-hostname> bash ssh-path-fix.sh
# ----------------------------------------------------------------------------

set -euo pipefail

PRIMARY_USER="${PRIMARY_USER:-}"
PRIMARY_HOST="${PRIMARY_HOST:-}"

if [[ -z "$PRIMARY_USER" || -z "$PRIMARY_HOST" ]]; then
  echo "Usage: PRIMARY_USER=<user> PRIMARY_HOST=<ip-or-hostname> bash ssh-path-fix.sh"
  exit 1
fi

SSH="ssh -o IdentitiesOnly=yes -i $HOME/.ssh/id_ed25519 ${PRIMARY_USER}@${PRIMARY_HOST}"

echo "==> Writing ~/.zshenv on primary (${PRIMARY_USER}@${PRIMARY_HOST})"
$SSH 'cat > ~/.zshenv << '"'"'EOF'"'"'
eval "$(/usr/local/bin/brew shellenv zsh)"
export PATH="/usr/local/bin:$PATH"
EOF'

echo "==> Verifying tools on SSH PATH"
$SSH 'for cmd in brew claude node gh git; do
  path=$(command -v $cmd 2>/dev/null || echo "NOT FOUND")
  echo "  $cmd: $path"
done'
