#!/usr/bin/env bash
#
# secondary-setup.sh
# ----------------------------------------------------------------------------
# Bootstrap the secondary/mobile Mac to connect to the primary:
#   - Tailscale      -> join the same private mesh as the primary
#   - SSH key        -> generate if missing; print public key to add to primary
#   - Claude Code    -> verify it's installed
#
# Run this on your SECONDARY machine (MacBook / laptop).
# The primary must already have Tailscale installed and be on your tailnet.
#
# USAGE:
#   chmod +x secondary-setup.sh
#   ./secondary-setup.sh
# ----------------------------------------------------------------------------

set -uo pipefail

bold=$(printf '\033[1m'); green=$(printf '\033[32m')
yellow=$(printf '\033[33m'); red=$(printf '\033[31m'); reset=$(printf '\033[0m')

say()  { printf '%s\n' "${bold}==>${reset} $*"; }
ok()   { printf '%s\n' "    ${green}✓${reset} $*"; }
warn() { printf '%s\n' "    ${yellow}!${reset} $*"; }
err()  { printf '%s\n' "    ${red}✗${reset} $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

echo
say "Secondary Mac bootstrap"
echo

# ---------- 1. Tailscale ------------------------------------------------------
say "Tailscale"
if have tailscale; then
  ok "tailscale present ($(tailscale --version | head -1))"
else
  warn "Tailscale not installed."
  warn "Because the installer requires an interactive sudo prompt, run this"
  warn "yourself in a real terminal (not inside Claude Code's Bash tool):"
  echo
  echo "    brew install --cask tailscale"
  echo
  warn "Then open the Tailscale app and sign in to the SAME account as the primary."
fi

# ---------- 2. SSH key --------------------------------------------------------
say "SSH key"
KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$KEY" ]]; then
  ok "ed25519 key exists"
else
  warn "No ed25519 key found — generating one now."
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -C "$(id -un)@$(hostname)" -f "$KEY" -N ""
  ok "Key generated: $KEY"
fi

echo
say "Your public key — add this to the primary's ~/.ssh/authorized_keys:"
echo
cat "${KEY}.pub"
echo
warn "On the primary, run:"
echo "    echo \"$(cat "${KEY}.pub")\" >> ~/.ssh/authorized_keys"
echo "    chmod 600 ~/.ssh/authorized_keys"
echo

# ---------- 3. Claude Code ----------------------------------------------------
say "Claude Code"
if have claude; then
  ok "claude present ($(claude --version 2>/dev/null | head -1))"
else
  warn "Claude Code not installed."
  curl -fsSL https://claude.ai/install.sh | bash
  have claude && ok "claude installed" || warn "Installed but not on PATH yet — open a new terminal."
fi

# ---------- 4. Verify Tailscale -----------------------------------------------
say "Tailscale status"
if have tailscale; then
  tailscale status 2>/dev/null || warn "Tailscale installed but not connected — open the app and sign in."
else
  warn "Tailscale not installed — see step 1 above."
fi

# ---------- next steps --------------------------------------------------------
echo
say "${green}Next steps:${reset}"
cat << 'EOF'

  1. If Tailscale wasn't installed above, run in a terminal:
       brew install --cask tailscale
     Then open the app and sign in to your tailnet.

  2. Add your public key (printed above) to the primary:
       On primary: echo "ssh-ed25519 ..." >> ~/.ssh/authorized_keys

  3. Fix SSH PATH on primary (so claude/brew/node are visible over SSH):
       PRIMARY_USER=<user> PRIMARY_HOST=<primary-tailscale-ip> bash ssh-path-fix.sh

  4. Test the connection:
       ssh <user>@<primary-tailscale-ip> "claude --print 'hello from primary'"

  5. Interactive session on primary:
       ssh -t <user>@<primary-tailscale-ip> "claude"

EOF
ok "Done."
