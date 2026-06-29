# User's Guide: Getting the Most Out of Your Dual-Mac Claude Setup

This is a practical reference for daily use — not setup instructions (see README for that). Everything here assumes the Tailscale + SSH connection is live and Claude is authenticated on the primary.

---

## Quick Reference

```bash
# One-shot Claude prompt on primary
ssh <user>@primary "claude --print 'your prompt here'"

# Interactive Claude session on primary
ssh -t <user>@primary "claude"

# Claude inside a specific project on primary
ssh -t <user>@primary "cd ~/Claude/projects/<project> && claude"

# Check what's mounted (including external drive)
ssh <user>@primary "df -h | grep -v devfs"

# Check what's running on primary
ssh <user>@primary "ps aux | grep -E '(claude|node|python)' | grep -v grep"
```

Replace `<user>` with your primary machine username and `primary` with the Tailscale hostname or `100.x.y.z` IP.

---

## 1. Connecting

### Standard connection
```bash
ssh <user>@primary
```

Tailscale keeps the `100.x.y.z` address stable — you can also use the machine's Tailscale hostname if you've set one. Both work without being on the same Wi-Fi network.

### Fix a stale host key
If you see `Host key verification failed` after a macOS update on primary:
```bash
ssh-keygen -R primary          # by hostname
ssh-keygen -R 100.x.y.z        # by IP (run both if needed)
ssh -o StrictHostKeyChecking=accept-new <user>@primary "echo ok"
```

### Check Tailscale is up before connecting
```bash
tailscale status               # both machines should appear
tailscale ping primary         # direct connectivity check
```

---

## 2. Running Claude on Primary from Secondary

### One-shot prompts
Best for quick questions, file summaries, or scripted tasks:
```bash
ssh <user>@primary "claude --print 'explain what this does' < ~/Claude/projects/myproject/main.py"
```

Pipe local files from secondary into a primary Claude prompt:
```bash
cat ~/local-notes.md | ssh <user>@primary "claude --print 'summarise this'"
```

### Interactive sessions
Required for multi-turn conversation, file edits, or running Claude Code tools:
```bash
ssh -t <user>@primary "claude"
```

The `-t` flag is mandatory — without it Claude hangs waiting for a terminal that never comes.

### Starting inside a project
Claude Code picks up context from the working directory:
```bash
ssh -t <user>@primary "cd ~/Claude/projects/<project> && claude"
```

### Using a specific model
```bash
ssh <user>@primary "claude --model claude-opus-4-8 --print 'your prompt'"
```

---

## 3. Keeping Sessions Alive with tmux

SSH sessions die when your laptop sleeps or your network drops. Use `tmux` on primary to keep long Claude sessions running.

### Start a named session
```bash
ssh -t <user>@primary "tmux new-session -s work"
# Now inside tmux — start claude, run tasks, etc.
# Detach: Ctrl-B then D
```

### Reattach later
```bash
ssh -t <user>@primary "tmux attach -t work"
```

### List running sessions
```bash
ssh <user>@primary "tmux ls"
```

### Quick alias (add to your local ~/.zshrc)
```bash
alias gdeskwork='ssh -t <user>@primary "tmux new-session -A -s work"'
```

This creates the session if it doesn't exist, or reattaches if it does.

---

## 4. Working with Files

### Read a file on primary from secondary
```bash
ssh <user>@primary "cat ~/Claude/projects/<project>/README.md"
```

### Copy a file from primary to secondary
```bash
scp <user>@primary:~/Claude/projects/<project>/output.txt ~/Downloads/
```

### Copy a file from secondary to primary
```bash
scp ~/Downloads/draft.md <user>@primary:~/Claude/projects/<project>/
```

### Sync a whole directory (primary → secondary)
```bash
rsync -avz <user>@primary:~/Claude/projects/<project>/ ~/local-mirror/<project>/
```

### Edit a file on primary directly from secondary
VS Code with Remote-SSH extension makes this seamless:
1. Install the **Remote - SSH** extension in VS Code on secondary
2. `Cmd+Shift+P` → `Remote-SSH: Connect to Host` → `<user>@primary`
3. Open any folder on primary — edits happen in place, no copying needed

---

## 5. Accessing the External Drive

The 2TB external is mounted on primary at `/Volumes/ExternalDrive`.

### Browse it
```bash
ssh <user>@primary "ls '/Volumes/ExternalDrive/'"
```

### Read a file from it
```bash
ssh <user>@primary "cat '/Volumes/ExternalDrive/path/to/file.txt'"
```

### Copy from external drive to secondary
```bash
scp "<user>@primary:/Volumes/ExternalDrive/path/to/file" ~/Downloads/
```

### Run Claude against something on the external drive
```bash
ssh <user>@primary "claude --print 'summarise this document' < '/Volumes/ExternalDrive/docs/report.pdf'"
```

### Check drive health
```bash
ssh <user>@primary "df -h | grep 'ExternalDrive'"
# Expected: ~1.8Ti total, shows used/available
```

> **Note:** If the drive isn't showing up, it may have been ejected or gone to sleep. You'll need to physically reconnect it or wake it on primary — this can't be done remotely.

---

## 6. Project Workflows

### Typical session: pick up work on a primary project from the laptop

```bash
# 1. See what projects exist
ssh <user>@primary "ls ~/Claude/projects/"

# 2. Check git status on a project
ssh <user>@primary "cd ~/Claude/projects/<project> && git status && git log --oneline -5"

# 3. Open an interactive Claude session inside it
ssh -t <user>@primary "cd ~/Claude/projects/<project> && claude"

# 4. After Claude makes changes, commit from secondary
ssh <user>@primary "cd ~/Claude/projects/<project> && git add -A && git commit -m 'your message'"

# 5. Push to GitHub
ssh <user>@primary "cd ~/Claude/projects/<project> && git push"
```

### Run a dev server on primary and access it on secondary
Most dev servers bind to `localhost` by default, which means you can't reach them from secondary. Use SSH port forwarding:

```bash
# Forward primary's port 4321 to secondary's localhost:4321
ssh -L 4321:localhost:4321 <user>@primary "cd ~/Claude/projects/<project> && npm run dev"
```

Then open `http://localhost:4321` on secondary's browser — you're hitting primary's dev server.

One-liner version (start server separately, then forward):
```bash
ssh -N -L 4321:localhost:4321 <user>@primary
```

### Running a long build or task and checking back later

```bash
# Start in tmux so it survives disconnect
ssh -t <user>@primary "tmux new-session -d -s build 'cd ~/Claude/projects/<project> && npm run build > build.log 2>&1'"

# Check progress later
ssh <user>@primary "tail -f ~/Claude/projects/<project>/build.log"
# Ctrl-C to stop tailing (doesn't stop the build)
```

---

## 7. Monitoring Primary

### Quick health check
```bash
ssh <user>@primary "df -h / && uptime && sw_vers -productVersion"
```

### External drive status
```bash
ssh <user>@primary "df -h | grep -E 'Filesystem|ExternalDrive|disk[0-9]'"
```

### What's running
```bash
ssh <user>@primary "ps aux | grep -E '(claude|node|python|npm)' | grep -v grep"
```

### Check backup and health logs
```bash
ssh <user>@primary "tail -20 ~/Claude/monitoring/health-check.log"
ssh <user>@primary "tail -20 ~/Claude/monitoring/backup.log"
```

### Check the audit log
The `PostToolUse` hook logs every Bash, Write, and Edit tool call Claude makes on primary:
```bash
ssh <user>@primary "tail -20 ~/Claude/monitoring/audit.log"
```
Format: `[2026-06-29T20:22:03Z] TOOL=Bash`

### Run a manual backup
```bash
ssh <user>@primary "bash ~/Claude/monitoring/backup.sh"
```

---

## 8. Useful Aliases

Add these to `~/.zshrc` on secondary to save typing:

```bash
# Core connection
alias primary='ssh <user>@primary'
alias primaryt='ssh -t <user>@primary'

# Claude shortcuts
alias gclaude='ssh <user>@primary "claude --print"'
alias gclaudei='ssh -t <user>@primary "claude"'

# Work session (tmux + claude)
alias gwork='ssh -t <user>@primary "tmux new-session -A -s work"'

# Project shortcuts
alias gprojects='ssh <user>@primary "ls ~/Claude/projects/"'
alias gdrive='ssh <user>@primary "ls '"'"'/Volumes/ExternalDrive/'"'"'"'

# Monitoring
alias ghealth='ssh <user>@primary "tail -20 ~/Claude/monitoring/health-check.log"'
alias gdisk='ssh <user>@primary "df -h | grep -v devfs"'
```

After adding, run `source ~/.zshrc` to load them.

---

## 9. Troubleshooting

### `claude: command not found` over SSH
The `~/.zshenv` PATH fix isn't loaded. Re-run on primary:
```bash
ssh <user>@primary 'echo "eval \"\$(/usr/local/bin/brew shellenv zsh)\"" >> ~/.zshenv'
ssh <user>@primary 'echo "export PATH=\"/usr/local/bin:\$PATH\"" >> ~/.zshenv'
```

### SSH hangs or times out
Usually Tailscale dropped. Check from secondary:
```bash
tailscale status
tailscale ping 100.x.y.z
```
If primary doesn't appear, open the Tailscale app on primary and re-authenticate.

### Claude session dies when laptop sleeps
Use `tmux` (see section 3). Sessions on primary survive — just reattach when you reconnect.

### `Host key verification failed`
Primary's SSH fingerprint changed (OS update, reinstall). Fix:
```bash
ssh-keygen -R primary
ssh-keygen -R 100.x.y.z
ssh -o StrictHostKeyChecking=accept-new <user>@primary "echo reconnected"
```

### Interactive Claude immediately exits
Missing `-t` flag. Always use `ssh -t` for interactive sessions.

### External drive not visible
```bash
ssh <user>@primary "ls /Volumes/"
```
If it's missing, the drive needs to be physically reconnected or woken on primary — can't be done remotely.

### Port forwarding not working
Make sure the dev server is bound to `localhost` or `0.0.0.0`, not a specific IP. Check:
```bash
ssh <user>@primary "lsof -i :4321"
```

---

## 10. What's Next

- **Phone access:** iOS Shortcut → Anthropic API → scheduled remote agent → primary. Lets you trigger Claude tasks from your phone without SSH.
- **VS Code Remote-SSH:** Replaces `scp`/`rsync` for file editing — open primary's filesystem directly in your editor on secondary.
- **Persistent tmux layout:** Pre-configure a tmux session with windows for each project so one command drops you into your full working environment.
- **`tmux` on secondary too:** If you run long local tasks on secondary, same principle applies.
