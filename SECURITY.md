# Security and compliance - Warrior Master

Warrior Master is built to respect Blizzard's addon rules and the client's protected-action system. This document records every decision that touches account safety, so it can be audited.

> No addon can guarantee zero account risk. Warrior Master reduces risk by using documented APIs only, never automating gameplay, and turning a feature off when its behaviour cannot be confirmed. It does not claim to be "ban-proof".

## 1. Principles

1. **No automation.** The addon never plays for you. It does not cast spells, change stance, equip items, target, attack or run macros by itself, whether on a timer, on an event or on any other condition.
2. **Every game action needs your hardware input.** The only things that act in game are the stance buttons, which are secure buttons fired by your mouse click or key binding, and macros that you place and press yourself.
3. **No protected-API bypass.** No hooks on Blizzard code, no restricted-environment snippets, no `:Click()` calls, no binding changes, no combat-lockdown tricks.
4. **No combat log.** WoW Forever forbids it for addons, and the addon never registers it.
5. **No hidden values are guessed.** When the client hides a value (a "secret value"), the addon displays it through the client's own widgets or turns the dependent feature off. It never infers or approximates.
6. **Privacy.** No network traffic, telemetry or analytics. No downloaded or obfuscated code, and no external programs. The game client is never modified.

## 2. Feature classification

Status meanings:
- **SAFE**: documented APIs only, no protected behaviour.
- **RESTRICTED**: needs secure player input or is limited to out of combat.
- **UNSUPPORTED**: cannot be done compliantly, so it is not implemented.
- **UNVERIFIED**: implemented defensively but waiting for in-game confirmation. Risky items in this group are off by default.

The same list appears in game on the **Safety & About** page and comes from `Core/Security.lua`.

| Feature | Status | How it stays compliant |
|---|---|---|
| Rage bar | SAFE | Reads `UnitPower`/`UnitPowerMax`. Hidden values go straight to `StatusBar`/`FontString` setters that accept them. |
| Health bar | SAFE | Same handling with `UnitHealth`/`UnitHealthMax`. |
| Colors and glow while values are hidden | UNVERIFIED | Client curve objects (`C_CurveUtil`) evaluated by `UnitPowerPercent`/`UnitHealthPercent`. Falls back to a single color if the client rejects it. |
| Sound alerts | RESTRICTED | Need a readable value. Paused automatically while values are hidden. Edge-triggered and throttled to one every 2 s. |
| Swing timer (MH/OH/ranged) | UNVERIFIED | Uses only the client event `PLAYER_SWING`. Hidden or invalid durations are ignored and never guessed. |
| Out-of-reach dimming | UNVERIFIED | `C_SwingTimer.EnableRangeCheck`. Off by default. Only switched off again when the game's own swing bars are off, because the check is shared with them. |
| Swing timer weapon filter | SAFE | Reads the main hand's equip location with `C_Item.GetItemInfoInstant`. When it cannot be read, the timer stays shown rather than hidden on a guess. |
| Cast bar | UNVERIFIED | Reads only your own casts with `UnitCastingInfo("player")` / `UnitChannelInfo("player")` on the `UNIT_SPELLCAST_*` events, as Blizzard's cast bar does. Display only. If the start or end time is hidden (secret), no bar is drawn for that cast: addons cannot do arithmetic on hidden values, and `StatusBar:SetTimerDuration` only accepts them from Blizzard code. The game's own cast bar is never touched. |
| Enemy swing timer | **UNSUPPORTED** | Would need the combat log, which is blocked. `UNIT_COMBAT` cannot tell which enemy swung, so a timer built on it would be misleading. Not implemented. |
| Stance buttons | RESTRICTED | `SecureActionButtonTemplate`, type `spell`. They act only on your click or binding. Created, changed, moved and hidden only out of combat. |
| Weapon picker (right-click) | SAFE | Plain UI. The right mouse button is given the secure type `none`, which is not an action, so a right-click never casts or equips anything. The picker only saves your choice. |
| Stance macros for action bars | RESTRICTED | Character macros "WM Battle/Defensive/Berserker" with the same text as each stance button's click action, validated, and never run by the addon. Created with `CreateMacro` only once the game has loaded your macros (`UPDATE_MACROS`, so no duplicates), and updated with `EditMacro` when the setup changes. Out of combat only, and can be turned off. `PickupMacro` puts one on your cursor only when you click or drag. A macro you delete is not recreated until that stance's setup changes. Editing macros is interface configuration, not a game action. |
| Stance macros onto an action bar | RESTRICTED | One button on the Stances page. On your click and out of combat only, it picks up the addon's own stance macros (`PickupMacro`) and drops each into an empty slot with `C_ActionBar.PutActionInSlot`, then clears the cursor. It refuses if your cursor holds something, skips macros already on a bar, never replaces or removes an action, and never touches the main bar. Placing an action is interface configuration, like dragging it yourself. |
| Automatic layout | SAFE | Only positions frames, each anchored to the screen (never to another module's frame). The secure stance bar is moved through `ns.Combat:Run`, so out of combat only. |
| Warrior effects in the settings window | SAFE | Cosmetic textures already in the client and `PlaySound` with sound kits from the client's own `SOUNDKIT` table. The overlay never takes mouse clicks, and its `OnUpdate` only runs while an effect plays. Follows the Sound switch and can be turned off. |
| Minimap button and AddOns menu entry | SAFE | Plain UI parented to the minimap and the TOC `AddonCompartmentFunc` entry; both only open the settings or lock and unlock frames. |
| Weapons with a stance | RESTRICTED | Same secure click with type `macro`: `/cast [nostance:N] Stance` followed by `/equipslot` or `/equipset` lines that you chose. |
| Automatic weapon or stance swap on events | **UNSUPPORTED** | That would play the game for you. Forbidden by design. A stance change only updates the highlight. |
| Macro builder: text, preview, copy | SAFE | Text generation and validation only. |
| Macro builder: create in game | RESTRICTED | `CreateMacro`/`EditMacro`, only from your button click, only out of combat, only after validation. The addon never runs the macro. |
| Profiles, import and export | SAFE | Plain-data format, read by a hand-written parser (never `loadstring`), then validated field by field. |
| Client swing-timer option button | RESTRICTED | Sets the `showSwingTimer` option only when you click the button, and only out of combat. This is the only setting the addon ever changes. |

## 3. Secure interaction rules, as implemented

### 3.1 Combat lockdown
- Every change to a secure frame goes through `ns.Combat:Run(key, fn)` in `Core/Combat.lua`. This covers creation, attributes, show/hide, size and position.
- In combat the change is queued (the latest change per key wins) and applied on `PLAYER_REGEN_ENABLED`.
- `Security.AssertOutOfCombat` is a second guard inside those functions. If it ever fires, the error is reported, not hidden.
- If you `/reload` in combat, the secure buttons are created only after combat.
- The automatic layout moves the stance bar through the same queue: changed in combat, it moves after combat, while the plain bars follow at once.
- Dragging the stance bar is refused in combat. When combat starts, any drag in progress is stopped and every frame is locked. This happens on `PLAYER_REGEN_DISABLED`, before lockdown begins.
- During combat only cosmetic regions change: the active-stance highlight, cooldown swipe, icons and tooltips. Hidden stance state is turned into an alpha value with `C_CurveUtil.EvaluateColorValueFromBoolean`.

### 3.2 What a stance button can do
The button holds one of two actions, both built only from your own choices:
```
type = "spell",  spell = "Defensive Stance"
type = "macro",  macrotext = "/cast [nostance:2] Defensive Stance\n/equipslot 16 item:12345\n/equipslot 17 item:67890"
```
- Item and stance names pass through `Security.SanitizeMacroToken`. It removes line breaks, control characters, `|`, `[`, `]`, `;` and leading slashes, so a crafted item name cannot inject another line or condition. This is tested.
- The text is checked against the forbidden command list and limited to 1,000 characters.
- Disabling the module clears all actions (`type`, `spell` and `macrotext` set to nil) and hides the buttons. In combat this happens right after combat.
- Key bindings (`Bindings.xml`) are standard `CLICK` bindings on these buttons: your key press is the hardware event.

### 3.3 Macro policy
Generated macros do one thing per key press and use only standard macro options: `[stance]`, `[nostance]`, `[equipped]`, `[noequipped]`, `[mod]`, `[combat]` and `[nocombat]`.

The validator (`MacroBuilder.Validate`) and `Security.FORBIDDEN_COMMANDS` reject the following:
- Script and console commands: `/run`, `/script`, `/console`, `/dump`, `/tinspect`, `/eventtrace`, `/fstack`, `/framestack`, `/api`.
- Session commands: `/reload`, `/rl`, `/logout`, `/camp`, `/quit`, `/exit`.
- Action chains: `/castsequence` and `/click`.

Conditional stance macros (for example "Overpower in Battle Stance, otherwise switch to Battle Stance") are a standard Blizzard feature. They still need one key press per action and make no decision the player did not encode.

### 3.4 Things the addon never does
Each item below is enforced by the static audit (`tools/audit.py`), which also tests itself against known-bad samples:
- Code execution or environment access: `loadstring`, `load`, `dofile`, `loadfile`, `getfenv`, `setfenv`, the `debug`, `io` and `os` libraries, `RunScript`, `RunMacro`, `RunMacroText`.
- Protected actions: `CastSpellByName`, `CastSpellByID`, `CastShapeshiftForm`, `UseAction`, `UseInventoryItem`, `UseContainerItem`, `PickupInventoryItem`, `PickupContainerItem`, `EquipItemByName`, `EquipCursorItem`, `AutoEquipCursorItem`, `UseEquipmentSet`, `TargetUnit`, `AttackTarget`, `StartAttack`, `SpellStopCasting`, `SecureCmdUseItem`.
- Programmatic clicks: `:Click()` on any frame.
- Combat log: `CombatLogGetCurrentEventInfo`, or any `COMBAT_LOG_EVENT*` string.
- Communication: `SendChatMessage`, `SendAddonMessage`, `C_ChatInfo`, `C_BattleNet`.
- Bindings, hooks and secure drivers: `SetBinding*`, `SetOverrideBinding*`, `hooksecurefunc`, `RegisterStateDriver`, `SecureHandlerWrapScript`.
- Game settings: `SetCVar`, with one documented, line-marked exception (the swing-option button).
- Blizzard's internal lists: `RegisterGameMenuEscHandler`, `UISpecialFrames` and `StaticPopupDialogs`, with no exception (see 4.1).

## 4. Runtime safeguards
- **API presence:** every version-sensitive API is looked up in `Core/Compat.lua` and wrapped in `pcall`. A missing API turns the dependent feature off.
- **Hidden values:** `issecretvalue` is checked before any comparison or arithmetic (`Compat.ReadableNumber` and `ReadableBool`).
- **Saved data:** profiles, character data and imports are rebuilt through `Core/Schema.lua`. That fixes wrong types, NaN or infinite numbers, out-of-range values, unknown enums, oversized strings and unknown keys.
- **Import limits:** 64 KB of text, nesting depth 12, 4,000 items, strings of 1,024 bytes, a checksum, and no code evaluation.
- **Errors:** event handlers run under `pcall`. Each error is recorded (`/warrior errors`) and forwarded once to the game's error handler, so it stays visible rather than being swallowed.
- **Blocked actions:** if the client reports `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` for this addon, a chat warning is printed.
- **Event volume:** each module has its own event frame. A disabled module unregisters everything and cannot act. Swing updates run only while a swing is in progress. Bursts of bag and item events are merged into one rebuild.
- **Message loops:** internal messages stop at a depth of 8.
- **Taint:**
  - No Blizzard frame or function is hooked, modified or re-anchored, and nothing is added to Blizzard's internal lists.
  - The settings window uses its own widgets, not `UIDropDownMenu`.
  - Escape is handled by each window's own keyboard script, and keyboard capture is off during combat (see 4.1).

### 4.1 Escape key and taint (fixed in 1.0.1)
In 1.0.0, the settings window and the weapon picker added their own handler to Blizzard's Escape list with `RegisterGameMenuEscHandler`. That function inserts into and re-sorts a table that Blizzard's own handlers live in, and doing that from addon code taints the table. Blizzard's "Casting" Escape handler (`Blizzard_Game/Shared/Game.lua`) calls `SpellStopCasting()` and `SpellStopTargeting()`. Once the table was tainted, pressing Escape to stop a cast or cancel targeting was blocked, and the game blamed Warrior Master, even though the addon never calls those functions itself.

The fix in 1.0.1:
- Warrior Master no longer calls `RegisterGameMenuEscHandler`, and never writes to `UISpecialFrames`. The audit forbids both, plus `SpellStopCasting`, `SpellStopTargeting`, `SpellTargetUnit` and `ClearTarget`.
- Each window listens to the keyboard itself. `OnKeyDown` stops only Escape from reaching the game (`SetPropagateKeyboardInput(false)`), `OnKeyUp` closes the window, and every other key passes through.
- Addons cannot change keyboard propagation in combat, so keyboard capture is switched off on `PLAYER_REGEN_DISABLED`. During combat, Escape goes straight to the game (stop casting, cancel targeting, menu), and the window closes with its X button.
- Tests check that no Blizzard Escape handler is ever registered, that `UISpecialFrames` stays empty, and that no keyboard call is made in combat.

### 4.2 Optional SharedMedia
If another addon has loaded LibSharedMedia-3.0, Warrior Master reads its list of status bar textures and fonts. It only looks up file names through `LibStub("LibSharedMedia-3.0", true)`, inside `pcall`. Nothing is registered, modified or executed, and the addon works the same without it.

## 5. Privacy and integrity
- No network communication, telemetry, analytics or personal data collection. The saved variables contain only settings, your profile names and the item IDs you picked.
- No external executables, DLLs, memory access or client modification.
- The source is plain, commented Lua with no obfuscation, minification or bundled libraries.
- During development the game was never launched or controlled, and no debugger was attached. All validation is offline (see TESTING.md).

## 6. Reporting a problem
Run `/warrior diag` and `/warrior errors` in game and share the output. If the game ever shows "Interface action failed because of an AddOn" or a blocked-action warning naming Warrior Master, disable the module concerned and report it. It will be treated as a bug to fix, never worked around.
