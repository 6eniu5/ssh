# Known Issues — Fonts

## WezTerm cannot find "Cascadia Code Light"

**Status:** Fixed (applied in `6eniu5/esetup`: `dotfiles/wezterm/.config/wezterm/wezterm.lua` — family `Cascadia Code` with `weight = "Light"`).  
**Affects:** WezTerm after initial `setup.sh` + `stow` (before fix)

### Error

WezTerm repeatedly logs on startup:

```
Unable to load a font specified by your font=wezterm.font('Cascadia Code
Light', {weight="Regular", stretch='Normal', style=Normal}) configuration.
Fallback(s) are being used instead, and the terminal may not render as
intended. See https://wezfurlong.org/wezterm/config/fonts.html for more
information
```

### Root cause

The dotfiles wezterm config (`wezterm/.config/wezterm/wezterm.lua`)
specifies the font family as a literal string:

```lua
font = wezterm.font_with_fallback({
  "Cascadia Code Light",
  "Vazir Code Hack",
  "MesloLGS NF",
})
```

Homebrew's `font-cascadia-code` cask (version 2407.24) installs **variable
font** files:

```
~/Library/Fonts/CascadiaCode.ttf
~/Library/Fonts/CascadiaCodeItalic.ttf
```

The font family name registered by these files is **"Cascadia Code"**, not
"Cascadia Code Light". "Light" is a *weight axis value* inside the
variable font, not a separate family. WezTerm cannot resolve a family
literally named "Cascadia Code Light" and falls back to its default font.

### Fix options

**Option A — Use the correct family name with an explicit weight
(recommended):**

```lua
font = wezterm.font_with_fallback({
  { family = "Cascadia Code", weight = "Light" },
  "Vazir Code Hack",
  "MesloLGS NF",
})
```

This tells WezTerm to look up the "Cascadia Code" variable font and
select the Light weight axis.

**Option B — Use the family name without specifying weight:**

```lua
font = wezterm.font_with_fallback({
  "Cascadia Code",
  "Vazir Code Hack",
  "MesloLGS NF",
})
```

This uses the Regular weight. Simpler, but loses the Light aesthetic.

**Option C — Install the static (non-variable) font package:**

Microsoft distributes static `.ttf` builds where each weight is a
separate file/family. These are available from the
[Cascadia Code releases](https://github.com/microsoft/cascadia-code/releases)
page. The static `CascadiaCodeLight.ttf` would register as "Cascadia
Code Light" and match the current config as-is.

### Where to apply the fix

The wezterm config lives in:

- **Source (esetup):** `esetup/dotfiles/wezterm/.config/wezterm/wezterm.lua`
- **Stowed target:** `~/dotfiles/wezterm/.config/wezterm/wezterm.lua`
- **Symlinked to:** `~/.config/wezterm/wezterm.lua`

The source in `esetup/dotfiles/` has been updated; re-run `stow` or manually sync the live config under `~/6eniu5/dotfiles` / `~/.config/wezterm` if needed.
