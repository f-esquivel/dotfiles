# SSH Configuration

This directory contains SSH configuration for managing multiple SSH keys across different hosts.

## File Structure

```
ssh/
├── config                    # Main SSH config (safe to commit)
├── config.local              # Machine-specific keys (git-ignored)
├── config.local.template     # Template for config.local
└── config.template           # Alternative template for full config
```

## Setup on a New Machine

1. **Symlink the main config:**
   ```bash
   ln -sf ~/dotfiles/ssh/config ~/.ssh/config
   ```

2. **Create your local config:**
   ```bash
   cp ~/dotfiles/ssh/config.local.template ~/dotfiles/ssh/config.local
   ```

3. **Edit `config.local` with your SSH key paths:**
   ```bash
   # Update IdentityFile paths to match your machine's keys
   vim ~/dotfiles/ssh/config.local
   ```

## How It Works

- **`config`** - Contains host configurations (hostnames, ports, users) that are the same across all machines
- **`config.local`** - Contains machine-specific IdentityFile paths that vary per machine
- SSH reads `config` which then includes `config.local` using the `Include` directive

## Adding a New Host

1. Add the host configuration to `config` (without IdentityFile)
2. Add the IdentityFile directive to `config.local`

Example:

**In `config`:**
```ssh-config
Host myserver
  HostName server.example.com
  User myusername
  # IdentityFile defined in config.local
```

**In `config.local`:**
```ssh-config
Host myserver
  IdentityFile ~/.ssh/id_myserver
```

## Current Hosts

- **gitlab.com** - GitLab via alternate port (443)
- **github.com** - Personal GitHub account
- **dgh** - Work GitHub account (designli)
