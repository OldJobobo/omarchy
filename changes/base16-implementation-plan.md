# Base16 Implementation Plan

## Goal
Migrate Omarchy theme colors from ANSI-first (`color0`-`color15`) to Base16-first (`base00`-`base0F`) without breaking existing templates or theme switching.

## Scope
- `bin/omarchy-theme-set-templates`
- `default/themed/*.tpl`
- `themes/*/colors.toml`
- `config/omarchy/themed/alacritty.toml.tpl.sample`

## Status
- Owner: TBD
- Branch: `base16-colors-and-templates`
- State: Planned
- Target release: TBD

## Work Sets

### Set 1: Schema Spec and Freeze
- [x] Create `default/themed/COLORS_SCHEMA.md`
- [x] Define required semantic keys:
  - `accent`, `cursor`, `foreground`, `background`, `selection_foreground`, `selection_background`
- [x] Define required Base16 keys:
  - `base00`..`base0F`
- [x] Define transitional support for `color0`..`color15` as deprecated
- [x] Document canonical Base16 -> ANSI compatibility mapping

Acceptance criteria:
- [x] One documented mapping is approved and treated as source of truth.

### Set 2: Template Engine Compatibility Layer
- [x] Update `bin/omarchy-theme-set-templates` to read Base16 keys
- [x] Auto-export derived `color0`..`color15` when ANSI keys are missing
- [x] Preserve `{{ key }}`, `{{ key_strip }}`, and `{{ key_rgb }}` behavior
- [x] Add validation error if neither full Base16 nor full ANSI palette exists

Acceptance criteria:
- [x] Existing themes render unchanged.
- [x] A Base16-only theme renders without unresolved placeholders.

### Set 3: Migrate Stock Templates to Base16 Tokens
- [x] Update `default/themed/alacritty.toml.tpl`
- [x] Update `default/themed/kitty.conf.tpl`
- [x] Update `default/themed/ghostty.conf.tpl`
- [x] Update `default/themed/obsidian.css.tpl`
- [x] Update `default/themed/btop.theme.tpl`
- [x] Update `default/themed/hyprland-preview-share-picker.css.tpl`
- [x] Keep semantic placeholders (`accent`, `background`, etc.) where they remain appropriate

Acceptance criteria:
- [x] `rg "\{\{\s*color[0-9]" default/themed` returns no matches.

### Set 4: Migrate Theme Files
- [x] Add `base00`..`base0F` to each `themes/*/colors.toml`
- [x] Keep semantic keys explicit in each theme
- [x] Optionally keep `color0`..`color15` during transition release

Acceptance criteria:
- [x] All 16 stock themes include full Base16 keyset.

### Set 5: Update User Template Docs
- [x] Update `config/omarchy/themed/alacritty.toml.tpl.sample`
- [x] Document Base16-first variables
- [x] Document ANSI compatibility as transitional/deprecated

Acceptance criteria:
- [x] User-facing docs no longer describe ANSI keys as primary API.

### Set 6: Validation and Regression
- [x] Add a validation script/check for required theme keys
- [x] Add unresolved-placeholder check after template generation
- [x] Test at least one dark and one light theme via `omarchy-theme-set <theme>`
- [x] Verify generated theme artifacts for terminal, Waybar, Walker, and SwayOSD

Acceptance criteria:
- [x] No unresolved placeholders in generated files.
- [x] Theme switch flow remains healthy.

### Set 7: Rollout and Cleanup
- [ ] Release N: Base16 primary + ANSI compatibility on + deprecation notice
- [ ] Release N+1: remove ANSI compatibility if no blockers
- [ ] Add migration (if needed) for installed user-side theme copies

Acceptance criteria:
- [ ] No active breakage reports tied to color key mismatch.

## Compatibility Mapping (Canonical)
Use this mapping for transitional compatibility when deriving ANSI slots from Base16:

- `color0 = base00`
- `color1 = base08`
- `color2 = base0B`
- `color3 = base0A`
- `color4 = base0D`
- `color5 = base0E`
- `color6 = base0C`
- `color7 = base05`
- `color8 = base03`
- `color9 = base08`
- `color10 = base0B`
- `color11 = base0A`
- `color12 = base0D`
- `color13 = base0E`
- `color14 = base0C`
- `color15 = base07`

## Definition of Done
- [ ] Stock templates consume Base16 directly.
- [ ] Stock themes provide full Base16 palettes.
- [ ] Theme set flow (`omarchy-theme-set` -> `omarchy-theme-set-templates`) works without unresolved tokens.
- [ ] User template docs reflect Base16-first usage.
