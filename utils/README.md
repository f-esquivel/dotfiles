# Utilities

This directory contains utility scripts and configuration files for development tools.

## Configuration Files

### `.hushlogin`
Suppresses the system "Last login" message when opening a new terminal session.

**How it works:** The mere presence of this file in `$HOME` is enough to suppress the login message - the content doesn't matter.

**Installation:** Symlinked to `~/.hushlogin` by `install.sh`

---

### `.npmrc`
NPM configuration file with opinionated settings for package management.

**Key settings:**
- `save-exact=true` - Saves exact versions instead of ranges (e.g., `1.0.0` instead of `^1.0.0`)
- `package-lock=true` - Uses package-lock.json for deterministic installs
- `progress=true` - Shows progress bar during installation
- `prefer-offline=true` - Prefers offline cache when available for better performance
- `audit=true` - Automatically runs security audit after install
- `registry=https://registry.npmjs.org/` - Default NPM registry (explicit)

**Installation:** Symlinked to `~/.npmrc` by `install.sh`

---

### `.lazy-nvm.sh`
Lazy-loading wrapper for NVM (Node Version Manager). This significantly improves shell startup time by deferring NVM initialization until a Node-related command is actually used.

**Performance impact:** Reduces shell startup time from ~500ms to ~50ms by not loading NVM immediately.

**Trigger commands:** The wrapper automatically loads NVM when you first use:
- `nvm` - NVM itself
- `node` - Node.js runtime
- `npm` - Node package manager
- `npx` - NPM package runner
- `nest` - NestJS CLI
- `lerna` - Lerna monorepo tool

**How it works:**
1. Creates placeholder functions for the above commands
2. When called, removes placeholders and loads actual NVM
3. Re-runs the original command with full NVM environment

**Installation:** Sourced by `.zshrc.user` at line 49

---

## Executable Scripts

### `gcp-sql-proxy.sh`
Interactive utility for connecting to GCP Cloud SQL instances via the Cloud SQL Auth Proxy.

**Features:**
- Lists all SQL instances from your current GCP project
- Interactive selection using `fzf` (fuzzy finder)
- Auto-detects database type (PostgreSQL, MySQL, SQL Server)
- Suggests appropriate default ports based on database type
- Checks and prompts for Application Default Credentials (ADC) setup if needed
- Automatically downloads and installs `cloud-sql-proxy` binary to `~/.local/bin`
- No sudo required (installs to user directory)

**Requirements:**
- `gcloud` (Google Cloud SDK) - for listing instances and authentication
- `fzf` (fuzzy finder) - for interactive instance selection
- Active GCP project configured: `gcloud config set project PROJECT_ID`
- Application Default Credentials (ADC) - the script will prompt you to set this up if needed

**Installation location:**
- Script: `~/.dotfiles/utils/gcp-sql-proxy.sh`
- Binary: `~/.local/bin/cloud-sql-proxy` (same location as JetBrains Toolbox shell scripts)
- Alias: `gcpsql` (defined in `.zshrc.user`)

**Usage:**

```bash
# Interactive mode - lists instances and prompts for port (recommended)
gcpsql

# Interactive with custom port specified
gcpsql --port 5433

# Direct connection using instance connection name
gcpsql --instance my-project:us-central1:my-instance --port 5432

# Show help and examples
gcpsql --help
```

**Default ports by database type:**
- PostgreSQL: `5432`
- MySQL: `3306`
- SQL Server: `1433`

**After starting the proxy:**

Once the proxy is running, you can connect using your preferred database client:

```bash
# PostgreSQL example
psql -h localhost -p 5432 -U your_user -d your_database

# MySQL example
mysql -h localhost -P 3306 -u your_user -p your_database

# Or use connection strings
postgresql://user:pass@localhost:5432/database
mysql://user:pass@localhost:3306/database
```

**Troubleshooting:**

If you get an ADC authentication error:
```bash
# The script will prompt you, or you can run manually:
gcloud auth application-default login
```

If the binary fails to download:
```bash
# Manually download for your architecture (Apple Silicon):
curl -o ~/.local/bin/cloud-sql-proxy \
  https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.1/cloud-sql-proxy.darwin.arm64
chmod +x ~/.local/bin/cloud-sql-proxy
```

---

## Adding New Utilities

To add a new utility to this directory:

### For Configuration Files

1. **Create the file** in `utils/`
   ```bash
   vim utils/.myconfig
   ```

2. **Add symlink logic** to `install.sh`
   ```bash
   safe_symlink "$DOTFILES_DIR/utils/.myconfig" "$HOME/.myconfig" "myconfig"
   ```

3. **Document it** in this README

### For Executable Scripts

1. **Create the script** in `utils/`
   ```bash
   vim utils/my-script.sh
   chmod +x utils/my-script.sh
   ```

2. **(Optional) Add an alias** in `zsh/.zshrc.user`
   ```bash
   echo 'alias myscript="$DOTFILES_DIR/utils/my-script.sh"' >> zsh/.zshrc.user
   ```

3. **Reload shell** to enable the alias
   ```bash
   rzsh  # or: source ~/.zshrc
   ```

4. **Document it** in this README

### Example Workflow

```bash
# 1. Create a new utility script
cat > utils/my-tool.sh << 'EOF'
#!/usr/bin/env bash
echo "Hello from my tool!"
EOF

# 2. Make it executable
chmod +x utils/my-tool.sh

# 3. Add alias for easy access
echo 'alias mytool="$DOTFILES_DIR/utils/my-tool.sh"' >> zsh/.zshrc.user

# 4. Reload shell
rzsh

# 5. Use it
mytool  # Output: Hello from my tool!

# 6. Commit changes
git add utils/my-tool.sh zsh/.zshrc.user utils/README.md
git commit -m "feat(utils): add my-tool utility script"
```

---

## Directory Structure

```
utils/
├── README.md              # This file
├── .hushlogin             # Suppress login message (symlinked to ~/)
├── .npmrc                 # NPM configuration (symlinked to ~/)
├── .lazy-nvm.sh           # NVM lazy-loader (sourced by .zshrc.user)
└── gcp-sql-proxy.sh       # GCP SQL Proxy utility (executable, aliased as 'gcpsql')
```

All configuration files (`.hushlogin`, `.npmrc`) are symlinked to `$HOME` during installation via `install.sh`.
