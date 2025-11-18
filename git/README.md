# Git Configuration

This directory contains Git configuration files with support for **context-based identities** using Git's conditional includes feature.

## Overview

The Git configuration in this dotfiles setup allows you to:
- Use different Git identities (name, email, signing keys) based on project directory
- Keep work/client email addresses private (git-ignored)
- Easily switch contexts without manual configuration per repo

## Files

- **`.gitconfig`** - Main Git configuration (tracked in git)
  - Contains shared aliases, settings, and conditional include directives
  - Defines your default Git identity

- **`.gitconfig.context.template`** - Template for creating new contexts (tracked in git)
  - Copy this to create new context-specific configurations

- **`.gitconfig.*`** - Context-specific configurations (git-ignored)
  - Create as many contexts as you need
  - Automatically git-ignored to keep sensitive data private

## How Conditional Includes Work

Git's `includeIf` directive allows you to conditionally include configuration files based on the repository path:

```gitconfig
[includeIf "gitdir:~/Documents/Dev/work/"]
    path = ~/.dotfiles/git/.gitconfig.work
```

When you run Git commands in a directory matching the pattern:
1. Git reads your main `.gitconfig`
2. Git checks if the current directory matches any `includeIf` patterns
3. If it matches, Git includes the specified config file
4. Settings in the included file override the main config

## Setup

### Create Your First Context

To create a context for a specific directory (e.g., work projects, client projects):

```bash
# 1. Copy the template
cd ~/.dotfiles/git
cp .gitconfig.context.template .gitconfig.work

# 2. Edit with context-specific identity
vim .gitconfig.work
# Update the name and email fields with your work identity

# 3. Add conditional include to main .gitconfig
vim .gitconfig

# Add this section (uncomment and modify one of the examples):
[includeIf "gitdir:~/Documents/Dev/work/"]
    path = ~/.dotfiles/git/.gitconfig.work
```

## Testing Your Setup

### Verify Which Config is Active

```bash
# Go to a directory
cd ~/Documents/Dev/work/some-project

# Check the effective email
git config user.email

# Check all user settings
git config --list | grep user

# Or use the whoami alias
git whoami
```

### Test All Contexts

```bash
# Default (anywhere outside special directories)
cd ~/Documents/random-project
git config user.email
# Should show: your default email (configured in main .gitconfig)

# Work context (if you set one up)
cd ~/Documents/Dev/work/some-project
git config user.email
# Should show: your work email (configured in .gitconfig.work)
```

### Debug Configuration Loading

```bash
# Show where Git is loading config from
git config --list --show-origin | grep user

# Show the effective configuration with sources
git config --list --show-origin --show-scope
```

## Common Patterns

### Pattern: All Subdirectories

```gitconfig
# Applies to ~/Documents/Dev/work/ and ALL subdirectories
[includeIf "gitdir:~/Documents/Dev/work/"]
    path = ~/.dotfiles/git/.gitconfig.work
```

### Pattern: Specific Directory Only

```gitconfig
# Applies only to repos directly in ~/Documents/Dev/work/
# (not nested subdirectories)
[includeIf "gitdir:~/Documents/Dev/work/**"]
    path = ~/.dotfiles/git/.gitconfig.work
```

### Pattern: Multiple Organizations

```gitconfig
# Work
[includeIf "gitdir:~/Documents/Dev/work/"]
    path = ~/.dotfiles/git/.gitconfig.work

# Client A
[includeIf "gitdir:~/Documents/Dev/client-a/"]
    path = ~/.dotfiles/git/.gitconfig.client-a

# Client B
[includeIf "gitdir:~/Documents/Dev/client-b/"]
    path = ~/.dotfiles/git/.gitconfig.client-b

# Open source
[includeIf "gitdir:~/Documents/Dev/oss/"]
    path = ~/.dotfiles/git/.gitconfig.opensource
```

## Aliases

The following Git aliases are available (from `.gitconfig`):

| Alias | Command | Description |
|-------|---------|-------------|
| `git l` | `log --pretty=oneline -n 20 --graph --abbrev-commit` | Pretty commit log |
| `git s` | `status -s` | Short status |
| `git d` | `diff-index --quiet HEAD -- \|\| git --no-pager diff --patch-with-stat` | Diff with stats |
| `git go` | `checkout -b "$1" 2> /dev/null \|\| checkout "$1"` | Switch/create branch |
| `git tags` | `tag -l` | List tags |
| `git branches` | `branch --all` | List all branches |
| `git remotes` | `remote --verbose` | List remotes |
| `git aliases` | `config --get-regexp alias` | List all aliases |
| `git dm` | Delete merged branches | Remove merged branches |
| `git whoami` | `config user.email` | Show current email |

## Troubleshooting

### Email Not Changing

**Problem**: `git config user.email` still shows the default email in a work directory.

**Solutions**:
1. Verify the path pattern matches:
   ```bash
   # If your repo is at ~/Documents/Dev/work/my-project
   # Your includeIf should use "gitdir:~/Documents/Dev/work/"
   ```

2. Check the path to the context file is correct:
   ```bash
   # The path should point to the actual file location
   cat ~/.dotfiles/git/.gitconfig.work
   ```

3. Ensure you're in a Git repository:
   ```bash
   git rev-parse --git-dir
   # If this errors, you're not in a Git repo
   ```

4. Check for path expansion issues:
   ```bash
   # Use full path instead of ~
   [includeIf "gitdir:/Users/yourname/Documents/Dev/work/"]
       path = /Users/yourname/.dotfiles/git/.gitconfig.work
   ```

### Context File Not Found

**Problem**: Git complains it can't find the context file.

**Solution**: Verify the path in the `includeIf` directive points to the actual file location:
```bash
ls -la ~/.dotfiles/git/.gitconfig.work
# If file doesn't exist, create it from template
cp ~/.dotfiles/git/.gitconfig.context.template ~/.dotfiles/git/.gitconfig.work
```

### Changes Not Applying

**Problem**: Made changes to context file but they don't apply.

**Solutions**:
1. Git caches config - try in a new terminal
2. Verify file syntax:
   ```bash
   git config --file ~/.dotfiles/git/.gitconfig.work --list
   ```
3. Check file permissions:
   ```bash
   chmod 644 ~/.dotfiles/git/.gitconfig.work
   ```

## Security Notes

- **Context files are git-ignored**: `.gitconfig.*` files (except `.template` files) are automatically ignored
- **Never commit work emails**: Keep sensitive identity information in `.gitconfig.*` files
- **Template files are safe**: `.gitconfig.context.template` is tracked and contains no real data
- **Main config is public**: `.gitconfig` is tracked in git, so only put shareable info there

## Advanced: GPG Signing Per Context

You can configure different GPG keys for different contexts:

```gitconfig
# In .gitconfig.work
[user]
    email = work@company.com
    signingkey = WORK_GPG_KEY_ID

[commit]
    gpgsign = true

# In .gitconfig.personal
[user]
    email = personal@gmail.com
    signingkey = PERSONAL_GPG_KEY_ID

[commit]
    gpgsign = true
```

## Resources

- [Git Conditional Includes Documentation](https://git-scm.com/docs/git-config#_conditional_includes)
- [Git Config Documentation](https://git-scm.com/docs/git-config)
