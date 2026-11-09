# Warrior Master

An all-in-one, lightweight addon for **Warriors** in **World of Warcraft Forever** (client 1.60.1, interface 16001). English and French.

| Module | What it gives you |
|---|---|
| **Rage Bar** | Smooth rage bar with value text, threshold or gradient colors, a glow above a threshold, an optional sound, and visibility rules. It can attach to the health bar. |
| **Health Bar** | Personal health bar with value and percent, color gradient, and a low-health glow and sound. |
| **Swing Timer** | Main-hand, off-hand and ranged bars driven by the game's own swing event, with countdown, haste adjustment, weapon-swap restart, optional sound and optional out-of-reach dimming. It can show only with a two-handed or only with one-handed weapons. |
| **Cast Bar** | Your own casts and channels, including items that cast (Hearthstone, bandages, food and drink): icon, name, time left, and a finished, failed or interrupted flash. |
| **Stances & Weapons** | Secure buttons for Battle, Defensive and Berserker Stance. Each button can also equip the weapons (or equipment set) you choose for that stance, all in one click or key press. |
| **Macro Builder** | 21 Warrior templates (stance dancing, Charge/Intercept, Overpower, Execute, Pummel/Shield Bash, Taunt, weapon swaps, and more), with options, live preview, validation, copy, and one-click creation. |

Out of the box everything looks like WoW Forever's own interface. Eleven ready-made styles combine textures, colors and fonts, and every setting can still be changed one by one. One switch stacks every bar vertically with an even gap, in the order you choose. Profiles can be per character or shared, and can be imported and exported.

**Safety first:** Warrior Master never plays for you. It never reads the combat log, never acts without your click or key press, and never sends data anywhere. See [SECURITY.md](SECURITY.md).

---

## Installation
1. Close the game, or plan to `/reload` after copying.
2. Copy the `WarriorMaster` folder into the Forever AddOns folder:
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
3. The result must be `...\Interface\AddOns\WarriorMaster\WarriorMaster.toc`.
4. Start the game yourself, and enable **Warrior Master** in the AddOns list on the character screen.

From this repository you can also run:
```bash
cp -r WarriorMaster "/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/"
```

The addon only activates on Warrior characters.

## Getting started
- Type **`/warrior`** to open the settings (`/warriormaster` and `/uw` work too), or click the **minimap button**. Warrior Master is also in the game's AddOns menu next to the minimap.
- **Minimap button:** left-click opens the settings, right-click locks or unlocks the frames, and you can drag it around the minimap. It can be hidden on the General page.
- Click **Unlock frames** in the window footer and drag the bars where you want them. Right-click a frame to reset its position.
- Turn on **Preview mode** to see every bar with simulated values while you style them. It turns itself off when combat starts.
- Pick a **style** on the General page (or at the top of a module's page), then fine-tune anything you like.

### Slash commands
| Command | Effect |
|---|---|
| `/warrior` | Open or close the settings |
| `/warrior lock`, `/warrior unlock` | Lock or unlock frame dragging |
| `/warrior test` | Toggle preview mode |
| `/warrior preset <style> [module]` | Apply a style to every module, or to one (`health`, `rage`, `swing`, `stance`). Example: `/warrior preset frost rage` |
| `/warrior profile <name>` | Switch profile |
| `/warrior reset` | Reset all frame positions |
| `/warrior diag` | Print diagnostics (client build, hidden values, swing events, queued changes) |
| `/warrior errors` | List errors caught this session |
| `/warrior help` | List commands |

(`/wm` cannot be used: on WoW Forever it is the game's own world-marker command, and the game always runs its built-in commands before an addon's.)

### Stances and weapons in three clicks
1. **Right-click** a stance button. A small window lists, as icons, the weapons in your bags and equipment that fit each hand (and your equipment sets, if you have any).
2. **Click the icons** you want for that stance. A two-hander greys out the off hand; choosing an equipment set replaces single weapons.
3. **Left-click** the stance button (or press its key) to switch stance and equip those weapons in one go.

**Stance macros:** Warrior Master creates its own character macros for the stances you know: **WM Battle**, **WM Defensive** and **WM Berserker**. Each one does exactly what its stance button does, stance and weapons. Put them wherever you like on your action bars (find them in `/macro`, Character tab) and bind keys to those slots.
- **Always up to date:** whenever you change a stance's weapons, its macro is updated.
- **Out of combat:** they are created and updated outside combat only.
- **Deleting one:** a macro you delete stays deleted until you change that stance's setup again.
- **Turning them off:** there's a switch on the Stances page.
- **One-click placement:** the Stances page's **Put the stance macros on an action bar** button puts the macros you don't have on a bar yet into empty slots, side by side, on the bottom left, bottom right, right or left bar (a bar that is shown comes first). It never replaces an action, and works out of combat only.

The weapon window only switches weapons: icons per hand, and equipment sets if you have any. Nothing else.

**Prefer the game's own stance bar?** Tick **Use the game's stance bar** on the Stances page. Warrior Master's bar disappears and its actions move onto the game's stance buttons:
- **Left-click** a stance there: change stance and equip the weapons you chose.
- **Right-click** it: open the weapon picker (a right-click no longer changes stance).
- **Look and position:** the game's bar keeps its look, position and cooldowns. Move it with the game's Edit Mode, and keep it shown (Options > Action Bars).
- **Key bindings:** the game's own stance key bindings still only change stance. Use Warrior Master's bindings to equip as well.
- **Quick keybind mode:** turn the option off while you set key bindings with the game's quick keybind mode.

### Key bindings
*Options > Keybindings > AddOns > Warrior Master* lists **Stance button 1-3**. They press the stance buttons exactly like a click.

## Styles
The default look is **WoW Forever**, built from Blizzard's own Forever interface:
- **Health and rage bars:** the personal resource bar texture and drop-shadow background, Blizzard's green health and red rage, and Friz Quadrata text with an outline.
- **Swing timer:** the native framed swing bars, with Blizzard's own main-hand, off-hand and ranged fills and the moving "pip".
- **Stance buttons:** the action-button frame with a masked icon and a glow on the active stance.

Ten more styles mix textures, colors and fonts:

| Style | Look |
|---|---|
| Classic | Old-school status bar texture, classic frame border, red-yellow-green health |
| Modern | Flat glossy bars, thin black border |
| Minimal | Thin flat bars, no border, muted colors, small Arial text |
| Compact | Small bars and buttons |
| High Visibility | Large bars, white borders, bright colors, thick outlines |
| Ember | Smooth bars in fire tones, Morpheus font |
| Frost | Icy blues and whites, glossy, shadowed text |
| Gladiator | Gold borders on black, Morpheus font |
| Berserker | Blood-red bars, thick borders, Skurri font |
| Void | Purple and teal, Skurri font |

**How to apply one** (General page):
- pick the style;
- pick **all modules** or one module;
- tick the parts you want: **Textures & borders**, **Colors**, **Fonts & text**, **Sizes**.

So you can, for example, take Ember's colors on top of the Forever textures. Each module page also has a one-click **Apply to this module**.

Positions, thresholds, alerts and visibility are never changed by a style. Changing any style setting by hand makes that module **Custom**, and choosing **Custom** later brings your own look back after you've tried other styles.

**Media:**
- **Textures:** 8 bar textures (WoW Forever, WoW Forever swing, WoW Forever cast, Flat, Classic, Smooth, Raid, Skills).
- **Fonts:** 10, all from the game files: Friz Quadrata, Arial Narrow, Morpheus, Skurri, plus Gothic, Damage, Page Text, Kai Brush, Hei Bold and Hei. The last six are the game's Asian fonts: great for numbers, but some accented letters may be missing.
- **Font styles:** 12 one-click combinations of font, size, outline and shadow (WoW Forever, Classic, Clean, Crisp shadow, Fantasy, Runic, Bold, Impact, Storybook, Brush, Heavy, Large).
- **SharedMedia:** if another addon provides LibSharedMedia, its textures and fonts appear in the lists too.

**Positions:**
- **Each module:** choose a screen anchor (corners, edges or center) and decide whether it stays on screen.
- **Everything at once:** the General page moves all modules together and can keep every frame on screen. When frames are unlocked, an **All modules** handle appears; drag it to move the whole set.
- **Automatic layout:** General page > **Layout** stacks the health, rage, swing, cast and stance bars from top to bottom:
  - choose the gap and the alignment (left, center or right);
  - reorder them with the arrows;
  - modules you switch off take no room;
  - drag any bar to move the whole stack;
  - if you change it during a fight, the stance bar follows after combat.

## Warrior fun
In the settings window, pressing a button sometimes plays an execute sound and spills a little blood over the window with a battle line ("No mercy!"). Confirmed reset buttons always do. Closing the settings sounds a war horn with a battle cry. You can change the chance, turn off the battle cry or turn it all off on the General page. It is purely cosmetic: it follows the Sound switch and never touches the game.

## Configuration overview
- **General:** turn modules on or off, unlock frames, reset positions, preview mode, position of all modules (move everything, keep every frame on screen), the automatic layout (on or off, gap, alignment, order), the style picker, sounds and channel, warrior fun, addon language (game language, English or French), diagnostics, restore defaults.
- **Health Bar / Rage Bar:**
  - visibility (always, in combat, with a target, in combat or with a target);
  - size, scale, opacity in and out of combat, screen anchor (9 points), keep on screen, precise X/Y position;
  - style, texture, shading, border (WoW Forever shadow or frame, thin line, classic frame, none), background, spark, smooth animation;
  - text format, font style (12 one-click combinations), font, size, outline, shadow, alignment and color;
  - color mode (single, thresholds, gradient) with three colors and two thresholds;
  - alert threshold, glow, pulse and sound;
  - for the rage bar, attachment to the health bar (above or below, gap, matching width).
- **Swing Timer:** which bars to show and their colors, which weapons it shows with (any, two-handed only, one-handed only), fill direction, spacing, haste adjustment, swing sound, experimental out-of-reach dimming, countdown format, labels, and the game's own swing-timer option.
- **Cast Bar:** icon, spell name, fade-out, colors for casting, channeling, finished and failed, plus the same size, position, look and text options as the other bars.
- **Stances & Weapons:**
  - style, button look (WoW Forever frame, thin border, icon only), size, spacing, layout, scale, opacity and colors;
  - weapon icons, tooltips, and the key-binding text (font, size, outline, color);
  - for each stance, a main hand, off hand or shield, or an equipment set, with a preview of the exact click action and warnings (missing item, two-hander conflict, Dual Wield not learned).
- **Macro Builder:** category and template, template options (start attack, modifier key, stance, items), editable preview with a live character count and validation, macro name, character or account macro, create or update, select text to copy.
- **Profiles:** switch, create (or create one for this character), copy, reset, delete, export and import.
- **Safety & About:** version, principles, and the safety status of every feature.

## About WoW Forever restrictions
WoW Forever runs Classic-era content on the modern game engine, with Midnight-style addon rules. Two of those rules matter here:
- **The combat log is blocked for addons.** The swing timer therefore uses the game's own `PLAYER_SWING` event. An **enemy swing timer is not possible** reliably, so it is left out on purpose.
- **Some values can be hidden from addons**, for example rage and health in combat. Warrior Master passes hidden values straight to the game's own bar and text widgets, and uses the game's color curves for colors and glow, so the displays keep working. Sound alerts need a readable number and pause while values are hidden.

Details: [COMPATIBILITY.md](COMPATIBILITY.md).

## Project layout
```
WarriorMaster/            the addon (copy this folder into Interface/AddOns)
  WarriorMaster.toc       interface 16001, load order
  Bindings.xml            stance button key bindings
  Core/                   init, compatibility layer, events, combat queue, security,
                          styles, schema/validation, presets, serializer, database, slash, boot
  Locales/                enUS, frFR
  Widgets/                status bar widget, drag-and-drop movers, automatic layout
  Modules/                rage, health, swing, cast bar, stance, weapon picker,
                          macro templates/builder, preview
  Config/                 settings window, controls, pages, warrior effects
tests/                    offline test suite (mocked client, never the real game)
tools/                    API extractor and static security/compatibility audit
COMPATIBILITY.md          research on the target client and APIs
SECURITY.md               compliance decisions and feature classification
TESTING.md                offline results and the manual in-game checklist
```

## Development and testing
```bash
python -m pip install lupa
```
```bash
python tests/run_tests.py
```
This runs a Lua 5.1 syntax check, a TOC check, locale parity, the static audit and the behaviour tests against a mocked Forever client. Nothing launches or touches the game. In-game verification is a manual checklist for the player: [TESTING.md](TESTING.md).

## Status
- **Validated offline:** everything listed in TESTING.md, part 1.
- **Awaiting in-game confirmation:**
  - the swing event reaching addons;
  - colors and glow while values are hidden;
  - stance and weapon clicks;
  - `/equipslot item:ID` versus item names;
  - macro creation;
  - the out-of-reach dimming;
  - the cast bar, the one-click action bar placement and the warrior sounds.

  These are marked *Unverified* or *Restricted* on the Safety page until confirmed.

## License
No license file is included yet. Choose one before publishing. Warrior Master contains no code or artwork copied from other addons.
