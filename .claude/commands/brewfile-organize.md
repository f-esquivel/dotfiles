# Brewfile Organization Command

You are tasked with organizing and maintaining the Brewfile at `~/dotfiles/brew/Brewfile`.

## Your Task

1. Run `brew bundle dump --file=/tmp/Brewfile.new --force` to get currently installed packages
2. Compare with the existing organized Brewfile
3. Identify new packages that need to be added
4. Add them to the appropriate sections while preserving the existing organization
5. Show me what changed

## Brewfile Format Requirements

### File Structure

```ruby
# =============================================================================
# Homebrew Bundle File
# =============================================================================
# Install all packages: brew bundle install --file=~/dotfiles/brew/Brewfile
# Update Brewfile:      brew bundle dump --file=~/dotfiles/brew/Brewfile --force
# Cleanup packages:     brew bundle cleanup --file=~/dotfiles/brew/Brewfile

# -----------------------------------------------------------------------------
# Section Name
# -----------------------------------------------------------------------------

# Subsection (optional)
package "name"              # Inline comment explaining what it does
```

### Section Organization

Organize packages into these sections in this order:

1. **Taps** - Third-party repositories
2. **CLI Tools & Utilities** - Command-line tools
3. **Development Tools** - Dev-specific CLI tools
4. **Databases & Data Tools** - Database systems and tools
5. **PHP & Composer** - PHP and related tools (if applicable)
6. **Runtime Environments** - Language runtimes (Node, Bun, etc.)
7. **GUI Applications (Casks)** - Split into subsections:
   - Development
   - Cloud & DevOps
   - Browsers
   - Utilities
   - Fonts
8. **VSCode Extensions** - Split into subsections:
   - Themes & UI
   - Code Intelligence
   - AI Assistants
   - Language Support
   - Tools & Utilities
9. **Go Packages** - Go-specific packages
10. **Other** - Any packages that don't fit above categories

### Formatting Rules

- Use `# =====` for main header
- Use `# -----` for section dividers
- Add inline comments for every package explaining what it does
- Keep comments aligned where possible (use spaces to align after package name)
- Sort packages alphabetically within each section
- One blank line between sections
- No blank lines within a section

### Comments Guidelines

- **Taps**: No inline comments needed
- **Brews**: Brief description of what the tool does
  - Good: `# Better cat with syntax highlighting`
  - Bad: `# cat replacement`
- **Casks**: Brief app description
  - Good: `# Terminal emulator`
  - Bad: `# A terminal`
- **VSCode**: Short description or leave blank if name is clear
  - Good: `# Grammar checker` (for harper)
  - Blank if obvious: `vscode "golang.go"` (no comment needed)

### Special Cases

- Packages with options should be on one line:
  ```ruby
  brew "postgresql@15", restart_service: :changed # PostgreSQL database
  brew "php@8.2", restart_service: :changed, link: true
  ```

- Tapped packages should include tap name:
  ```ruby
  brew "oven-sh/bun/bun"  # Fast JavaScript runtime
  ```

## Workflow

1. Extract all packages from `/tmp/Brewfile.new`
2. For each package type (tap, brew, cask, vscode, go):
   - Check if it exists in current Brewfile
   - If missing, determine the appropriate section
   - Format it with proper comment
3. Present changes to user:
   - Show what will be added
   - Show which section it belongs to
   - Ask for confirmation before updating
4. Update the Brewfile maintaining all formatting

## Output Format

Show me:
```
📦 New packages to add:

[CLI Tools & Utilities]
  brew "newtool"              # Description here

[VSCode Extensions / AI Assistants]
  vscode "newext.extension"   # Description here

Would you like me to add these to your Brewfile?
```

## Important Rules

- NEVER use `brew bundle dump --force` directly on the organized Brewfile
- ALWAYS preserve the existing organization and comments
- ALWAYS ask before making changes
- ALWAYS add appropriate inline comments for new packages
- NEVER remove packages without explicit instruction
- ALWAYS maintain alphabetical order within sections
