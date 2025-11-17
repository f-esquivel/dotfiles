# Brewfile Organization Command

You are tasked with organizing and maintaining the Brewfile at `~/dotfiles/brew/Brewfile`.

## Your Task

1. Run `brew bundle dump --file=/tmp/Brewfile.new --force` to get currently installed packages
2. Compare with the existing organized Brewfile and identify new packages
3. Show detailed preview of changes that will be applied to the Brewfile
4. Ask for user confirmation using AskUserQuestion tool
5. If confirmed, apply changes to the Brewfile maintaining all organization
6. Show summary of what was changed

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
2. **Compare package declarations** (IMPORTANT - see "Common Pitfalls" below):
   - Extract package declarations from organized Brewfile (strip comments)
   - Use `comm` to find packages in new dump but not in organized Brewfile
   - Recommended command:
     ```bash
     grep -E '^(tap|brew|cask|vscode)' ~/dotfiles/brew/Brewfile | sed 's/#.*//' | sed 's/[[:space:]]*$//' | sort > /tmp/brewfile_current.txt
     comm -13 /tmp/brewfile_current.txt <(sort /tmp/Brewfile.new)
     ```
3. For each new package identified:
   - Determine the appropriate section based on package type
   - Format it with proper inline comment
   - Maintain alphabetical order within section
3. **Show detailed preview** to user:
   - List all new packages organized by section
   - Use markdown diff blocks (```diff) for visual syntax highlighting
   - Show 2-3 context lines (existing packages) before and after insertion point
   - Mark new packages with `+` prefix (renders in green)
   - Display exact formatted lines with comments
   - Choose diff format for populated sections, simple list for empty sections
4. **Request confirmation** using AskUserQuestion tool:
   - Ask: "Apply these changes to your Brewfile?"
   - Provide clear options: "Yes, apply changes" or "No, cancel"
   - Wait for user response
5. **Only if confirmed**, update the Brewfile:
   - Insert new packages in appropriate sections
   - Maintain all existing formatting and comments
   - Preserve alphabetical order within sections
6. Show final summary of what was changed

## Output Format

### Step 3: Preview Format

**IMPORTANT**: Use markdown diff blocks with syntax highlighting for visual clarity.

Show the preview in this format:

````
📦 Brewfile Update Preview

Found **X new packages** to add across **Y sections**

````

Then for each affected section, show a **diff-style comparison** showing context:

`````markdown
### 📂 CLI Tools & Utilities
**+2 packages**

```diff
  brew "bat"                  # Better cat with syntax highlighting
  brew "curl"                 # HTTP client
+ brew "newtool"              # Description of what it does
+ brew "another-tool"         # Another description
  brew "ripgrep"              # Fast grep alternative
```

### 📂 VSCode Extensions / AI Assistants
**+1 package**

```diff
  vscode "catppuccin.catppuccin-vsc"           # Catppuccin theme
+ vscode "newext.extension"                    # Extension description
  vscode "eleanorjboyd.pythonview-vscode"      # Python testing
```

---

📊 **Summary**: X packages will be added to Y sections
`````

**Guidelines for context lines:**
- Show 2-3 existing packages before and after the insertion point
- Use `+` prefix for new packages (will render in green in diff syntax)
- Use no prefix for existing packages (context lines)
- Include the full formatted line with comments
- Show packages in alphabetical order

**Alternative: Simple list format** (use when adding many packages or to empty sections):

```
📦 Brewfile Update Preview

✨ **New Packages** (X total)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 📦 CLI Tools & Utilities
✅ `brew "newtool"`              # Description of what it does
✅ `brew "another-tool"`         # Another description

### 📦 VSCode Extensions / AI Assistants
✅ `vscode "newext.extension"`   # Extension description

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Summary: X packages → Y sections
```

**Choose the appropriate format:**
- Use **diff format** when there are existing packages in the section (shows insertion point clearly)
- Use **simple list** when adding to new/empty sections or when there are 10+ new packages

### Step 4: Confirmation

After showing the preview, use AskUserQuestion tool with:
- Question: "Apply these changes to your Brewfile?"
- Header: "Confirm"
- Options:
  - "Yes, apply changes" - "Add all new packages to Brewfile with proper formatting"
  - "No, cancel" - "Don't modify the Brewfile"
- multiSelect: false

### Step 6: Final Summary Format

After successfully applying changes, show:

```
✅ Brewfile Updated Successfully!

📊 Changes Applied:
  ✨ CLI Tools & Utilities: +2 packages
  ✨ VSCode Extensions / AI Assistants: +1 package

📝 Total: X packages added across Y sections
📂 File: ~/dotfiles/brew/Brewfile
```

If packages were removed (if ever supported in future):
```diff
📊 Changes Applied:
+ Added:   2 packages
- Removed: 1 package
```

## Important Rules

- NEVER use `brew bundle dump --force` directly on the organized Brewfile
- ALWAYS dump to `/tmp/Brewfile.new` first, then compare
- ALWAYS show detailed preview before making any changes
- ALWAYS use AskUserQuestion tool for confirmation - NEVER proceed without user approval
- ONLY modify the Brewfile if user confirms "Yes, apply changes"
- ALWAYS preserve the existing organization and comments
- ALWAYS add appropriate inline comments for new packages
- NEVER remove packages without explicit instruction
- ALWAYS maintain alphabetical order within sections
- If user selects "No, cancel", exit gracefully without modifying any files

## Common Pitfalls

### ❌ Incorrect Comparison Method

**Problem**: Using `diff` on the organized Brewfile (with comments) vs new dump (without comments) will incorrectly report all existing packages as "different" even when they're the same.

```bash
# ❌ WRONG - This will fail because of comment differences
diff -u <(grep -E '^(tap|brew|cask)' ~/dotfiles/brew/Brewfile | sort) <(sort /tmp/Brewfile.new)
```

**Why it fails:**
- Organized Brewfile: `brew "bat"              # Better cat with syntax highlighting`
- New dump: `brew "bat"`
- `diff` sees these as different lines due to the comment

### ✅ Correct Comparison Method

**Solution**: Strip comments from the organized Brewfile before comparing:

```bash
# ✅ CORRECT - Strip comments first, then compare
grep -E '^(tap|brew|cask|vscode)' ~/dotfiles/brew/Brewfile | \
  sed 's/#.*//' | \              # Remove everything after #
  sed 's/[[:space:]]*$//' | \    # Remove trailing whitespace
  sort > /tmp/brewfile_current.txt

# Find packages in new dump that aren't in current Brewfile
comm -13 /tmp/brewfile_current.txt <(sort /tmp/Brewfile.new)
```

**How it works:**
1. Extract package declarations from organized Brewfile
2. Remove inline comments with `sed 's/#.*//'`
3. Remove trailing spaces with `sed 's/[[:space:]]*$//'`
4. Sort and save to temp file
5. Use `comm -13` to find lines in new dump but not in current Brewfile

**Example output** (only truly new packages):
```
cask "claude-code"
cask "notion"
cask "orbstack"
cask "postman"
```

### 🔍 Verification Tip

Always verify your comparison results make sense:
- If you see packages that are obviously already in the Brewfile, your comparison method is wrong
- Expected result: Only packages that were recently installed with `brew install` or `brew install --cask`
- Use `brew list` and `brew list --cask` to manually verify if uncertain
