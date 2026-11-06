"""Port the macOS IntelliJ keymap to Windows, keeping the same physical chords.

IntelliJ's Java runtime reports no modifier for the Win key on Windows, so every
``meta`` shortcut in a macOS keymap is unreachable there. This script resolves the
effective macOS keymap (including plugin shortcuts) and writes two files that must
stay in step:

* ``macOS (Ronen) Windows``, an IntelliJ keymap in the IDE's ``keymaps`` directory.
* ``intellij-mac-hotkeys.ahk``, included by komorebic-hotkeys.ahk, which turns the
  physical Cmd (Win) chords into the chords that keymap binds.

Physical Ctrl stays real Ctrl, so control characters keep working in the IDE's
terminal. Cmd+X becomes Ctrl+X unless Ctrl+X means something else on the Mac; those
Cmd chords become an otherwise unused F13-F24 chord instead.

Re-run after changing the macOS keymap or upgrading IntelliJ, then restart IntelliJ
and reload the AutoHotkey script:

    python intellij-mac-keymap.py
"""
import glob
import os
import re
import xml.etree.ElementTree as ET
import zipfile
from collections import defaultdict

SOURCE_KEYMAP_FILE = "macOS _Ronen_.xml"
OUTPUT_KEYMAP_NAME = "macOS (Ronen) Windows"
OUTPUT_KEYMAP_FILE = "macOS _Ronen_ Windows.xml"
OUTPUT_AHK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "intellij-mac-hotkeys.ahk")
MAC_KEYMAP = "Mac OS X 10.5+"
DEFAULT_KEYMAP = "$default"
IDEA_WINDOW = "ahk_exe idea64.exe"

ARROWS = ("LEFT", "RIGHT", "UP", "DOWN")
F_KEYS = [f"F{n}" for n in range(13, 25)]
# Modifier sets used to extend the F13-F24 chords, least intrusive first.
CODE_MODIFIERS = [(), ("shift",), ("ctrl",), ("shift", "ctrl"), ("alt",), ("shift", "alt"),
                  ("ctrl", "alt"), ("shift", "ctrl", "alt")]
AHK_MODIFIERS = {"ctrl": "^", "alt": "!", "shift": "+", "meta": "#"}

# Key names IntelliJ uses, mapped to AutoHotkey key names. Punctuation uses virtual
# key codes so it needs no escaping and does not depend on the active layout.
AHK_KEYS = {
    "BACK_SPACE": "Backspace", "ENTER": "Enter", "ESCAPE": "Esc", "SPACE": "Space", "TAB": "Tab",
    "DELETE": "Delete", "INSERT": "Insert", "HOME": "Home", "END": "End", "PAGE_UP": "PgUp",
    "PAGE_DOWN": "PgDn", "UP": "Up", "DOWN": "Down", "LEFT": "Left", "RIGHT": "Right",
    "MINUS": "vkBD", "EQUALS": "vkBB", "OPEN_BRACKET": "vkDB", "CLOSE_BRACKET": "vkDD",
    "BACK_SLASH": "vkDC", "SEMICOLON": "vkBA", "QUOTE": "vkDE", "COMMA": "vkBC", "PERIOD": "vkBE",
    "SLASH": "vkBF", "BACK_QUOTE": "vkC0", "ADD": "NumpadAdd", "SUBTRACT": "NumpadSub",
    "MULTIPLY": "NumpadMult", "DIVIDE": "NumpadDiv", "DECIMAL": "NumpadDot",
    "CONTEXT_MENU": "AppsKey", "PAUSE": "Pause",
}
AHK_KEYS.update({f"NUMPAD{n}": f"Numpad{n}" for n in range(10)})
AHK_KEYS.update({f"F{n}": f"F{n}" for n in range(1, 25)})
AHK_KEYS.update({chr(c): chr(c).lower() for c in range(ord("A"), ord("Z") + 1)})
AHK_KEYS.update({str(n): str(n) for n in range(10)})


def chord(mods, key):
    """Build a normalized chord.

    :param mods: iterable of modifier names
    :param key: IntelliJ key name
    :return: tuple of (frozenset of modifiers, key)
    """
    return frozenset(mods), key


def parse_stroke(stroke):
    """Parse an IntelliJ keystroke string.

    :param stroke: a keystroke such as ``control shift A``
    :return: the normalized chord, or None for forms that cannot be ported
    """
    tokens = stroke.replace("control", "ctrl").split()
    mods = [t for t in tokens if t in AHK_MODIFIERS]
    rest = [t for t in tokens if t not in AHK_MODIFIERS]
    if len(rest) != 1:
        return None
    return chord(mods, rest[0].upper())


def format_stroke(parsed):
    """Format a chord as an IntelliJ keystroke string.

    :param parsed: a normalized chord
    :return: the keystroke string
    """
    mods, key = parsed
    return " ".join([m for m in ("shift", "ctrl", "alt", "meta") if m in mods] + [key])


def with_each(mods_list, keys):
    """Expand modifier sets and keys into a set of chords.

    :param mods_list: list of modifier tuples
    :param keys: iterable of key names
    :return: set of normalized chords
    """
    return {chord(mods, key) for mods in mods_list for key in keys}


# Chords the window manager owns on both machines (komorebic-hotkeys.ahk and
# .aerospace.toml), which IntelliJ therefore never receives on the Mac either.
WM_OWNED = (
    with_each([("ctrl",), ("shift", "ctrl")], ARROWS + ("MINUS", "EQUALS"))
    | with_each([("ctrl", "alt")], ("LEFT", "RIGHT"))
    | with_each([("shift", "ctrl")], "123456")
    | with_each([("alt",)], tuple("123456") + ("SLASH", "COMMA"))
)
# Cmd chords that belong to the OS, Deskflow or the window manager rather than the IDE.
CMD_RESERVED = (
    with_each([("meta",), ("ctrl", "meta")], ("SPACE",))
    | with_each([("meta",), ("shift", "meta")], ("TAB",))
    | with_each([("shift", "meta")], "345")
    | with_each([("ctrl", "alt", "meta"), ("shift", "ctrl", "alt", "meta")], ARROWS)
)
# Cmd chords kept on real Ctrl even though Ctrl means something else on the Mac, because
# plain text fields in dialogs only understand the real editing shortcuts. The physical
# Ctrl versions of these chords therefore act like Cmd in IntelliJ, not like their macOS
# actions.
TEXT_FIELD_CHORDS = with_each([("meta",)], "ACVXZ") | {chord(("shift", "meta"), "Z")}
# Left off Ctrl+A so that physical Ctrl+A still reaches the shell in the IDE's terminal.
TERMINAL_ACTIONS_DROPPED = {("Terminal.SelectAll", chord(("meta",), "A"))}


def shortcuts_of(element):
    """Read the shortcut children of a keymap ``action`` element.

    :param element: the XML element
    :return: list of (kind, first, second) tuples, where kind is ``keyboard``, ``mouse``
        or ``gesture``; ``second`` holds a keyboard shortcut's second stroke or a
        gesture's modifier, and is None otherwise
    """
    found = []
    for child in element:
        if child.tag == "keyboard-shortcut":
            found.append(("keyboard", child.get("first-keystroke"), child.get("second-keystroke")))
        elif child.tag == "mouse-shortcut":
            found.append(("mouse", child.get("keystroke"), None))
        elif child.tag == "keyboard-gesture-shortcut":
            found.append(("gesture", child.get("keystroke"), child.get("modifier")))
    return found


def load_keymap(path):
    """Load a keymap file.

    :param path: path of the keymap XML file
    :return: dict of action id to its list of shortcuts
    """
    root = ET.parse(path).getroot()
    return {action.get("id"): shortcuts_of(action) for action in root.findall("action")}


def add_plugin_shortcuts(xml_bytes, default_map, mac_map):
    """Merge the shortcuts a plugin descriptor registers into the keymap tables.

    :param xml_bytes: raw content of a descriptor XML file
    :param default_map: the ``$default`` table to update
    :param mac_map: the macOS table to update
    """
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        return
    for element in root.iter():
        if element.tag not in ("action", "group") or not element.get("id"):
            continue
        for child in element:
            target = {DEFAULT_KEYMAP: default_map, MAC_KEYMAP: mac_map}.get(child.get("keymap"))
            if target is None or child.get("remove") == "true":
                continue
            if child.tag == "keyboard-shortcut" and child.get("first-keystroke"):
                shortcut = ("keyboard", child.get("first-keystroke"), child.get("second-keystroke"))
            elif child.tag == "mouse-shortcut" and child.get("keystroke"):
                shortcut = ("mouse", child.get("keystroke"), None)
            else:
                continue
            target.setdefault(element.get("id"), []).append(shortcut)


def scan_plugins(install_dir, config_dir, default_map, mac_map):
    """Scan bundled and installed plugin jars for keymap shortcuts.

    :param install_dir: IntelliJ's installation directory
    :param config_dir: IntelliJ's configuration directory
    :param default_map: the ``$default`` table to update
    :param mac_map: the macOS table to update
    """
    patterns = [
        os.path.join(install_dir, "lib", "**", "*.jar"),
        os.path.join(install_dir, "plugins", "*", "lib", "**", "*.jar"),
        os.path.join(config_dir, "plugins", "*", "lib", "**", "*.jar"),
    ]
    for pattern in patterns:
        for jar in glob.glob(pattern, recursive=True):
            try:
                with zipfile.ZipFile(jar) as archive:
                    for name in archive.namelist():
                        is_descriptor = name.endswith(".xml") and (
                            name.startswith("META-INF/") or "/" not in name)
                        if is_descriptor:
                            add_plugin_shortcuts(archive.read(name), default_map, mac_map)
            except (zipfile.BadZipFile, OSError):
                continue


def load_bundled_keymap(install_dir, name):
    """Read one of IntelliJ's bundled keymaps out of its resources jar.

    :param install_dir: IntelliJ's installation directory
    :param name: the keymap name
    :return: dict of action id to its list of shortcuts
    """
    with zipfile.ZipFile(os.path.join(install_dir, "lib", "intellij.platform.resources.jar")) as archive:
        with archive.open(f"keymaps/{name}.xml") as handle:
            root = ET.parse(handle).getroot()
    return {action.get("id"): shortcuts_of(action) for action in root.findall("action")}


def to_mac(stroke):
    """Apply IntelliJ's conversion of an inherited ``$default`` shortcut to macOS.

    :param stroke: a keystroke from the default keymap, or None
    :return: the same keystroke with Ctrl converted to Cmd, or None
    """
    return re.sub(r"\b(control|ctrl)\b", "meta", stroke) if stroke else None


def effective_keymap(install_dir, config_dir):
    """Resolve the macOS keymap exactly as the IDE would on a Mac.

    :param install_dir: IntelliJ's installation directory
    :param config_dir: IntelliJ's configuration directory
    :return: dict of action id to its list of macOS shortcuts
    """
    default_map = load_bundled_keymap(install_dir, DEFAULT_KEYMAP)
    mac_map = load_bundled_keymap(install_dir, MAC_KEYMAP)
    scan_plugins(install_dir, config_dir, default_map, mac_map)
    effective = {
        action: [
            (kind, first, second) if kind == "gesture" else (kind, to_mac(first), to_mac(second))
            for kind, first, second in shortcuts
        ]
        for action, shortcuts in default_map.items()
    }
    effective.update(mac_map)
    effective.update(load_keymap(os.path.join(config_dir, "keymaps", SOURCE_KEYMAP_FILE)))
    return effective


def reachable_strokes(effective):
    """List every keyboard stroke of the macOS keymap with the actions it triggers.

    :param effective: the effective macOS keymap
    :return: dict of normalized chord to the set of action ids using it
    """
    actions_by_chord = defaultdict(set)
    for action, shortcuts in effective.items():
        for kind, first, second in shortcuts:
            if kind != "keyboard":
                continue
            for stroke in (first, second):
                parsed = parse_stroke(stroke) if stroke else None
                if parsed and parsed[1] in AHK_KEYS:
                    actions_by_chord[parsed].add(action)
    return actions_by_chord


def assign_cmd_chords(actions_by_chord):
    """Decide which Windows chord each physical Cmd chord is sent as.

    :param actions_by_chord: output of :func:`reachable_strokes`
    :return: dict of physical Cmd chord to the chord IntelliJ receives on Windows
    """
    codes = iter(chord(mods, key) for mods in CODE_MODIFIERS for key in F_KEYS)
    mapping = {}
    for physical in sorted(actions_by_chord, key=format_stroke):
        mods, key = physical
        if "meta" not in mods or physical in CMD_RESERVED:
            continue
        renamed = chord(({"ctrl" if m == "meta" else m for m in mods}), key)
        same_actions = actions_by_chord.get(renamed, set()) == actions_by_chord[physical]
        ctrl_is_free = renamed not in actions_by_chord or renamed in WM_OWNED or same_actions
        if physical in TEXT_FIELD_CHORDS or ("ctrl" not in mods and ctrl_is_free):
            mapping[physical] = renamed
        else:
            mapping[physical] = next(codes)
    return mapping


def translate_stroke(stroke, mapping):
    """Translate a macOS keystroke to the keystroke the Windows keymap binds.

    :param stroke: a macOS keystroke string
    :param mapping: output of :func:`assign_cmd_chords`
    :return: the Windows keystroke, or None if the chord never reaches the IDE
    """
    parsed = parse_stroke(stroke)
    if parsed is None or parsed[1] not in AHK_KEYS:
        return None
    if "meta" in parsed[0]:
        target = mapping.get(parsed)
        return format_stroke(target) if target else None
    kept_on_cmd = chord(({"meta" if m == "ctrl" else m for m in parsed[0]}), parsed[1])
    if parsed in WM_OWNED or kept_on_cmd in TEXT_FIELD_CHORDS:
        return None
    return format_stroke(parsed)


def translate_mouse(stroke):
    """Translate a macOS mouse shortcut for the Cmd+click hotkeys in the AHK script.

    :param stroke: a mouse keystroke such as ``meta button1``
    :return: the Windows mouse keystroke, or None for physical Ctrl+click, which
        macOS treats as a right click and IntelliJ cannot tell apart from Cmd+click,
        and for force touch, which Windows does not have
    """
    tokens = stroke.replace("control", "ctrl").split()
    if "ctrl" in tokens or "Force" in tokens:
        return None
    return " ".join("ctrl" if token == "meta" else token for token in tokens)


def build_keymap_xml(effective, mapping):
    """Build the translated keymap document.

    :param effective: the effective macOS keymap
    :param mapping: output of :func:`assign_cmd_chords`
    :return: the root XML element of the new keymap
    """
    root = ET.Element("keymap", {"version": "1", "name": OUTPUT_KEYMAP_NAME, "parent": DEFAULT_KEYMAP,
                                 "disable-mnemonics": "true"})
    for action in sorted(effective):
        element = ET.SubElement(root, "action", {"id": action})
        seen = set()
        for kind, first, second in effective[action]:
            if kind == "gesture":
                ET.SubElement(element, "keyboard-gesture-shortcut", {"keystroke": first, "modifier": second})
                continue
            if kind == "mouse":
                translated = translate_mouse(first)
                if translated and translated not in seen:
                    seen.add(translated)
                    ET.SubElement(element, "mouse-shortcut", {"keystroke": translated})
                continue
            parsed = parse_stroke(first)
            if parsed and (action, parsed) in TERMINAL_ACTIONS_DROPPED:
                continue
            new_first = translate_stroke(first, mapping)
            new_second = translate_stroke(second, mapping) if second else None
            if new_first is None or (second and new_second is None) or (new_first, new_second) in seen:
                continue
            seen.add((new_first, new_second))
            attributes = {"first-keystroke": new_first}
            if new_second:
                attributes["second-keystroke"] = new_second
            ET.SubElement(element, "keyboard-shortcut", attributes)
    ET.indent(root)
    return root


def ahk_hotkey(physical):
    """Format a physical chord as an AutoHotkey hotkey label.

    :param physical: a normalized chord
    :return: the hotkey label
    """
    mods, key = physical
    return "".join(AHK_MODIFIERS[m] for m in ("ctrl", "alt", "shift", "meta") if m in mods) + AHK_KEYS[key]


def ahk_send(target):
    """Format a chord as an AutoHotkey ``Send`` key string.

    :param target: a normalized chord
    :return: the key string
    """
    mods, key = target
    name = AHK_KEYS[key]
    prefix = "".join(AHK_MODIFIERS[m] for m in ("ctrl", "alt", "shift") if m in mods)
    return prefix + (name if len(name) == 1 else "{" + name + "}")


def write_ahk(mapping, path):
    """Write the AutoHotkey hotkeys for the physical Cmd chords.

    :param mapping: output of :func:`assign_cmd_chords`
    :param path: the output file
    """
    lines = [
        "; GENERATED by intellij-mac-keymap.py - edit that script, not this file.",
        "; Sends each physical Cmd (Win) chord of the macOS IntelliJ keymap as the chord the",
        f'; "{OUTPUT_KEYMAP_NAME}" keymap binds, because IntelliJ cannot see the Win key.',
        f'#HotIf WinActive("{IDEA_WINDOW}")',
    ]
    for physical in sorted(mapping, key=ahk_hotkey):
        lines.append(f'{ahk_hotkey(physical)}:: Send("{ahk_send(mapping[physical])}")')
    lines.append("#HotIf")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def find_config_dir():
    """Find the newest IntelliJ IDEA configuration directory.

    :return: the configuration directory's path
    """
    candidates = glob.glob(os.path.join(os.environ["APPDATA"], "JetBrains", "IntelliJIdea*"))
    return max(candidates, key=lambda path: os.path.basename(path))


def main():
    """Generate the Windows keymap and its AutoHotkey hotkeys."""
    config_dir = find_config_dir()
    version = os.path.basename(config_dir).removeprefix("IntelliJIdea")
    install_dir = os.path.join(os.environ["ProgramFiles"], "JetBrains", f"IntelliJ IDEA {version}")
    effective = effective_keymap(install_dir, config_dir)
    actions_by_chord = reachable_strokes(effective)
    mapping = assign_cmd_chords(actions_by_chord)

    keymap_path = os.path.join(config_dir, "keymaps", OUTPUT_KEYMAP_FILE)
    ET.ElementTree(build_keymap_xml(effective, mapping)).write(keymap_path, encoding="unicode")
    write_ahk(mapping, OUTPUT_AHK)

    coded = sum(1 for target in mapping.values() if target[1] in F_KEYS)
    print(f"Wrote {keymap_path}")
    print(f"Wrote {OUTPUT_AHK}")
    print(f"{len(mapping)} Cmd chords, {coded} sent as F13-F24 chords")


if __name__ == "__main__":
    main()
