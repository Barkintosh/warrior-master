# Testing - Warrior Master

Two kinds of validation are kept strictly apart:

- **Validated offline**: checks that ran on this machine without the game. Static analysis, Lua 5.1 compilation, and behaviour tests against a mocked client.
- **Awaiting in-game verification**: anything that depends on the real client. Only the player runs these, by hand.

Nothing in this project launches, controls or connects to World of Warcraft or Battle.net.

---

## Part 1 - Offline validation

### Running it
```bash
python -m pip install lupa
```
```bash
python tests/run_tests.py
```
`lupa` provides an embedded Lua 5.1 interpreter (the same language version as WoW). The runner takes a minute or two. Run one test file with `python tests/run_tests.py test_stance`.

### What it checks
| Step | Content |
|---|---|
| 1. Syntax | Every addon and test file compiles under Lua 5.1. |
| 2. TOC | `## Interface: 16001`; every listed file exists; no Lua file is left out. |
| 3. Locales | `frFR` defines exactly the `enUS` keys; `%d`/`%s` placeholders match; every string the code uses exists. |
| 4. Static audit (`tools/audit.py`) | No forbidden API (automation, code execution, combat log, chat, bindings, hooks, CVars); no `:Click()`; every global call, `C_` API and registered event exists in Forever 1.60.1.70862. Also runs a self-test proving the audit catches 11 kinds of violation. |
| 5. Behaviour tests (`tests/test_*.lua`) | Sixteen test files, run against the mock in `tests/wowmock.lua` (see below). |

What the mock (`tests/wowmock.lua`) enforces:
- **Widget methods:** every PascalCase method the addon calls must be in Blizzard's documented widget API for 1.60.1 (`tests/data/forever_api.lua`) or in a short list of verified Blizzard mixins. Anything else raises an error.
- **Events:** registering an event the client does not document raises an error.
- **Hidden values:** `Mock.Secret(v)` raises an error on any arithmetic, comparison, concatenation or `tostring`, like the real client does for addon code.
- **Combat lockdown:** protected operations on secure buttons (and on their parent frames) raise `ADDON_ACTION_BLOCKED` while in combat, and are counted. Every test fails if anything was blocked or any addon error was reported.
- **Global writes:** every global the addon writes is recorded and compared with the allowed list.

### Latest offline result
Run on 2026-11-08 against API data for build 1.60.1.70862: **162 passed, 0 failed** (`python tests/run_tests.py`). That is 12 static checks plus 150 behaviour tests in 16 files. The suite covers:
- **Boot:** loads on Warriors only; creates only its saved variables, slash command and key-binding labels as globals; disabled modules release their events and actions; Options entry and Escape handler.
- **Bars:** readable values and threshold colors; other power types ignored; hidden values go to widgets with no Lua math; the client's curves drive color and glow; the color curve matches the Lua color rules; low-health sound is edge-triggered and throttled; sound pauses while values are hidden; visibility and opacity rules; attachment to the health bar; preview mode switches off when combat starts.
- **Swing:** progress and countdown; updater stops when idle; off-hand bar only with an off-hand weapon; hidden or invalid durations ignored; haste rescale; no rescale when attack speed is hidden; weapon-swap restart; sound; range check off by default; disabled module ignores swings; game-option button refused in combat.
- **Stances:**
  - one secure button per known stance;
  - the click macro is built from your loadout;
  - two-hander conflicts and missing items are reported;
  - a malicious item name cannot inject a line;
  - changes and disabling made in combat wait until combat ends, with zero blocked calls;
  - a stance change in combat only moves the highlight;
  - hidden stance state is handled;
  - the bar cannot be dragged in combat;
  - equipment sets, binding labels and tooltips work.
- **Macros:**
  - all 21 templates build valid macros (255 characters or fewer, no placeholder, no forbidden command, translated name and description);
  - missing items are reported;
  - stance-dance text is correct, and French fallback names are used when the client gives none;
  - the validator rejects `/run`, `/script`, `/castsequence`, `/click` and oversized text;
  - saving creates, updates, refuses in combat (never calling `CreateMacro`), and checks name and free slots;
  - option values are sanitized.
- **Profiles:** corrupted saved variables are repaired; create, switch, copy and delete; export then import round-trips; hostile or broken imports are refused and never executed; serializer and base64 round-trip; styles change only the look and restore the custom look; module reset; forced language.
- **UI:** all 8 pages build and refresh; checkbox, dropdown and color picker work; two-click confirmation; macro page preview and save; profile import; live French rebuild; movers (drag, right-click reset); slash commands.
- **Styles:**
  - a new profile equals the WoW Forever style;
  - all 11 styles define every setting with valid values and render on every module;
  - partial application (only some parts), single-module application, and Custom restore per module;
  - only style settings switch a module to Custom;
  - Forever draws Blizzard's atlases (resource bar, swing frame, fills and pip, action-button frame and mask);
  - switching to a non-atlas border uses the background color;
  - SharedMedia textures and fonts are listed and used when present, and ignored when absent;
  - the General page picker applies the chosen parts and modules.
- **Weapon picker and stance macros:**
  - right-click opens the picker and has no secure action;
  - the right weapons are listed per hand;
  - clicking icons assigns them and rebuilds the click action;
  - a two-hander disables the off hand;
  - picks made in combat apply after combat;
  - equipment sets and single weapons replace each other;
  - Escape closes the picker;
  - the stance macro is created, placed on the cursor and kept in sync (never edited or created in combat);
  - the Stances page "Put on action bar" button works.
- **Positions, command, fonts, layout:**
  - the global offset moves every module (the stance bar after combat if needed);
  - keep-on-screen works per module and globally;
  - changing the anchor keeps the frame in place;
  - dragging keeps the anchor;
  - the All modules handle sets the global offset;
  - `/warrior` is the command and `/wm` is left to the game;
  - font styles apply font, size and outline together;
  - short controls share rows.
- **Stance macros, minimap and compartment:**
  - nothing is created before the macros are loaded;
  - after loading, one macro per known stance, with no duplicates (also through the fallback timer);
  - macros follow the setup;
  - a deleted macro is not recreated until its setup changes;
  - the option turns them off and on;
  - in combat they wait for the end of combat;
  - full slots are reported once;
  - the minimap button sits on the edge, opens the settings, locks and unlocks, can be dragged and hidden;
  - the compartment entry opens the settings;
  - nothing appears on other classes.
- **Cast bar:**
  - a cast shows its name, icon, progress and time, fills when it ends and fades;
  - a channel empties, and an interrupted channel shows it;
  - another spell failing mid-cast leaves the bar alone, our own interrupt or failure is shown;
  - hidden cast timing draws nothing and raises no error;
  - pushback moves the end time;
  - a cast already running at login is picked up;
  - the bar ends by itself if the stop event never comes;
  - preview mode, the move placeholder, the Forever casting-bar art for each state, and all 11 styles.
- **Swing timer weapon filter:** any weapon, two-handed only, one-handed only (dual wield included), no weapon, frames unlocked, and an unreadable weapon (never hidden).
- **Automatic layout:**
  - off by default;
  - stacks every module top to bottom with the gap, each anchored to the screen;
  - reorder with the arrows, and switched-off modules take no room;
  - saved or imported orders are repaired;
  - in combat the stance bar waits and the other bars follow, with no protected call, and switching the layout off mid-fight puts it back in its own place;
  - dragging any bar moves the whole stack, and right-click puts it back;
  - an attached rage bar is placed by the layout;
  - the module pages say the layout places them.
- **Stance macros onto an action bar:** one button; three macros side by side on a shown bar; an existing action is never replaced; a second click is harmless; only missing macros are placed; hidden bars are a last resort; full bars are reported; refused in combat or with something on the cursor.
- **Weapon picker:** only weapons, with no macro, binding or hint text.
- **Warrior effects:** execute splash on a button press (chance 100), never at chance 0, always on a confirmed reset, battle cry on closing, the Sound switch silences them, the switch turns them off, the try button fires once, and nothing keeps running afterwards.
- **Escape and taint:**
  - nothing is ever added to Blizzard's Escape handler list or `UISpecialFrames`;
  - Escape closes the dropdown, then the window, without reaching the game;
  - other keys keep reaching the game;
  - in combat, keyboard capture is off and Escape goes to the game, with no keyboard call blocked.
- **Mock self-tests:** they prove the mock really rejects undocumented methods, unknown events, combat-blocked calls and math on hidden values, and that nothing runs `OnUpdate` while idle.

### Limits of offline testing
- In the mock, `type()` of a hidden value is `"table"` (in game it is `"number"` or `"string"`). Equality tests against a hidden value do not raise errors in the mock. The addon always calls `issecretvalue` before comparing, so this does not hide bugs in the current code, but the real client is the final judge.
- Rendering (textures, fonts, layout, colors on screen) is not visible offline.
- When the client hides values, which values it hides and when is decided by the real client. The mock only switches them on and off on request.
- `CreateMacro`, `/equipslot`, secure clicks and key bindings are simulated, not executed.

---

## Part 2 - Manual in-game checklist (player only)

**Before you start:**
1. Install the addon (see README).
2. In the game options, turn on *Display Lua errors*, or use BugSack.
3. After each section, type `/warrior errors`. It should print "No errors recorded this session".

Keep the output of `/warrior diag` from your first login. It reports, for your client, which values are hidden, whether the native swing event arrives, and how many queued secure changes are waiting.

Each test lists what to do, what you should see, and what counts as a failure.

### T1 - Loading
- **Do:** log in on a Warrior, then type `/warrior`.
- **Expected:** the chat says nothing alarming. The settings window opens. The health, rage, swing and stance displays appear under your character.
- **Failure:** a Lua error, a missing window, or the message "only active on Warrior characters" on a Warrior.
- **Also:** log in on another class. Nothing should appear, and `/warrior` should print the Warrior-only message.

### T2 - Diagnostics
- **Do:** type `/warrior diag` out of combat, then again during a fight against a training dummy or a mob.
- **Expected:** the lines `Hidden values: ...` and `APIs: curves yes | native swing yes ...`.
- **Report:** please send both outputs. They confirm which values the real client hides on Forever.

### T3 - Rage bar
- **Do:** fight a mob and gain and spend rage.
- **Expected:**
  - The bar fills smoothly and the number follows your rage.
  - The color changes at 30 and 60 rage (default "By thresholds" mode).
  - The golden glow pulses above 50 rage.
- **If the client hides rage** (`rage yes` in diag): the bar, number, colors and glow must still work in combat. Sound alerts may stay silent, which is expected.
- **Failure:**
  - the bar stays empty or frozen;
  - the text is blank in combat while the bar moves (report `/warrior diag`);
  - the color never changes in combat (curves not accepted: report `curve failures` from diag);
  - a Lua error.

### T4 - Health bar and low-health warning
- **Do:** take damage until you drop below 30 % health.
- **Expected:**
  - The bar and "value (percent)" text follow your health.
  - The color goes from green through yellow to red.
  - A red glow pulses below 30 %.
  - The raid-warning sound plays once when crossing 30 %, but only if health is readable at that moment.
- **Failure:** wrong values, no glow, repeated sounds, or errors.

### T5 - Swing timer (most important check)
- **Do:** equip a weapon, attack a training dummy for 20 seconds, then type `/warrior diag`.
- **Expected:**
  - The main-hand bar refills with each swing, and the countdown matches your weapon speed.
  - The diag line `PLAYER_SWING events N` shows N greater than 0, with `hidden 0`.
- **If N stays 0:** open **Swing Timer** settings, click **Turn on the game swing timer**, and repeat. Please report whether that was needed; it decides a documented open question.
- **Dual wield:** equip two one-handed weapons. An off-hand bar must appear and refill independently.
- **Shield:** equip a shield. The off-hand bar must disappear.
- **Weapon swap mid-fight:** the bar should restart with the new weapon's speed.
- **Haste** (for example Flurry or a haste effect): the running swing should shorten. With *Adjust a running swing...* turned off, it must not.
- **Slam or Heroic Strike:** watch whether the bar resets as the game resets your swing. The addon only follows the client's event, so report what you see.
- **Failure:** the bars never move, they show the wrong durations, `hidden` is greater than 0, or errors appear.

### T6 - Swing out-of-reach dimming (experimental, off by default)
- **Do:** in **Swing Timer** settings, turn on *Dim bars when the target is out of reach*. Attack a target, then step out of melee range between swings.
- **Expected:** the bars dim between swings while you are out of reach.
- **Failure:** no dimming, or Blizzard's own swing bars stop dimming correctly.

### T7 - Stance buttons (secure)
- **Do:** click each stance button out of combat, then in combat.
- **Expected:** you change stance. The gold border follows the active stance. The tooltip names the stance.
- **Bindings:** go to *Options > Keybindings > AddOns > Warrior Master*, bind a key to *Stance button 1*, and press it. You should change stance, and the key label should appear on the button.
- **Failure:** nothing happens on click, an "Interface action failed because of an AddOn" message appears, or errors appear.

### T8 - Weapons per stance
1. In **Stances & Weapons**, choose a one-hander and a shield for Defensive Stance, and a two-hander for Battle Stance.
2. Click the Defensive button, then the Battle button, out of combat.
3. Expected: the stance changes and the chosen weapons are equipped in the same click. The "Click action" preview matches what happens.
4. Repeat in combat (Classic rules allow weapon swaps in combat).

- **If items do not equip:** turn on *Use item names instead of item IDs* and retest. Report which mode works, because this decides whether `/equipslot item:ID` is accepted by the client.
- **Combat check:** change a weapon choice during combat. Chat should say the change applies after combat, and the button should update when combat ends.
- **Failure:** the stance changes but no weapon swaps (try item names), a wrong item swaps, or errors appear.

### T9 - Macro builder
- **Do:** in **Macro Builder**, pick *Overpower*, then click **Create or update macro**. Open `/macro`.
- **Expected:**
  - A macro named "Overpower" exists with the previewed text.
  - Placing it on a bar and pressing it casts Overpower in Battle Stance, or switches to Battle Stance otherwise.
  - **Select text** highlights the preview so you can press Ctrl+C.
  - Clicking **Create** in combat shows "cannot be created or edited in combat".
- **Failure:** the macro is not created, the text is wrong, a spell name is wrong in your language, or errors appear.

### T10 - Settings, presets, profiles
- **Moving frames:**
  - **Unlock frames** (footer) and drag each frame. Its position should be kept after `/reload`.
  - Right-click a frame to reset it.
  - Entering combat while unlocked should lock everything.
- **Default look:** on a fresh profile, compare the bars with the game's own personal resource display and swing timer (turn them on in Edit Mode to see both). Textures, colors, text and the swing frame should match closely.
- **Styles:**
  - apply each style to all modules and check that it looks right;
  - then apply one style's **Colors** only on top of another;
  - then apply a style to a single module;
  - choosing **Custom** should bring your own look back.
  Please report any style that looks wrong, with a screenshot.
- **Profiles:**
  - Create a profile, change something, then switch back to Default.
  - **Export** and copy the text.
  - **Import** it under a new name; it should be identical.
  - Paste random text and import it: you should get a clear error and nothing else.
- **Language:** set *Addon language* to Français. The window switches to French.
- **Escape** closes the settings window, and closes an open dropdown first. Out of combat only: in combat, Escape is left to the game.
- **Options entry:** *Options > AddOns > Warrior Master* shows a button that opens the window.
- **Preview mode:** the bars animate. Entering combat turns preview mode off.

### T10b - Weapon picker, stance macros, positions, fonts
- **Picker:**
  - Right-click each stance button: the picker opens above it, with the right weapons as icons.
  - Hover an icon: the item tooltip appears.
  - Click a one-hander and a shield, then left-click the button: you change stance and equip them.
  - Right-clicking must never change your stance.
- **Stance macros:**
  - In the picker, drag the stance icon onto an action bar slot. A macro "WM Defensive" (or Battle, Berserker) appears there.
  - Pressing it does the same as the stance button.
  - Change the weapons: after combat, the macro text in `/macro` should follow.
- **Positions:**
  - Unlock frames and drag the **All modules** handle: everything moves together.
  - Change a module's screen anchor: it must not jump.
  - Turn off "Keep on screen" and drag a bar half off screen; turn it on again and it comes back.
- **Fonts:** try each font style and each font. Note any font that shows boxes instead of letters, especially accented letters in French.

### T10e - Cast bar, layout, action bar placement and warrior fun (1.2.0)
- **Cast bar:** cast Hearthstone. The bar shows its icon, name and time left, fills, then fades. Move while casting: it shows "Interrupted".
  - Eat or drink, or use a bandage: the bar empties as the channel runs.
  - Press another ability while casting: the bar keeps going.
  - `/warrior diag` shows the cast counts and how many casts had hidden timing.
- **Swing filter:** set Swing Timer > Show with > Two-handed weapons only. With a one-hander the timer disappears; equip a two-hander and it comes back.
- **Layout:** General > Layout, tick the switch. The bars stack with an even gap. Use the arrows to reorder, change the gap and the alignment.
  - Unlock the frames and drag any bar: the whole stack moves.
  - Change the order in combat: the stance bar moves when combat ends, with no error.
- **Action bar:** turn on the bottom left bar in the game's options. On the Stances page, click **Put the stance macros on an action bar**. The three WM macros land side by side in empty slots and nothing else on the bar changes. Click it again: it says they are already there.
- **Weapon window:** right-click a stance button. It shows only weapon icons (and sets), with no text below them.
- **Warrior fun:** on the General page, click **Execute!**: sound, blood and a battle line. Close the settings: war horn and battle cry. Untick the switch: silence.

### T10d - Stance macros and minimap button (1.1.0)
- **Stance macros:** log in, open `/macro` and go to the Character tab. You should see WM Battle, WM Defensive and WM Berserker, only for the stances you know, and only once even after `/reload`.
  - Put one on an action bar and press it: same result as the stance button.
  - Change that stance's weapons (right-click the stance button). The macro text updates after combat if you were fighting.
  - Delete one and `/reload`: it stays deleted until you change that stance's weapons.
- **Minimap button:**
  - The Warrior Master icon sits on the minimap edge.
  - Left-click opens or closes the settings; right-click locks or unlocks the frames.
  - Drag it around the minimap, `/reload`, and it stays where you put it.
  - The General page switch hides it.
  - The game's AddOns menu next to the minimap also lists Warrior Master.
- **Command:** `/warrior` opens the settings.

### T10c - Escape never blocked (fixed in 1.0.1)
1. Open `/warrior` and the weapon picker once, then close them.
2. Start casting something with a cast time (or click a ground-targeted ability), then press **Escape**. The cast or targeting must stop normally.
3. Do the same in combat.
4. **Failure:** any "blocked" message naming Warrior Master, or naming `SpellStopCasting()` / `SpellStopTargeting()`.

### T11 - Taint and blocked-action watch
Play normally for a while: dungeon, group, open bags, change talents if applicable, `/reload` in and out of combat.

- **Expected:** no "Interface action failed because of an AddOn" message, and no blocked-action warning naming Warrior Master.
- **If one appears:** note what you were doing and send `/warrior diag` and `/warrior errors`.

### Reporting results
For each test, please send:
- PASS or FAIL;
- the `/warrior diag` output;
- any error text;
- a screenshot if the issue is visual.

Results from T2, T5 and T8 decide the remaining open questions. Those features stay marked "Unverified" until you confirm them.
