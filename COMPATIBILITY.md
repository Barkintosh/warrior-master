# Compatibility research - World of Warcraft Forever

Research record for Warrior Master. Carried out on 2026-11-08 by reading files only. The game was never launched, attached to or automated.

## 1. Target client

| Item | Value | Source |
|---|---|---|
| Product | World of Warcraft Forever (`wowf`) | `_forever_/.flavor.info`, `.build.info` |
| Client version | 1.60.1.70862 | `.build.info` of the local install |
| Interface number | **16001** | TOC files of installed Forever addons; Blizzard UI source |
| Engine | Modern (Midnight 12.x) engine running Classic-era content | Blizzard UI source, `Blizzard_*` addons |
| Project ID | `WOW_PROJECT_CAMELOT` (18) | AtlasLootClassic, community notes |
| TOC suffixes in use | `_Camelot.toc`, `_Forever.toc` | Installed addons |

Warrior Master ships a single `WarriorMaster.toc` with `## Interface: 16001`. The base TOC loads when no flavor-specific TOC exists, so no suffix file is needed.

## 2. Sources used

1. **Blizzard's UI source for the exact build**: the public mirror `Gethe/wow-ui-source`, branch `forever`, commit `9dc84f0d` ("1.60.1 (70862)", 2026-11-07). Two parts were read:
   - `Blizzard_APIDocumentationGenerated`, the client's own API documentation. `tools/extract_api.py` turns it into `tests/data/forever_api.lua`: 5,144 functions, 1,816 events and 1,193 widget methods, with their secret-value flags.
   - Blizzard's own addons that use the same APIs: `Blizzard_SwingTimer`, `SecureTemplates.lua`, `StanceBar.lua`, `Blizzard_MacroUI`, `Blizzard_ColorPickerFrame`, `Blizzard_GameMenuEsc`, `SlashCommands.lua`, `CurveConstants.lua`.
2. **Installed Forever addons**, read-only: Plater (Camelot), DBM-Core, DoesItDie, GlowingBars, Attune, Auctionator, Baganator. They show how other authors handle secret values, curves and the blocked combat log on this client.
3. **Public pages**: CurseForge pages for the reference addons, the community API notes `xIGBClutchIx/ForeverPlusPlus/docs/forever-api.md`, `wowforeverguides.com`, and the IceHUD swing timer PR #105.

## 3. Findings that shape the design

### 3.1 Combat log: blocked
Registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden for addons on Forever: it raises `ADDON_ACTION_FORBIDDEN` and shows a "blocked" popup. `CombatLogGetCurrentEventInfo` is gone. DoesItDie's source says it outright: *"Never register COMBAT_LOG_EVENT_UNFILTERED: Forever forbids it"*.
**Consequence:** Warrior Master never touches the combat log, and the enemy swing timer is not implemented (see SECURITY.md).

### 3.2 Secret values
Forever inherits Midnight's "secret value" system. Several APIs can return opaque values during combat (some even outside it). Addon code can hand them to certain widget setters, but any arithmetic, comparison, concatenation or `tostring` on them raises an error.

| API | Documented flag (1.60.1.70862) |
|---|---|
| `UnitPower`, `UnitPowerPercent` | `SecretWhenUnitPowerRestricted` |
| `UnitPowerMax` | `SecretWhenUnitPowerMaxRestricted` |
| `UnitHealth` | `SecretReturns` |
| `UnitHealthMax` | `SecretWhenUnitHealthMaxRestricted` |
| `UnitHealthPercent` | `SecretReturns`, `SecretWhenCurveSecret` |
| `UnitAttackSpeed` | `SecretWhenUnitStatsRestricted` |
| `UNIT_COMBAT` amount | `SecretValue` |
| `StatusBar:SetMinMaxValues / SetValue / SetStatusBarColor` | accept secrets (`AllowedWhenTainted`) |
| `FontString:SetText / SetFormattedText` | accept secrets (`AllowedWhenTainted`) |
| `Region:SetAlpha`, `Region:SetVertexColor` | accept secrets (`AllowedWhenTainted`) |
| `Cooldown:SetCooldown` | rejects secrets |

Community testing on Forever reports that the player's own health and power can be secret, even out of combat for some power types.

**Consequence:** every value is tested with `issecretvalue` before any Lua math. When a value is hidden:
- it goes straight to the widgets;
- colors and glow come from the client's curve objects (`C_CurveUtil.CreateColorCurve` / `CreateCurve`), evaluated by `UnitPowerPercent` / `UnitHealthPercent`;
- sound alerts pause, because they need a comparison.

`CurveConstants.ScaleTo100` confirms that curves take a 0-1 fraction as input.

### 3.3 Native swing timer
Forever adds `C_SwingTimer` and the event `PLAYER_SWING(swingDuration, swingType)`, documented in `SwingTimerDocumentation.lua`:
- `swingType` uses `Enum.PlayerSwingType`: MainHand 0, OffHand 1, Ranged 2.
- `PLAYER_SWING_RANGE_UPDATE` and `C_SwingTimer.EnableRangeCheck` provide range state.
- The payload is not flagged as secret.

Blizzard's own `Blizzard_SwingTimer` (`AllowLoadGameType: camelot`) uses the same event. It also uses `WEAPON_SLOT_CHANGED` for weapon swaps and `UnitAttackSpeed` for the equipped speed.

**Consequence:** the swing timer uses this event as its only source of timing.

**Open question:** Blizzard's manager only registers `PLAYER_SWING` while the `showSwingTimer` option is on. Whether the client fires the event to addon frames while that option is off is not documented. It is covered in TESTING.md, and the settings page has a button to turn the option on.

### 3.4 Secure actions
`SecureTemplates.lua` (1.60.1) keeps the `spell`, `macro` (with `macrotext`, run via `C_Macro.RunMacroText`), `item` and `equipmentset` action types. Since 10.x, buttons should register `AnyUp` and `AnyDown` clicks because of `ActionButtonUseKeyDown`.

`/equipslot` calls `C_Item.EquipItemByName(SecureCmdItemParse(item), slot)`.

Stance data comes from `GetNumShapeshiftForms` and `GetShapeshiftFormInfo(i)`, which returns icon, isActive, isCastable and spellID. Both are used by `StanceBar.lua`.

### 3.5 Native look of the Forever interface
The default style reproduces Blizzard's own Forever UI. These atlases and fonts all come from that build:

| Element | Source in Blizzard's Forever UI | Used for |
|---|---|---|
| `UI-HUD-CoolDownManager-Bar`, `-Bar-BG` (BG offset -2,3 / 6,-7) | `Blizzard_PersonalResourceDisplay.xml` | Health and rage bars |
| Rage color (1, 0, 0) | `PowerBarColor["RAGE"]`, `PowerBarColorUtil.lua` | Default rage color |
| `ui-swingtimerbar-background`, `-frame`, `-filling-mainhand/offhand/ranged`, `-pip` (bar inset 5,4) | `Blizzard_SwingTimer.xml` | Swing bars |
| `UI-HUD-ActionBar-IconFrame`, `-Background`, `-Mask`, `-Mouseover` | `ActionButtonTemplate.xml` (Mainline family, which Camelot uses) | Stance buttons |
| `Fonts\FRIZQT__.TTF` 10, outline (`SystemFont_Outline_Small`, `TextStatusBarText`) | `GameFonts.xml`, `GameFontStyles.xml` | Bar text |
| `Fonts\ARIALN.TTF`, `MORPHEUS.TTF`, `SKURRI.TTF` | `Blizzard_Fonts_Shared` | Other fonts |

`StatusBar:SetStatusBarTexture` accepts an atlas name, as Blizzard's own code does. `Texture:SetAtlas`, `CreateMaskTexture`, `AddMaskTexture`/`RemoveMaskTexture` and `SetShadowOffset`/`SetShadowColor` are documented for 1.60.1. Each atlas call is wrapped so that a missing atlas falls back to a plain texture.

### 3.6 Slash commands, macros and tooltips
- **`/wm` is taken:** it is Blizzard's `WORLD_MARKER` secure command (`SlashCommands.lua`). `SlashCommandsRegistry.lua` states that the secure command registry "is always consulted first when a command is executed", so an addon cannot own `/wm`. Warrior Master uses `/warrior`, with `/warriormaster` and `/uw` as aliases.
- **Right-click on a secure button:** `SecureTemplates.lua` looks up `type2` for the right button. An unknown type such as `none` finds no handler, so nothing is done. `PostClick` then runs the addon's picker.
- **Stance macros:** `PickupMacro` is used by `Blizzard_MacroUI` (verified legacy global). `UPDATE_MACROS` (documented) marks the moment the player's macros are loaded; nothing is created before it.
- **Minimap button and compartment:** a plain button parented to `Minimap`. It uses the textures `Interface\Minimap\MiniMap-TrackingBorder`, `UI-Minimap-Background` and `UI-Minimap-ZoomButton-Highlight`, which Forever addons already use. The addon compartment is fed through the TOC fields `AddonCompartmentFunc*`, as ForeverDungeonJournal, OpenMap and Baganator do on Forever.
- **Item tooltips:** `GameTooltip:SetBagItem` and `SetInventoryItem` are used by Forever's own `Camelot/EquipmentFlyout.lua`.
- **Fonts:** every font file offered is referenced by `Blizzard_Fonts_Shared` of 1.60.1. That covers the Western Friz Quadrata, Arial Narrow, Morpheus and Skurri, and the Asian 2002, K_Damage, K_Pagetext, ARKai_T, bHEI01B and ARHei.

### 3.7 Removed or changed APIs
- `GetSpellInfo` and `GetItemInfo` were removed at beta. Warrior Master uses `C_Spell.*` and `C_Item.*` throughout.
- `GetMacroIndexByName` and `IsPlayerSpell` are not used by any Blizzard code of this build and are absent from the docs, so they are avoided. Replacements: a scan with `GetMacroInfo`, and `C_SpellBook.IsSpellKnown`.
- Escape handling: Forever adds `RegisterGameMenuEscHandler(priority, handler)`. It must **not** be used by addons: it inserts into and re-sorts Blizzard's handler table, which taints it, and Blizzard's Casting handler then gets `SpellStopCasting()`/`SpellStopTargeting()` blocked. Warrior Master uses the keyboard pattern Forever addons such as Auctionator use (`SetPropagateKeyboardInput` in `OnKeyDown`, close in `OnKeyUp`), and only out of combat. See SECURITY.md 4.1.

### 3.8 Legacy globals verified in Blizzard code
These globals are absent from the generated docs but used by Blizzard's 1.60.1 UI, so they exist. The audit (`tools/audit.py`, `LEGACY_GLOBALS`) records where each one is used:

`CreateFrame`, `InCombatLockdown`, `GetInventoryItemID`, `GetNumShapeshiftForms`, `GetShapeshiftFormInfo`, `GetShapeshiftFormCooldown`, `GetCVarBool`, `CreateMacro`, `EditMacro`, `GetNumMacros`, `GetMacroInfo`, `PickupMacro`, `PlaySound`, `GetBindingKey`, `geterrorhandler`, `CreateColor`, `UnitAttackSpeed`.

## 4. Reference addons

| Addon | License | Use made |
|---|---|---|
| Better Personal Resource Display | All Rights Reserved | Feature and UX inspiration only, from its public page: bar styling, visibility rules, ordering. No code or art copied or downloaded. |
| WeaponSwingTimer SixxFix | GPL-3.0 | Feature inspiration from its public page: MH/OH/target bars, per-bar settings, slam and parry handling. Its Classic implementation reads the combat log, which Forever blocks, so its approach does not carry over. No code copied. |
| Blizzard_SwingTimer | Blizzard UI | Reference for event handling (`PLAYER_SWING`, `WEAPON_SLOT_CHANGED`, range checks). No code copied. |
| DoesItDie, GlowingBars, Plater (Camelot) | Various | Read locally to confirm how other Forever addons use curves, secrets and the combat-log restriction. No code copied. |

All of Warrior Master's code and visuals are original. The visuals are built from textures and fonts that ship with the game.

## 5. Re-checking after a client patch

```bash
# 1. Update the Blizzard UI mirror (any folder outside the project)
git clone --depth 1 --filter=blob:none --sparse -b forever https://github.com/Gethe/wow-ui-source.git wowui
git -C wowui sparse-checkout set Interface/AddOns/Blizzard_APIDocumentationGenerated
# 2. Regenerate the API list and re-run everything
python tools/extract_api.py wowui/Interface/AddOns/Blizzard_APIDocumentationGenerated "<new build>"
python tests/run_tests.py
```
If an API disappears or changes, the audit and the mock name the call that is affected.
