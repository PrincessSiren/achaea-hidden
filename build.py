#!/usr/bin/env python3
"""Pack AchaeaHidden.lua plus the alias table below into a Mudlet package.

Produces two things next to this script:

  AchaeaHidden.xml       drag-and-drop installable, and committed to the repo
  AchaeaHidden.mpackage  the zip form Mudlet's package manager prefers

The shape is deliberate: real <Alias> elements inside one <AliasGroup> so they
can be read in Mudlet's Editor, and ALIASES as the single source of truth for
both the XML and the AchaeaHidden.COMMANDS table appended to the Lua, so the
in-game help cannot drift from what is installed.

The one trigger is not declared here. It is created at runtime with
tempRegexTrigger, from the pattern in the .lua, so there is one copy of it.
"""

from __future__ import annotations

import hashlib
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

HERE = Path(__file__).parent

# Where a recipient can get the Corresponding Source. GPL-3 asks that they be
# able to, and the .mpackage ships the *generated* .xml rather than the .lua and
# build.py that are the preferred form for making modifications -- so the
# package cannot serve as its own source, and has to say where the source is.
SOURCE_URL = "https://github.com/PrincessSiren/achaea-hidden"

# What the package manager's globe button opens -- dlgPackageManager reads
# `helpURL` and nothing else.
HELP_URL = SOURCE_URL

# The date that goes into config.lua as `created`, which Mudlet's package
# repository requires and its validator greps for. A constant rather than
# today's date, because both build artefacts are byte-reproducible. Move it
# when the version moves.
CREATED = "2026-10-01"
LUA = HERE / "AchaeaHidden.lua"
XML = HERE / "AchaeaHidden.xml"
MPACKAGE = HERE / "AchaeaHidden.mpackage"

PACKAGE_NAME = "AchaeaHidden"

# Mudlet's scmMudletXmlDefaultVersion (src/mudlet.h).
XML_VERSION = "1.001"

# (name, regex, lua, usage, help)
#
# No catch-all: Mudlet fires every matching alias rather than the first, so
# each form is spelled out.
ALIASES: list[tuple[str, str, str, str, str]] = [
    (
        "help",
        r"^hidden$",
        "AchaeaHidden.report()",
        "hidden",
        "whether it is on, what it sends, and this list",
    ),
    (
        "onoff",
        r"^hidden\s+(on|off)$",
        'AchaeaHidden.setEnabled(matches[2] == "on")',
        "hidden on|off",
        "clear the queue and diagnose on the venom line at all",
    ),
    (
        "clear",
        r"^hidden\s+clear\s+(on|off)$",
        'AchaeaHidden.setClear(matches[2] == "on")',
        "hidden clear on|off",
        "send clearqueue all before the rest, or leave the queue alone",
    ),
    (
        "send",
        r"^hidden\s+send\s+(.+)$",
        "AchaeaHidden.setSend(matches[2])",
        "hidden send <a;b>",
        "the commands it sends after that, separated by semicolons",
    ),
    (
        "gap",
        r"^hidden\s+gap\s+(\S+)$",
        "AchaeaHidden.setGap(matches[2])",
        "hidden gap <seconds>",
        "how long a repeat of the line is ignored for",
    ),
    (
        "diag",
        r"^hidden\s+diag$",
        "AchaeaHidden.diag()",
        "hidden diag",
        "build stamp, trigger count, where settings are saved",
    ),
]

XML_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE MudletPackage>
<MudletPackage version="{xml_version}">
    <ScriptPackage>
        <Script isActive="yes" isFolder="no">
            <name>{package}</name>
            <packageName>{package}</packageName>
            <script>{script}</script>
            <eventHandlerList />
        </Script>
    </ScriptPackage>
    <AliasPackage>
        <AliasGroup isActive="yes" isFolder="yes">
            <name>{package}</name>
            <script></script>
            <command></command>
            <packageName>{package}</packageName>
            <regex></regex>
{aliases}        </AliasGroup>
    </AliasPackage>
</MudletPackage>
"""

ALIAS_TEMPLATE = """            <Alias isActive="yes" isFolder="no">
                <name>{name}</name>
                <script>{script}</script>
                <command></command>
                <packageName>{package}</packageName>
                <regex>{regex}</regex>
            </Alias>
"""


def read_version(lua_source: str) -> str:
    for raw in lua_source.splitlines():
        line = raw.strip()
        if line.startswith("M.VERSION"):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return "0.0.0"


def lua_quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_stamp(lua_source: str) -> str:
    """Short digest of everything that ends up in the package.

    A content hash rather than a timestamp, because the .xml is committed: two
    builds with no source change must be byte-identical. `hidden diag` prints it
    back, which is the only reliable answer to "is Mudlet running what is on
    disk?" -- the version says what you expect whether or not you rebuilt.
    """
    material = lua_source + "\x00".join("\x00".join(row) for row in ALIASES)
    return hashlib.sha256(material.encode("utf-8")).hexdigest()[:8]


def commands_lua(lua_source: str) -> str:
    rows = "".join(
        f"    {{ usage = {lua_quote(usage)}, help = {lua_quote(help)} }},\n"
        for _name, _regex, _lua, usage, help in ALIASES
    )
    return (
        "\n-- Generated by build.py from its ALIASES table. Do not edit here.\n"
        f"AchaeaHidden.BUILD = {lua_quote(build_stamp(lua_source))}\n"
        f"AchaeaHidden.COMMANDS = {{\n{rows}}}\n"
    )


DESCRIPTION = f"""# AchaeaHidden

When a venom gives you an affliction without saying which, clear the queue and
diagnose.

The game's whole notice is one line:

```
You are confused as to the effects of the venom.
```

On that line the package sends `clearqueue all` and then `queue add bal
diagnose`, so the diagnose runs as soon as you have balance. A second
bite inside two seconds sends nothing more.

```
hidden
hidden off
hidden clear off
hidden send queue add bal diagnose
```

`hidden` is the full command list. What it sends is a setting, so it can be
changed without rebuilding anything.

Source and licence (GPL-3.0-or-later): {SOURCE_URL}"""


# The archive is built to be byte-identical anywhere, so that rebuilding a tag
# and comparing the digest is a check anyone can run. Two things had to give.
#
# The date. `writestr` with a plain string name takes `time.localtime()`, to
# the second, so two builds a second apart produced different archives -- easy
# to miss, because two builds inside the same second did not. 1980-01-01 is the
# earliest a zip can express, and nothing reads these back: Mudlet unzips into
# a profile directory and the dates there are the install's. `created` in
# config.lua is where a real date belongs.
#
# The compression. Deflate output is not defined by the format, it is whatever
# the linked zlib emits -- and Fedora's python links zlib-ng while an Ubuntu
# runner links stock zlib, so identical files gave different archives on the
# two machines. That is not a bug in either; there is no portable way to pin
# it. Storing the entries uncompressed takes the question away entirely, at
# 70KB against 22KB. Most of the difference is the GPL text, and the trade is
# worth it for a package whose whole claim is that you can check it yourself.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def zip_entry(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=ZIP_EPOCH)
    info.compress_type = zipfile.ZIP_STORED
    # A ZipInfo built by hand carries no mode at all, which some extractors
    # read as 0000. Say 0644 rather than leave it to them.
    info.external_attr = 0o644 << 16
    return info


def config_lua(version: str) -> str:
    """The package metadata Mudlet reads back out of the archive.

    Host::readPackageInfo runs this file as Lua and keeps every global that is
    a string, so a key added here is a key Mudlet's package manager can show.
    mpackage, title, version, created, author and description are the six the
    Mudlet package repository's validator requires; helpURL is what the package
    manager's globe button opens.
    """
    return (
        f'mpackage = "{PACKAGE_NAME}"\n'
        f'version = "{version}"\n'
        f'created = "{CREATED}"\n'
        f'author = "PrincessSiren"\n'
        f'title = "Diagnose a hidden affliction in Achaea"\n'
        f"description = [[{DESCRIPTION}]]\n"
        f'helpURL = "{HELP_URL}"\n'
        f'license = "GPL-3.0-or-later"\n'
        f'source = "{SOURCE_URL}"\n'
    )


def license_text() -> str:
    """The licence this package ships under.

    Looked for beside build.py first, then up the tree: a package that has been
    split out into its own repository carries its own copy, one still in the
    workshop shares the root one, and the same build.py works either way.

    It goes *inside* the .mpackage because Mudlet's package format has no
    licence field -- config.lua has no key for it, whatever else it carries --
    so this file is the only way the terms reach anyone who installs the
    package.
    """
    for path in (HERE / "LICENSE", *(p / "LICENSE" for p in HERE.parents)):
        if path.is_file():
            return path.read_text(encoding="utf-8")
    raise SystemExit("no LICENSE beside build.py or anywhere above it")


def build() -> None:
    handwritten = LUA.read_text(encoding="utf-8")
    lua_source = handwritten + commands_lua(handwritten)
    version = read_version(lua_source)
    stamp = build_stamp(handwritten)

    aliases = "".join(
        ALIAS_TEMPLATE.format(
            name=escape(name),
            script=escape(lua),
            package=PACKAGE_NAME,
            regex=escape(regex),
        )
        for name, regex, lua, _usage, _help in ALIASES
    )

    XML.write_text(
        XML_TEMPLATE.format(
            xml_version=XML_VERSION,
            package=PACKAGE_NAME,
            script=escape(lua_source),
            aliases=aliases,
        ),
        encoding="utf-8",
    )

    with zipfile.ZipFile(MPACKAGE, "w") as archive:
        for name, text in (
            (f"{PACKAGE_NAME}.xml", XML.read_text(encoding="utf-8")),
            ("config.lua", config_lua(version)),
            ("LICENSE", license_text()),
        ):
            archive.writestr(zip_entry(name), text)

    print(f"{PACKAGE_NAME} {version} build {stamp} ({len(ALIASES)} aliases)")
    print(f"  `hidden diag` in Mudlet should say build {stamp}; "
          f"anything else is a stale install")
    print(f"  wrote {XML.relative_to(HERE.parent)}")
    print(f"  wrote {MPACKAGE.relative_to(HERE.parent)}")


if __name__ == "__main__":
    build()
