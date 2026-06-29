#!/usr/bin/env bash
#
# primary-setup.sh
# ----------------------------------------------------------------------------
# Bootstrap the primary desktop as the canonical environment:
#   - Tailscale      -> private mesh so laptop + phone can reach this machine
#   - git + gh       -> version control + GitHub as source of truth
#   - SSH server     -> remote-in from the laptop (edit files in place)
#   - Claude Code    -> AI runs HERE, against the canonical files
#
# WHAT THIS SCRIPT DOES NOT DO (on purpose):
#   - It never asks for, stores, or types any password, API key, or token.
#     All sign-ins (Tailscale, GitHub, Claude) are interactive flows that YOU
#     complete in a browser AFTER this script finishes. They can't be scripted
#     safely and shouldn't be.
#   - It won't flip a security setting (the SSH server) without asking you Y/N.
#
# SUPPORTED: macOS and Linux. If primary is Windows, stop here and ask for the
# PowerShell (.ps1) version instead — this bash script won't run natively.
#
# USAGE:
#   chmod +x gdesk-setup.sh
#   ./gdesk-setup.sh
# ----------------------------------------------------------------------------

set -uo pipefail

# ---------- pretty output ----------------------------------------------------
bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); green=$(printf '\033[32m')
yellow=$(printf '\033[33m'); red=$(printf '\033[31m'); reset=$(printf '\033[0m')

say()  { printf '%s\n' "${bold}==>${reset} $*"; }
ok()   { printf '%s\n' "    ${green}✓${reset} $*"; }
warn() { printf '%s\n' "    ${yellow}!${reset} $*"; }
err()  { printf '%s\n' "    ${red}✗${reset} $*" >&2; }
ask()  { # ask "question" -> returns 0 for yes, 1 for no (default no)
  local reply
  printf '%s' "    ${bold}$1 [y/N]${reset} "
  read -r reply || true
  [[ "$reply" =~ ^[Yy]$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------- OS detection -----------------------------------------------------
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *) err "Unsupported OS: $OS. This script handles macOS and Linux only."
     err "If primary is Windows, ask for the PowerShell version."
     exit 1 ;;
esac

LINUX_PM=""
if [[ "$PLATFORM" == "linux" ]]; then
  if   have apt-get; then LINUX_PM="apt"
  elif have dnf;     then LINUX_PM="dnf"
  elif have pacman;  then LINUX_PM="pacman"
  fi
fi

echo
say "primary bootstrap — detected ${bold}${PLATFORM}${reset}${LINUX_PM:+ (${LINUX_PM})}"
echo "    ${dim}Nothing destructive runs without a prompt. Ctrl-C any time.${reset}"
echo

# ---------- 0. Homebrew (macOS only) ----------------------------------------
ensure_brew() {
  [[ "$PLATFORM" == "macos" ]] || return 0
  if have brew; then ok "Homebrew present"; return 0; fi
  warn "Homebrew is not installed (it's the cleanest way to get the rest on macOS)."
  if ask "Install Homebrew now?"; then
    /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # make brew available in this shell session
    if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
    have brew && ok "Homebrew installed" || err "Homebrew install did not complete"
  else
    warn "Skipping Homebrew — git/gh/tailscale steps below may not run on macOS."
  fi
}

# ---------- 1. git + GitHub CLI ---------------------------------------------
install_git_gh() {
  say "git + GitHub CLI"
  if have git; then ok "git present"; else
    case "$PLATFORM" in
      macos) have brew && brew install git ;;
      linux)
        case "$LINUX_PM" in
          apt)    sudo apt-get update -y && sudo apt-get install -y git ;;
          dnf)    sudo dnf install -y git ;;
          pacman) sudo pacman -Sy --noconfirm git ;;
          *) warn "Install git manually for your distro." ;;
        esac ;;
    esac
    have git && ok "git installed" || err "git not installed"
  fi

  if have gh; then ok "GitHub CLI present"; else
    case "$PLATFORM" in
      macos) have brew && brew install gh ;;
      linux)
        case "$LINUX_PM" in
          dnf)    sudo dnf install -y gh ;;
          pacman) sudo pacman -Sy --noconfirm github-cli ;;
          apt)
            # gh isn't in default apt repos; add the official one
            sudo mkdir -p -m 755 /etc/apt/keyrings
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
              | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
            sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
              | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            sudo apt-get update -y && sudo apt-get install -y gh ;;
          *) warn "Install gh manually: https://github.com/cli/cli#installation" ;;
        esac ;;
    esac
    have gh && ok "GitHub CLI installed" || warn "gh not installed (optional, but handy)"
  fi
}

# ---------- 2. Tailscale ------------------------------------------------------
install_tailscale() {
  say "Tailscale (private mesh network)"
  if have tailscale; then ok "tailscale present"; return 0; fi
  case "$PLATFORM" in
    macos)
      # The app (cask) is the smoothest path on a desktop with a GUI.
      if have brew; then
        brew install --cask tailscale && ok "Tailscale app installed"
        warn "Open the Tailscale app and sign in to finish (see NEXT STEPS)."
      else
        warn "No Homebrew — get Tailscale from https://tailscale.com/download"
      fi ;;
    linux)
      # Official installer detects the distro and sets up the daemon.
      curl -fsSL https://tailscale.com/install.sh | sh
      have tailscale && ok "Tailscale installed" || err "Tailscale install failed" ;;
  esac
}

# ---------- 3. SSH server (security setting — gated) -------------------------
enable_ssh() {
  say "SSH server (lets the laptop edit primary's files in place)"
  warn "This changes a system/security setting: it makes primary accept incoming"
  warn "SSH. With Tailscale, only your own devices can reach it — but it's still"
  warn "your call."
  if ! ask "Enable the SSH server on primary now?"; then
    warn "Skipped. You can enable it later when you're ready."
    return 0
  fi
  case "$PLATFORM" in
    macos)
      sudo systemsetup -setremotelogin on \
        && ok "Remote Login (SSH) enabled" \
        || err "Could not enable Remote Login" ;;
    linux)
      case "$LINUX_PM" in
        apt)    sudo apt-get install -y openssh-server ;;
        dnf)    sudo dnf install -y openssh-server ;;
        pacman) sudo pacman -Sy --noconfirm openssh ;;
      esac
      # service name is 'ssh' on Debian/Ubuntu, 'sshd' elsewhere
      if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        sudo systemctl enable --now ssh
      else
        sudo systemctl enable --now sshd
      fi
      ok "SSH server enabled" ;;
  esac
}

# ---------- 4. Claude Code ----------------------------------------------------
install_claude_code() {
  say "Claude Code (AI runs here, on the canonical files)"
  if have claude; then ok "Claude Code present"; return 0; fi
  case "$PLATFORM" in
    macos|linux)
      # Native installer (Anthropic's recommended method) — no Node.js needed.
      curl -fsSL https://claude.ai/install.sh | bash
      if have claude; then
        ok "Claude Code installed"
      else
        warn "Installed, but 'claude' isn't on PATH yet."
        warn "Open a NEW terminal, or add its bin dir to PATH, then run: claude --version"
      fi ;;
  esac
}

# ---------- run --------------------------------------------------------------
ensure_brew
install_git_gh
install_tailscale
enable_ssh
install_claude_code

# ---------- next steps (interactive — you do these) --------------------------
echo
say "${green}Tooling is in place. Finish with these interactive logins YOURSELF:${reset}"
cat <<'EOF'

  1. Join your Tailnet
       macOS:  open the Tailscale app, sign in
       Linux:  sudo tailscale up
     Then note this machine's address:
       tailscale ip -4        # the 100.x.y.z address
       tailscale status       # confirm the laptop/phone appear here later

  2. Sign in to GitHub
       gh auth login          # pick HTTPS, follow the browser prompt

  3. Sign in to Claude Code (just launch it once)
       claude                 # complete the browser OAuth, then /exit

  4. Put your canonical repo here (example)
       mkdir -p ~/Projects && cd ~/Projects
       git clone https://github.com/<you>/<repo>.git
       # this clone on primary is your primary working copy

  From the LAPTOP later: install Tailscale (same account), then
       ssh <user>@<gdesk-tailscale-name>
  or open the repo folder over VS Code Remote-SSH — you'll be editing
  primary's files directly, no duplicate copies.

  Remember the model: GitHub = truth, primary = primary, laptop clones =
  disposable (always commit + push before you walk away from one).
EOF
echo
ok "Done."
