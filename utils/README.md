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
- `yarn` - Node package manager

**How it works:**
1. Creates placeholder functions for the above commands
2. When called, removes placeholders and loads actual NVM
3. Re-runs the original command with full NVM environment

**Installation:** Sourced by `.zshrc.user` at line 49

---

## Executable Scripts

### `gcp-sql-proxy.sh`
Utility for connecting to GCP Cloud SQL instances via the Cloud SQL Auth Proxy.

Reference an instance three ways: by **profile name** from a registry (recommended), by **interactive pick**, or by **raw connection name**.

**Features:**
- **Named profiles** — `gcpsql be-test` resolves a short name to an instance + port from a registry (fast, offline, no `gcloud` call)
- **Aliases** — each profile can carry comma-separated aliases; `gcpsql bt` works the same as `gcpsql be-test`
- **Tab completion** — `gcpsql <tab>` completes profile names, aliases, and the `ls` subcommand (see `_gcpsql` in `.zshrc.user`)
- **Production guard** — profiles tagged `env=prod` require a typed `yes` confirmation before connecting
- Interactive fzf picker over the registry (`gcpsql` with no args)
- gcloud-API fallback when the registry is empty (lists instances from the current project)
- Auto-detects database type and default ports on the gcloud path (PostgreSQL, MySQL, SQL Server)
- Checks and prompts for Application Default Credentials (ADC) setup if needed
- Automatically downloads and installs `cloud-sql-proxy` binary to `~/.local/bin` (no sudo)

**Instance registry:**

Predefined instances live in a whitespace-separated table, **outside** the repo so machine-specific connection names are never committed:

```
$GCP_SQL_PROXY_REGISTRY   # default: ~/.config/gcp-sql-proxy/instances.tsv
```

`install.sh` seeds it from `utils/gcp-sql-instances.template` (never overwriting an existing file). Format — one profile per line:

```
# names           instance_connection_name                  port   env
be-test,bt        your-project:us-central1:my-backend-test  5436   test
be-prod,bp        your-project:us-central1:my-backend       5446   prod
```

Columns: `names` (comma-separated — first is canonical, the rest are aliases; all are usable and tab-complete, e.g. `gcpsql bt`), `inst` (`project:region:instance`), `port` (local bind port), `env` (optional — `prod` triggers the confirmation prompt). Add an instance = one line; no shell aliases needed.

**Requirements:**
- Application Default Credentials (ADC) — always required; the script prompts to set this up if missing
- `cloud-sql-proxy` binary — auto-downloaded to `~/.local/bin` on first run (no action needed)
- `fzf` (fuzzy finder) — only for the interactive picker (`gcpsql` with no args); not needed when calling a profile/alias directly
- `gcloud` (Google Cloud SDK) — only for the empty-registry fallback that lists instances from the current project; not needed for registry-based connections

**Installation location:**
- Script: `~/.dotfiles/utils/gcp-sql-proxy.sh`
- Binary: `~/.local/bin/cloud-sql-proxy` (same location as JetBrains Toolbox shell scripts)
- Registry: `~/.config/gcp-sql-proxy/instances.tsv` (seeded by `install.sh`, never committed)
- Alias + completion: `gcpsql` and `_gcpsql` (defined in `.zshrc.user`)

**Usage:**

```bash
# Connect via a registered profile or its alias (recommended) — tab-completes
gcpsql be-test        # canonical name
gcpsql bt             # alias for the same profile

# List registered profiles
gcpsql ls

# Interactive: fzf-pick a profile from the registry (or gcloud if empty)
gcpsql

# Raw connection using an instance connection name (no registry needed)
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
├── gcp-sql-proxy.sh       # GCP SQL Proxy utility (executable, aliased as 'gcpsql')
└── gcp-sql-instances.template  # Registry scaffold (seeded to ~/.config/gcp-sql-proxy/)
```

All configuration files (`.hushlogin`, `.npmrc`) are symlinked to `$HOME` during installation via `install.sh`.
