#!/usr/bin/env python3
"""Warrior Master - static security and compatibility audit.

Scans the addon's Lua source (comments and strings removed) and checks:
  - no forbidden API is referenced (automation, code execution, combat log,
    chat/network, bindings, hooks, file or OS access);
  - no programmatic :Click() on any frame;
  - every global function the addon calls exists on WoW Forever 1.60.1:
    either documented in Blizzard_APIDocumentationGenerated (see
    tests/data/forever_api.lua) or a legacy global verified in Blizzard's
    own UI code for that build (LEGACY_GLOBALS, with the file that uses it);
  - every event the addon registers is documented for the client;
  - exceptions are explicit: a line may carry "wm-audit: allow <NAME>".

Usage:  python tools/audit.py        (exit code 1 on failure)
Only reads files; never touches the game client.
"""
import glob
import os
import re
import sys

FORBIDDEN = {
    # Code execution / environment access
    "loadstring": "runs arbitrary code", "load": "runs arbitrary code",
    "dofile": "file access", "loadfile": "file access", "require": "not available in WoW",
    "getfenv": "environment tampering", "setfenv": "environment tampering",
    "debug": "debug library", "io": "file access", "os": "OS access",
    "RunScript": "runs arbitrary code", "RunMacro": "runs a macro without a click",
    "RunMacroText": "runs a macro without a click",
    # Game actions (must only happen through secure buttons the player clicks)
    "CastSpellByName": "protected action", "CastSpellByID": "protected action",
    "CastShapeshiftForm": "protected action", "UseAction": "protected action",
    "UseInventoryItem": "protected action", "UseContainerItem": "protected action",
    "PickupInventoryItem": "item automation", "PickupContainerItem": "item automation",
    "EquipItemByName": "automatic equipment change", "EquipCursorItem": "automatic equipment change",
    "AutoEquipCursorItem": "automatic equipment change", "UseEquipmentSet": "automatic equipment change",
    "TargetUnit": "targeting automation", "AttackTarget": "combat automation",
    "StartAttack": "combat automation", "SpellStopCasting": "combat automation",
    "SpellStopTargeting": "combat automation", "SpellTargetUnit": "combat automation",
    "ClearTarget": "targeting automation",
    "SecureCmdUseItem": "secure command from insecure code",
    # Combat log (blocked on Forever)
    "CombatLogGetCurrentEventInfo": "combat log not available to addons on Forever",
    # Communication
    "SendChatMessage": "sends messages", "SendAddonMessage": "network communication",
    "C_ChatInfo": "network communication", "C_BattleNet": "network communication",
    # Bindings and hooks
    "SetBinding": "changes key bindings", "SetBindingClick": "changes key bindings",
    "SetOverrideBinding": "changes key bindings", "SetOverrideBindingClick": "changes key bindings",
    "hooksecurefunc": "hooks Blizzard code", "RegisterStateDriver": "secure state driver",
    "SecureHandlerWrapScript": "restricted environment snippets",
    # Settings
    "SetCVar": "changes game settings",
    # Blizzard tables the addon must not modify: writing to them from addon
    # code taints Blizzard's own handling (for example, Escape then gets
    # SpellStopCasting()/SpellStopTargeting() blocked and blamed on the addon).
    "UISpecialFrames": "modifies a Blizzard table",
    "StaticPopupDialogs": "modifies a Blizzard table",
    "RegisterGameMenuEscHandler": "adds addon code to Blizzard's Escape handler list (taint)",
    "GameMenuEscPriority": "Blizzard's Escape handler list (taint)",
}

FORBIDDEN_STRINGS = {
    "COMBAT_LOG_EVENT_UNFILTERED": "combat log is blocked for addons on Forever",
    "COMBAT_LOG_EVENT": "combat log is blocked for addons on Forever",
}

# Legacy globals that are not in the generated API documentation but exist in
# client 1.60.1.70862: each one is used by Blizzard's own UI code of that build.
LEGACY_GLOBALS = {
    "CreateFrame": "Blizzard_PersonalResourceDisplay/Blizzard_PersonalResourceDisplay.lua",
    "InCombatLockdown": "Blizzard_FrameXML/Mainline/TutorialFrame.lua",
    "GetInventoryItemID": "Blizzard_ActionBar/WoWLabs/ActionButtonOverrides.lua",
    "GetNumShapeshiftForms": "Blizzard_ActionBar/Shared/StanceBar.lua",
    "GetShapeshiftFormInfo": "Blizzard_ActionBar/Shared/StanceBar.lua",
    "GetShapeshiftFormCooldown": "Blizzard_ActionBar/Shared/StanceBar.lua",
    "GetCVarBool": "Blizzard_ActionBar/Shared/StanceBar.lua",
    "CreateMacro": "Blizzard_MacroUI/Blizzard_MacroIconSelector.lua",
    "EditMacro": "Blizzard_MacroUI/Blizzard_MacroUI.lua",
    "GetNumMacros": "Blizzard_MacroUI/Blizzard_MacroUI.lua",
    "GetMacroInfo": "Blizzard_MacroUI/Blizzard_MacroUI.lua",
    "PickupMacro": "Blizzard_MacroUI/Blizzard_MacroUI.lua",
    "PlaySound": "Blizzard_MacroUI/Blizzard_MacroUI.lua",
    "GetBindingKey": "Blizzard_ActionBar/Shared/ActionButton.lua",
    "geterrorhandler": "Blizzard_SharedXMLBase/ErrorUtil.lua",
    "CreateColor": "Blizzard_SharedXML/ColorUtil.lua",
    "RegisterGameMenuEscHandler": "Blizzard_GameMenuEsc/Blizzard_GameMenuEsc.lua",
    "UnitAttackSpeed": "Blizzard_SwingTimer/Blizzard_SwingTimer.lua",
    "GetAddOnMetadata": "fallback only, guarded (C_AddOns.GetAddOnMetadata preferred)",
}

LUA_BUILTINS = {
    "pairs", "ipairs", "type", "tostring", "tonumber", "select", "unpack", "error",
    "assert", "pcall", "xpcall", "setmetatable", "getmetatable", "rawget", "rawset",
    "next", "print", "math", "string", "table", "self",
}

# Events the client dispatches internally since 12.1; registration is
# attempted through pcall only to surface blocked actions.
INTERNAL_EVENTS = {"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN"}

LUA_KEYWORDS = {
    "and", "or", "not", "if", "elseif", "else", "then", "return", "while", "until",
    "in", "function", "local", "do", "end", "for", "repeat", "break", "nil", "true", "false",
}

TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\S")


def strip_lua(src):
    """Returns (code_without_comments_or_strings, list_of_strings) keeping line breaks."""
    out, strings = [], []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
                out.append("\n" * src.count("\n", i, end))
                i = end
            else:
                end = src.find("\n", i)
                i = n if end < 0 else end
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            end = src.find(close, i)
            end = n if end < 0 else end + len(close)
            strings.append(src[i:end])
            out.append('""' + "\n" * src.count("\n", i, end))
            i = end
            continue
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                j += 1
            strings.append(src[i + 1:j])
            out.append('""')
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), strings


def load_api(root):
    path = os.path.join(root, "tests", "data", "forever_api.lua")
    text = open(path, encoding="utf-8").read()
    sections = {}
    current = None
    for line in text.splitlines():
        m = re.match(r"\s{2}(\w+) = \{$", line)
        if m:
            current = m.group(1)
            sections[current] = set()
            continue
        m = re.match(r'\s{4}\["([^"]+)"\] = ', line)
        if m and current:
            sections[current].add(m.group(1))
    return sections


def allowed_on_line(original_lines, lineno, name):
    line = original_lines[lineno - 1] if 0 < lineno <= len(original_lines) else ""
    m = re.search(r"wm-audit: allow ([\w, ]+)", line)
    return bool(m) and name in [x.strip() for x in m.group(1).split(",")]


def audit_file(path, rel, api, problems, stats):
    original = open(path, encoding="utf-8").read()
    original_lines = original.splitlines()
    code, strings = strip_lua(original)
    lines = code.splitlines()

    declared = set()
    for m in re.finditer(r"\blocal\s+function\s+([A-Za-z_]\w*)", code):
        declared.add(m.group(1))
    for m in re.finditer(r"\blocal\s+([A-Za-z_][\w\s,]*?)(?:=|\n|$)", code):
        for name in m.group(1).split(","):
            declared.add(name.strip())
    for m in re.finditer(r"\bfunction\s*[\w.:]*\(([^)]*)\)", code):
        for name in m.group(1).split(","):
            declared.add(name.strip())
    for m in re.finditer(r"\bfor\s+([\w\s,]+?)\s+(?:=|in)\b", code):
        for name in m.group(1).split(","):
            declared.add(name.strip())

    for lineno, line in enumerate(lines, 1):
        tokens = TOKEN_RE.findall(line)
        for idx, tok in enumerate(tokens):
            prev = tokens[idx - 1] if idx > 0 else ""
            nxt = tokens[idx + 1] if idx + 1 < len(tokens) else ""
            if prev in (".", ":"):
                if prev == ":" and tok == "Click" and nxt == "(":
                    problems.append("%s:%d calls :Click() (programmatic click)" % (rel, lineno))
                if tok in FORBIDDEN and not allowed_on_line(original_lines, lineno, tok):
                    problems.append("%s:%d uses %s (%s)" % (rel, lineno, tok, FORBIDDEN[tok]))
                continue
            if tok in FORBIDDEN and tok not in declared and not allowed_on_line(original_lines, lineno, tok):
                problems.append("%s:%d uses %s (%s)" % (rel, lineno, tok, FORBIDDEN[tok]))
            # Global function calls (direct, or passed to pcall) and namespaced C_ calls
            prev2 = tokens[idx - 2] if idx > 1 else ""
            called = nxt == "(" or (prev == "(" and prev2 == "pcall" and nxt in (",", ")"))
            if called and re.match(r"[A-Za-z_]", tok) and prev != "function" and tok not in declared:
                if tok in LUA_BUILTINS or tok in LUA_KEYWORDS:
                    continue
                stats["calls"].add(tok)
                if tok in api.get("protected", ()):
                    problems.append("%s:%d uses %s, a protected function (Blizzard UI only)" % (rel, lineno, tok))
                if tok not in api["functions"] and tok not in LEGACY_GLOBALS:
                    problems.append("%s:%d calls %s, which is not a known WoW Forever API" % (rel, lineno, tok))
            if tok.startswith("C_") and nxt == "." and idx + 2 < len(tokens):
                name = tok + "." + tokens[idx + 2]
                stats["namespaced"].add(name)
                if name in api.get("protected", ()):
                    problems.append("%s:%d uses %s, a protected function (Blizzard UI only)" % (rel, lineno, name))
                if name not in api["functions"]:
                    problems.append("%s:%d uses %s, which is not documented for WoW Forever" % (rel, lineno, name))

    for s in strings:
        for bad, why in FORBIDDEN_STRINGS.items():
            if bad in s:
                problems.append("%s references %s (%s)" % (rel, bad, why))

    for m in re.finditer(r"Register(?:Unit)?Event\(\s*\"([A-Z_]+)\"", original):
        event = m.group(1)
        stats["events"].add(event)
        if event not in api["events"] and event not in INTERNAL_EVENTS:
            problems.append("%s registers %s, which is not a documented event" % (rel, event))


SELF_TEST_BAD = {
    "direct cast": "CastSpellByName('Charge')",
    "indirect cast": "local f = CastSpellByID\nf(100)",
    "programmatic click": "WarriorMasterStanceButton1:Click()",
    "code execution": "local f = loadstring(text)",
    "macro execution": "C_Macro.RunMacroText('/cast Charge')",
    "combat log": "frame:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')",
    "cvar change": "C_CVar.SetCVar('a', '1')",
    "unknown api": "SomeRetailOnlyFunction()",
    "unknown event": 'f:RegisterEvent("NOT_A_REAL_EVENT")',
    "binding change": "SetOverrideBindingClick(owner, true, 'F', 'Btn')",
    "hook": "hooksecurefunc('ToggleGameMenu', fn)",
    "escape handler": "RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, fn)",
    "special frames": "table.insert(UISpecialFrames, 'MyFrame')",
    "stop targeting": "SpellStopTargeting()",
    "protected call": "C_TooltipComparison.CompareItem(a, b)",
}
SELF_TEST_GOOD = "local x = math.floor(1.5) -- CastSpellByName in a comment\nlocal s = 'CastSpellByID in a string'\nprint(x, s)"


def self_test(root, api):
    """Checks that the audit flags every known-bad snippet and accepts a clean one."""
    import tempfile
    missed = []
    with tempfile.TemporaryDirectory() as tmp:
        for label, snippet in list(SELF_TEST_BAD.items()) + [("clean", SELF_TEST_GOOD)]:
            path = os.path.join(tmp, "snippet.lua")
            with open(path, "w", encoding="utf-8") as f:
                f.write(snippet + "\n")
            found = []
            audit_file(path, "snippet.lua", api, found, {"calls": set(), "namespaced": set(), "events": set()})
            if label == "clean" and found:
                missed.append("false positive on clean code: " + "; ".join(found))
            elif label != "clean" and not found:
                missed.append("not detected: " + label)
    return missed


def run(root):
    """Yields (ok, label, detail) tuples."""
    api = load_api(root)
    missed = self_test(root, api)
    yield (not missed, "audit self-test: %d known violations detected, clean code accepted" % len(SELF_TEST_BAD), "\n".join(missed))
    problems = []
    stats = {"calls": set(), "namespaced": set(), "events": set()}
    files = sorted(glob.glob(os.path.join(root, "WarriorMaster", "**", "*.lua"), recursive=True))
    for path in files:
        audit_file(path, os.path.relpath(path, root).replace("\\", "/"), api, problems, stats)
    security = [p for p in problems if ("uses" in p and "not documented" not in p) or ":Click()" in p or "references" in p or "protected function" in p]
    compat = [p for p in problems if p not in security]
    yield (not security, "no forbidden APIs, programmatic clicks or combat-log access (%d files)" % len(files), "\n".join(security))
    yield (not compat, "%d global calls, %d C_ APIs and %d events exist on WoW Forever 1.60.1"
           % (len(stats["calls"]), len(stats["namespaced"]), len(stats["events"])), "\n".join(compat))
    legacy = sorted(c for c in stats["calls"] if c in LEGACY_GLOBALS)
    yield (True, "legacy globals verified in Blizzard UI code: " + ", ".join(legacy), "")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    failed = False
    for ok, label, detail in run(root):
        print(("PASS  " if ok else "FAIL  ") + label)
        if not ok:
            failed = True
            print("      " + detail.replace("\n", "\n      "))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
