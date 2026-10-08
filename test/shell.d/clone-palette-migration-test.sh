#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

migration = Path(sys.argv[1]) / "migrations/1791448028.sh"

def check(condition, description):
  if not condition:
    print("not ok - " + description, flush=True)
    raise SystemExit(1)
  print("ok - " + description, flush=True)

with tempfile.TemporaryDirectory() as temporary:
  home = Path(temporary)
  plugins = home / ".config/omarchy/plugins"
  environment = dict(os.environ, HOME=str(home))
  def run():
    result = subprocess.run(["bash", "-euo", "pipefail", str(migration)], env=environment, check=True, capture_output=True, text=True)
    print(result.stdout, end="")
    return result.stderr

  run()
  check(not plugins.exists(), "missing plugin directory is a no-op")

  def fixture(name, source, manifest={"omarchy": {"clonedFrom": "omarchy.clock"}}, filename="Main.qml"):
    directory = plugins / name
    directory.mkdir(parents=True, exist_ok=True)
    if manifest is not None:
      (directory / "manifest.json").write_text(json.dumps(manifest))
    file = directory / filename
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(source.encode())
    return file

  original = '''import QtQuick 6.11
import qs.Commons
Item {
  property color custom: Color.accent // user customization: 
  property color spaced: Color /* keep comment */ .foreground
  property color qualified: Commons.Color.background
  property color other: Something.Color.accent
  property string label: "Color.accent"
  property string escaped: "quote \\\" Color.accent"
  property string single: 'Color.foreground'
  property string template: `Color.background`
  // Color.foreground
  /* Color.background */
  Connections { target: Color; function onAccentChanged() {} }
  property int radius: Style.space(7)
}
'''
  main = fixture("custom clone with spaces", original)
  main.chmod(0o640)
  manifest_before = main.with_name("manifest.json").read_bytes()
  already = fixture("already-qualified", "import QtQuick\nimport qs.Commons as Commons\nItem { property color value: Commons.Color.accent }\n")
  mixed = fixture("mixed", "import QtQuick\nimport qs.Commons as Commons\nItem { property color a: Commons.Color.accent; property color b: Color.foreground }\n")
  alias = fixture("existing-alias", "import QtQuick\nimport qs.Commons 1.0 as Palette\nItem { property color a: Palette.Color.accent; property color b: Color.foreground }\n")
  collision = fixture("alias-collision", "import QtQuick as Commons\nimport qs.Commons\nItem { property color a: Color.accent }\n")
  nested = fixture("nested", "import QtQuick\nItem { property color a: Color.accent }\n", filename="nested/Panel.qml")
  crlf = fixture("windows-lines", "import QtQuick\r\nimport qs.Commons\r\nItem { property color a: Color.accent }\r\n")
  js = fixture("javascript", '.pragma library\n// Color.accent\nfunction accent() { return Color.accent }\nfunction label() { return "Color.accent" }\n', filename="Model.js")
  js_alias = fixture("javascript-alias", '.pragma library\n.import qs.Commons 1.0 as Palette\nfunction accent() { return Color.accent }\n', filename="Model.js")
  commented_alias_source = "import QtQuick\nimport qs.Commons\n/*\nimport qs.Commons as Palette\n*/\nItem { property color accent: Color.accent }\n"
  commented_alias = fixture("commented-alias", commented_alias_source)
  commented_insertion_source = "import QtQuick\n/*\nimport qs.Commons\npragma Singleton\n*/\nItem { property color accent: Color.accent }\n"
  commented_insertion = fixture("commented-insertion", commented_insertion_source)
  commented_js_source = '.pragma library\n/*\n.import qs.Commons 1.0 as Palette\n.pragma library\n*/\nfunction accent() { return Color.accent }\n'
  commented_js = fixture("commented-js", commented_js_source, filename="Model.js")
  trailing_import_source = "import QtQuick\nimport qs.Commons /* explanation\nstill inside the comment */\nItem { property color accent: Color.accent }\n"
  trailing_import = fixture("trailing-import-comment", trailing_import_source)
  trailing_pragma_source = '.pragma library /* explanation\nstill inside the comment */\nfunction accent() { return Color.accent }\n'
  trailing_pragma = fixture("trailing-pragma-comment", trailing_pragma_source, filename="Model.js")
  same_line_source = "import QtQuick\nimport qs.Commons\n/* explanation */ Item { property color accent: Color.accent }\n"
  same_line = fixture("same-line-comment", same_line_source)
  local_commons = fixture("local-commons", "import QtQuick\nimport qs.Commons\nItem { function accent() { const Commons = {}; return Color.accent } }\n")
  division_source = "import QtQuick\nimport qs.Commons\nItem { property real a: width / 2; property real b: (width - 1) / 2; property real c: Math.round(width) / 2; property color accent: Color.accent }\n"
  division = fixture("division", division_source)
  ambiguous = []
  for name, source in [
    ("template-interpolation", 'Item { property string accent: `${Color.accent}` }\n'),
    ("nested-template", 'Item { property string accent: `${true ? `${Color.accent}` : ""}` }\n'),
    ("regexp", 'Item { function matches(s) { return /Color.*/.test(s) } }\n'),
    ("regexp-quoted", '''Item { function matches(s) { return /["']Color.*/.test(s) }; property color accent: Color.accent }\n'''),
    ("regexp-after-control", 'Item { function matches(s) { if (s) /Color.*/.test(s) }; property color accent: Color.accent }\n'),
    ("local-parameter", 'Item { function accent(Color) { return Color.accent } }\n'),
    ("local-variable", 'Item { function accent() { const Color = {}; return Color.accent } }\n'),
    ("local-destructure", 'Item { function accent({Color}) { return Color.accent } }\n'),
    ("local-rest-parameter", 'Item { function accent(...Color) { return Color.accent } }\n'),
    ("alias-rest-parameter", 'import qs.Commons as Palette\nItem { function accent(...Palette) { return Color.accent } }\n'),
    ("regexp-after-debugger", 'Item { function matches(s) { debugger; /Color.*/.test(s) }; property color accent: Color.accent }\n'),
    ("regexp-after-break", 'Item { function matches(s) { label: while(s) { break label\n/Color.*/.test(s) } }; property color accent: Color.accent }\n'),
    ("standalone-palette", 'Item { function accent() { const palette = Color; return Color.accent } }\n'),
    ("existing-alias-shadow", 'import qs.Commons as Palette\nItem { function accent(Palette) { return Color.accent } }\n'),
    ("existing-commons-shadow", 'import qs.Commons as Commons\nItem { function accent() { const Commons = {}; return Color.accent } }\n'),
    ("escaped-identifier", r'Item { function accent(\u0043olor) { return Color.accent } }' + '\n'),
  ]:
    file = fixture(name, "import QtQuick\nimport qs.Commons\n" + source)
    ambiguous.append((file, file.read_bytes()))
  unchanged = []
  for name, manifest in [
    ("independent", {"id": "third.party"}),
    ("no-manifest", None),
    ("empty-clone", {"omarchy": {"clonedFrom": ""}}),
    ("whitespace-clone", {"omarchy": {"clonedFrom": " "}}),
    ("invalid-clone", {"omarchy": {"clonedFrom": True}}),
    ("invalid-metadata", {"omarchy": []}),
    ("invalid-manifest-type", []),
  ]:
    file = fixture(name, original, manifest)
    unchanged.append((file, file.read_bytes()))
  malformed = fixture("malformed", original)
  malformed.with_name("manifest.json").write_text("not json")
  unchanged.append((malformed, malformed.read_bytes()))
  comments = fixture("only-comments", 'import QtQuick\n// Color.accent\nItem { property string label: "Color.accent" }\n')
  unchanged.append((comments, comments.read_bytes()))
  noncode = fixture("noncode", "Color.accent", filename="notes.txt")
  unchanged.append((noncode, noncode.read_bytes()))

  external = home / "external"
  external.mkdir()
  external_file = external / "External.qml"
  external_file.write_text(original)
  (external / "manifest.json").write_text('{"omarchy":{"clonedFrom":"omarchy.clock"}}')
  (plugins / "linked-plugin").symlink_to(external, target_is_directory=True)
  (main.parent / "linked.qml").symlink_to(external_file)
  (main.parent / "linked-directory").symlink_to(external, target_is_directory=True)
  linked_manifest = fixture("linked-manifest", original, None)
  linked_manifest.with_name("manifest.json").symlink_to(external / "manifest.json")
  unchanged.extend([(external_file, external_file.read_bytes()), (linked_manifest, linked_manifest.read_bytes())])

  diagnostics = run()
  check(commented_alias.read_text() == commented_alias_source.replace("Item {", "import qs.Commons as Commons\nItem {", 1).replace("accent: Color.accent", "accent: Commons.Color.accent"), "commented aliases cannot select the palette namespace")
  check(commented_insertion.read_text() == commented_insertion_source.replace("Item {", "import qs.Commons as Commons\nItem {", 1).replace("accent: Color.accent", "accent: Commons.Color.accent"), "commented imports and pragmas cannot become insertion points")
  check(commented_js.read_text() == commented_js_source.replace("function accent", ".import qs.Commons 1.0 as Commons\nfunction accent", 1).replace("return Color.accent", "return Commons.Color.accent"), "JavaScript ignores commented module imports and pragmas")
  check(trailing_import.read_text() == trailing_import_source.replace("Item {", "import qs.Commons as Commons\nItem {", 1).replace("accent: Color.accent", "accent: Commons.Color.accent"), "import-line multiline comments cannot swallow the new QML import")
  check(trailing_pragma.read_text() == trailing_pragma_source.replace("function accent", ".import qs.Commons 1.0 as Commons\nfunction accent", 1).replace("return Color.accent", "return Commons.Color.accent"), "pragma-line multiline comments cannot swallow the new JavaScript import")
  check(same_line.read_text() == same_line_source.replace("Item {", "\nimport qs.Commons as Commons\nItem {", 1).replace("accent: Color.accent", "accent: Commons.Color.accent"), "comments ending on the root object's line remain outside the new import")
  check("as OmarchyCommons" in local_commons.read_text() and "return OmarchyCommons.Color.accent" in local_commons.read_text() and "const Commons = {}" in local_commons.read_text(), "new import aliases avoid locally declared names")
  check(division.read_text() == division_source.replace("import qs.Commons\n", "import qs.Commons\nimport qs.Commons as Commons\n").replace("accent: Color.accent", "accent: Commons.Color.accent"), "ordinary expression divisions remain unchanged while palette references migrate")
  for file, before in ambiguous:
    check(file.read_bytes() == before, "ambiguous " + file.parent.name + " remains byte-for-byte unchanged")
    check("Skipped " + str(file) + ":" in diagnostics and "qualify the shell palette manually" in diagnostics, "ambiguous " + file.parent.name + " reports its path and manual repair guidance")
  expected = original.replace("custom: Color.accent", "custom: Commons.Color.accent").replace("spaced: Color /*", "spaced: Commons.Color /*").replace("target: Color;", "target: Commons.Color;")
  expected = expected.replace("import qs.Commons\n", "import qs.Commons\nimport qs.Commons as Commons\n")
  check(main.read_text() == expected, "rewrites palette members and Connections target while preserving custom code, glyphs, strings, and comments")
  check(stat.S_IMODE(main.stat().st_mode) == 0o640, "preserves source file permissions")
  check(main.with_name("manifest.json").read_bytes() == manifest_before, "preserves clone metadata")
  check("Commons.Commons" not in mixed.read_text() and "b: Commons.Color.foreground" in mixed.read_text(), "mixed qualified and bare references never receive double qualification")
  check(mixed.read_text().count("import qs.Commons as Commons") == 1, "does not duplicate existing palette imports")
  check("b: Palette.Color.foreground" in alias.read_text() and "as Commons" not in alias.read_text(), "reuses an existing palette alias")
  check("import qs.Commons as OmarchyCommons" in collision.read_text() and "a: OmarchyCommons.Color.accent" in collision.read_text(), "avoids an occupied Commons import alias")
  check("import qs.Commons as Commons\n" in nested.read_text() and "Commons.Color.accent" in nested.read_text(), "migrates nested clone QML and adds a missing palette import")
  check(crlf.read_bytes() == b"import QtQuick\r\nimport qs.Commons\r\nimport qs.Commons as Commons\r\nItem { property color a: Commons.Color.accent }\r\n", "preserves CRLF line endings")
  check(js.read_text().startswith(".pragma library\n") and '.import qs.Commons 1.0 as Commons\nfunction accent' in js.read_text(), "JavaScript uses module import syntax after its library pragma and comments")
  check('return Commons.Color.accent' in js.read_text() and '// Color.accent' in js.read_text() and 'return "Color.accent"' in js.read_text(), "JavaScript rewrites code but preserves comments and strings")
  check("return Palette.Color.accent" in js_alias.read_text() and js_alias.read_text().count(".import") == 1, "JavaScript reuses an existing module alias")
  for file, before in unchanged:
    check(file.read_bytes() == before, "leaves " + str(file.relative_to(home)) + " unchanged")

  snapshot = {file: file.read_bytes() for file in plugins.rglob("*") if file.is_file()}
  run()
  check(all(file.read_bytes() == before for file, before in snapshot.items()), "second migration run is byte-for-byte idempotent")
  check(already.read_text() == "import QtQuick\nimport qs.Commons as Commons\nItem { property color value: Commons.Color.accent }\n", "already-migrated clones are byte-for-byte unchanged")
PY
