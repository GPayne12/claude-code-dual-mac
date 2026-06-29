# Claude Code — Dual Mac Setup via Tailscale + SSH

Connect two Macs running Claude Code into a unified environment: one primary machine owns the files and compute, one secondary machine drives it remotely over a private Tailscale mesh. No Docker, no cloud tunnel, no complexity.

---

## What You Get

- **Secondary** (MacBook / laptop) SSHs into **primary** (Mac Mini / desktop) over Tailscale
- All Claude commands on the primary are driveable from the secondary with a single SSH prefix
- Tools on the primary (`claude`, `brew`, `node`, `gh`, `git`) are fully accessible over SSH
- Persistent projects, memory, and sessions live on the primary — secondary is stateless
- No open ports to the internet; Tailscale handles NAT traversal and encryption

---

## Architecture

```
Secondary (MacBook — mobile/lightweight)
  │
  │  Tailscale mesh (100.x.y.z private IPs, encrypted)
  │
Primary (Mac Mini / desktop — canonical)
  ├── ~/projects/        ← codebases
  ├── ~/.claude/         ← memory, config, plugins
  ├── claude --print     ← remote one-shot AI
  └── claude (TTY)       ← interactive AI sessions
```

The secondary never stores canonical state. Everything lives on the primary. Secondary SSHes in and drives it.

---

## Prerequisites

| Machine | Requirements |
|---------|-------------|
| Primary (desktop) | macOS, Homebrew, `claude`, `git`, `gh`, `node` installed; SSH server enabled |
| Secondary (laptop) | macOS, `claude` installed locally; SSH key pair |
| Both | Tailscale account (free tier works); same tailnet |

---

## Step 1 — Bootstrap the Primary

Run `primary-setup.sh` on the primary machine. It installs Homebrew, git, gh, Tailscale, enables the SSH server, and installs Claude Code.

```bash
chmod +x primary-setup.sh
./primary-setup.sh
```

Then complete the interactive logins the script prints at the end:

```bash
# 1. Join tailnet
sudo tailscale up        # follow browser prompt
tailscale ip -4          # note your 100.x.y.z IP

# 2. GitHub
gh auth login

# 3. Claude Code
claude                   # complete OAuth, then /exit
```

---

## Step 2 — Bootstrap the Secondary

Run `secondary-setup.sh` on the secondary machine. It installs Tailscale, generates an SSH key, and waits for you to join the tailnet.

```bash
chmod +x secondary-setup.sh
./secondary-setup.sh
```

> **Note:** `brew install --cask tailscale` requires an interactive sudo prompt. If running inside Claude Code's Bash tool, use `! brew install --cask tailscale` in your terminal instead.

After Tailscale installs, open the app and sign in to the **same tailnet** as the primary.

---

## Step 3 — Authorize the Secondary's SSH Key on the Primary

On the primary, add the secondary's public key:

```bash
# On primary — paste secondary's public key (from ~/.ssh/id_ed25519.pub on secondary)
echo "ssh-ed25519 AAAA... user@hostname" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Or from the secondary, once Tailscale is running:

```bash
ssh-copy-id <user>@<primary-tailscale-ip>
```

---

## Step 4 — Fix SSH PATH on the Primary

SSH non-interactive sessions don't source `.zprofile`, so Homebrew tools vanish from `PATH`. Fix this once:

```bash
# Run from secondary, or directly on primary
PRIMARY_USER=<user> PRIMARY_HOST=<primary-tailscale-ip> bash ssh-path-fix.sh
```

Verify:

```bash
ssh <user>@<primary-tailscale-ip> 'for cmd in brew claude node gh git; do echo "$cmd: $(command -v $cmd)"; done'
```

---

## Step 5 — Verify End to End

```bash
# Ping
ping -c 3 <primary-tailscale-ip>

# SSH
ssh <user>@<primary-tailscale-ip> "uname -a && whoami"

# Claude on primary from secondary
ssh <user>@<primary-tailscale-ip> "claude --print 'confirm you are running on the primary'"
```

---

## Daily Usage

### One-shot Claude prompt on primary

```bash
ssh <user>@<primary-hostname> "claude --print 'your prompt here'"
```

### Interactive Claude session on primary

```bash
ssh -t <user>@<primary-hostname> "claude"
```

The `-t` flag allocates a TTY — required for interactive Claude.

### Run Claude against a file on the primary

```bash
ssh <user>@<primary-hostname> "claude --print 'summarize this' < ~/projects/myproject/README.md"
```

### Change into a project directory first

```bash
ssh -t <user>@<primary-hostname> "cd ~/projects/myproject && claude"
```

### Run any tool on primary

```bash
ssh <user>@<primary-hostname> "node --version"
ssh <user>@<primary-hostname> "gh pr list"
ssh <user>@<primary-hostname> "brew upgrade"
```

---

## File Layout on Primary

```
~/projects/
├── <your-project>/    ← active codebases (git-tracked)
└── ...

~/.claude/
├── settings.json      ← theme, permissions
├── memory/            ← persistent cross-session memory
├── sessions/          ← session history
└── plugins/           ← installed skills and plugins
```

---

## Tailscale Reference

```bash
tailscale status              # see all devices on your tailnet
tailscale ip -4               # this machine's 100.x address
ping <hostname>               # machines are reachable by Tailscale hostname too
```

Tailscale assigns stable `100.x.y.z` addresses that don't change. You can use either the IP or the machine's Tailscale hostname in SSH commands.

---

## Troubleshooting

### SSH: Connection refused
The primary's SSH server isn't running. On the primary:
```bash
sudo systemsetup -setremotelogin on
sudo systemsetup -getremotelogin   # should return: Remote Login: On
```

### SSH: Permission denied / Too many authentication failures
The secondary's public key isn't in the primary's `~/.ssh/authorized_keys`. Re-run Step 3.

### `claude` / `brew` / `node` not found over SSH
The `~/.zshenv` PATH fix isn't applied. Re-run Step 4 (`ssh-path-fix.sh`).

### Tailscale: machines not seeing each other
Both machines must be signed into the **same Tailscale account** (same tailnet). Check with `tailscale status` on each — both should appear in the list.

### `brew install --cask tailscale` fails with sudo error
The cask installer needs an interactive terminal. Run in a real terminal (not a background process):
```bash
brew install --cask tailscale
```

---

## What's Next

- **Phone access:** iOS Shortcut → Anthropic API → remote agent (Anthropic infra) → primary via scheduled Claude Code task
- **VS Code Remote-SSH:** Open primary's files directly in VS Code on secondary (`Remote-SSH: Connect to Host`)
- **Persistent sessions:** Use `tmux` on primary so sessions survive SSH disconnects

---

## Security

This repo includes a `pre-push` git hook that blocks pushes containing:
- `.env` files or credentials
- `node_modules/` or `dist/` artifacts
- Secrets detected by `git-secrets`

Install it after cloning:
```bash
cp hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
brew install git-secrets   # required dependency
```

---

## Files in This Repo

| File | Purpose | Run on |
|------|---------|--------|
| `primary-setup.sh` | Bootstrap primary machine | Primary |
| `secondary-setup.sh` | Bootstrap secondary machine | Secondary |
| `ssh-path-fix.sh` | Fix SSH PATH on primary | Secondary (runs remotely) |
| `hooks/pre-push` | Git pre-push secret scanner | Both (install into `.git/hooks/`) |
| `README.md` | This guide | — |
