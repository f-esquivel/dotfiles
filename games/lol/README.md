# League of Legends Configuration

This directory contains exported League of Legends keybindings and game settings.

## Files

- **PersistedSettings.json** - Keybindings, game settings, interface preferences
- **game.cfg** - Game configuration settings
- **input.ini** - Input and control settings
- **export-info.txt** - Metadata about the export

## Export Your Settings

Run this on your main machine to save your LoL configs:

```bash
~/dotfiles/scripts/lol-export.sh
```

This will:
1. Find your LoL installation
2. Copy config files to this directory
3. Create backups of any existing configs
4. Generate metadata about the export

## Import Settings to New Machine

After cloning your dotfiles on a new machine:

```bash
# Preview what would be imported
~/dotfiles/scripts/lol-import.sh --dry-run

# Import the configs
~/dotfiles/scripts/lol-import.sh
```

This will:
1. Find your LoL installation
2. Backup existing configs
3. Copy configs from dotfiles to LoL directory
4. Preserve your settings across machines

## Config File Locations

League of Legends stores configs in these locations on macOS:

```
~/Library/Application Support/Riot Games/League of Legends/Config/
~/Library/Preferences/Riot Games/League of Legends/Config/
/Applications/League of Legends.app/Contents/LoL/Config/
```

The scripts automatically detect the correct location.

## What's Included

### PersistedSettings.json
- All keybindings (abilities, items, camera, etc.)
- Game settings (audio, video, interface)
- Interface preferences (minimap, HUD)
- Accessibility options
- Chat settings

### game.cfg
- Graphics settings
- Performance options
- Network settings

### input.ini
- Mouse sensitivity
- Camera settings
- Input preferences

## Tips

- **Export regularly**: Run the export script after tweaking settings
- **Commit changes**: Add to git after exporting
  ```bash
  git add games/lol/
  git commit -m "Update LoL configs"
  git push
  ```
- **Test imports**: Use `--dry-run` first to preview changes
- **Keep backups**: Scripts automatically backup existing configs

## Troubleshooting

### LoL Not Found

Make sure:
1. League of Legends is installed
2. You've launched it at least once (creates config files)
3. It's in the standard installation location

### Settings Not Applying

1. Close League of Legends completely
2. Run the import script
3. Launch LoL again

### Restore from Backup

If import goes wrong, restore from the backup:

```bash
# Backups are in:
~/.lol-config-backup-TIMESTAMP/

# Or in dotfiles:
~/dotfiles/games/lol/backup-TIMESTAMP/
```

## Version Compatibility

These configs work across:
- ✅ Different macOS machines
- ✅ Different LoL versions (usually)
- ⚠️  May need tweaking after major LoL updates

## Privacy Note

**Warning**: Config files may contain:
- Summoner names
- Chat history preferences
- Friend list data

Review before committing to a public repository.
