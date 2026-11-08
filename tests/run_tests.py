#!/usr/bin/env python3
"""Warrior Master - offline validation.

Runs, in order:
  1. Lua 5.1 syntax check of every addon file
  2. TOC check (interface 16001, every listed file exists, no unlisted Lua)
  3. Locale parity (frFR defines exactly the enUS keys)
  4. Static security / compatibility audit (tools/audit.py)
  5. Behaviour tests (tests/test_*.lua) against the mocked client

Requirements: Python 3.9+ and the `lupa` package (embedded Lua 5.1):
    python -m pip install lupa

Nothing here launches, connects to or reads the memory of World of Warcraft.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON = os.path.join(ROOT, "WarriorMaster")
sys.path.insert(0, os.path.join(ROOT, "tools"))

try:
    from lupa import lua51
except ImportError:  # pragma: no cover
    print("lupa is required: python -m pip install lupa")
    sys.exit(2)

import audit  # noqa: E402


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def toc_entries():
    entries, interface = [], None
    for raw in read(os.path.join(ADDON, "WarriorMaster.toc")).splitlines():
        line = raw.strip()
        if line.startswith("## Interface:"):
            interface = line.split(":", 1)[1].strip()
        if not line or line.startswith("#"):
            continue
        entries.append(line.replace("\\", "/"))
    return entries, interface


class Report:
    def __init__(self):
        self.failures = 0
        self.passes = 0

    def ok(self, label):
        self.passes += 1
        print("  PASS  " + label)

    def fail(self, label, detail=""):
        self.failures += 1
        print("  FAIL  " + label)
        if detail:
            for line in str(detail).splitlines()[:40]:
                print("        " + line)


def new_runtime(files):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("FOREVER_API = (function() " + read(os.path.join(HERE, "data", "forever_api.lua")) + "\nend)()")
    rt.execute(read(os.path.join(HERE, "wowmock.lua")))
    g = rt.globals()
    g.ADDON_FILE_PATHS = rt.table(*[f for f in files])
    g.ADDON_FILE_SOURCES = rt.table(*[read(os.path.join(ADDON, f)) for f in files])
    rt.execute(read(os.path.join(HERE, "harness.lua")))
    return rt


def check_syntax(report):
    print("\n[1] Lua 5.1 syntax")
    rt = lua51.LuaRuntime()
    compile_ = rt.eval("function(src, name) local f, err = loadstring(src, name) return err end")
    paths = sorted(glob.glob(os.path.join(ADDON, "**", "*.lua"), recursive=True))
    paths += sorted(glob.glob(os.path.join(HERE, "*.lua")))
    bad = 0
    for path in paths:
        err = compile_(read(path), "@" + os.path.relpath(path, ROOT))
        if err:
            bad += 1
            report.fail("syntax " + os.path.relpath(path, ROOT), err)
    if not bad:
        report.ok("%d Lua files compile under Lua 5.1" % len(paths))


def check_toc(report):
    print("\n[2] TOC")
    entries, interface = toc_entries()
    if interface == "16001":
        report.ok("## Interface: 16001 (WoW Forever 1.60.1)")
    else:
        report.fail("interface version", "found %r, expected 16001" % interface)
    missing = [e for e in entries if not os.path.isfile(os.path.join(ADDON, e))]
    if missing:
        report.fail("listed files exist", "\n".join(missing))
    else:
        report.ok("all %d listed files exist" % len(entries))
    listed = set(entries)
    on_disk = {os.path.relpath(p, ADDON).replace("\\", "/") for p in glob.glob(os.path.join(ADDON, "**", "*.lua"), recursive=True)}
    unlisted = sorted(on_disk - listed)
    if unlisted:
        report.fail("every Lua file is listed in the TOC", "\n".join(unlisted))
    else:
        report.ok("no unlisted Lua files")
    if os.path.isfile(os.path.join(ADDON, "Bindings.xml")):
        report.ok("Bindings.xml present")


def check_locales(report):
    print("\n[3] Locales")
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("ns = { Locales = {} }")
    for code in ("enUS", "frFR"):
        rt.execute("local chunk = loadstring(...); chunk('WarriorMaster', ns)", read(os.path.join(ADDON, "Locales", code + ".lua")))
    keys = {}
    for code in ("enUS", "frFR"):
        table = rt.eval("ns.Locales.%s" % code)
        keys[code] = {k: table[k] for k in table}
    missing = sorted(set(keys["enUS"]) - set(keys["frFR"]))
    extra = sorted(set(keys["frFR"]) - set(keys["enUS"]))
    if missing or extra:
        report.fail("frFR matches enUS keys", "missing: %s\nextra: %s" % (missing, extra))
    else:
        report.ok("frFR defines all %d enUS keys" % len(keys["enUS"]))
    # Placeholders must match, otherwise :format() could fail in one language.
    bad = []
    for key, en in keys["enUS"].items():
        fr = keys["frFR"].get(key)
        if fr is None:
            continue
        if re.findall(r"%[ds%%]", en) != re.findall(r"%[ds%%]", fr):
            bad.append(key)
    if bad:
        report.fail("format placeholders match between locales", ", ".join(bad))
    else:
        report.ok("format placeholders match between locales")
    # Every L.KEY / L["KEY"] used in the code must exist in enUS.
    used = set()
    for path in glob.glob(os.path.join(ADDON, "**", "*.lua"), recursive=True):
        src = read(path)
        used.update(re.findall(r"\bL\.([A-Z][A-Z0-9_]+)", src))
        used.update(re.findall(r"\bL\[\"([A-Z][A-Z0-9_]+)\"\]", src))
        used.update(re.findall(r"\bns\.L\.([A-Z][A-Z0-9_]+)", src))
    unknown = sorted(k for k in used if k not in keys["enUS"])
    if unknown:
        report.fail("every referenced string exists", ", ".join(unknown))
    else:
        report.ok("all %d directly referenced strings exist" % len(used))


def run_behaviour_tests(report, only=None):
    print("\n[5] Behaviour tests (mocked client)")
    files, _ = toc_entries()
    lua_files = [f for f in files if f.endswith(".lua")]
    for test_path in sorted(glob.glob(os.path.join(HERE, "test_*.lua"))):
        name = os.path.basename(test_path)
        if only and only not in name:
            continue
        probe = new_runtime(lua_files)
        probe.execute(read(test_path))
        count = int(probe.eval("#TESTS"))
        print("  -- %s (%d)" % (name, count))
        for i in range(1, count + 1):
            rt = new_runtime(lua_files)
            rt.execute(read(test_path))
            title = rt.eval("TESTS[%d].name" % i)
            try:
                ok, message = rt.eval("RUN_TEST(%d)" % i)
            except Exception as exc:  # Lua error outside the protected call
                ok, message = False, str(exc)
            if ok:
                report.ok(title)
            else:
                report.fail(title, message)


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    report = Report()
    if not only:
        check_syntax(report)
        check_toc(report)
        check_locales(report)
        print("\n[4] Static audit")
        for ok, label, detail in audit.run(ROOT):
            (report.ok(label) if ok else report.fail(label, detail))
    run_behaviour_tests(report, only)
    print("\n%d passed, %d failed" % (report.passes, report.failures))
    return 1 if report.failures else 0


if __name__ == "__main__":
    sys.exit(main())
