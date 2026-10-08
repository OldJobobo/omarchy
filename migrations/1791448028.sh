echo "Qualify palette references in cloned built-in shell plugins for Qt 6.12"

# #14553 fixed shipped plugins, but user clones still contain bare Color
# references. Keep their customizations and leave independent plugins alone.
# The update pipeline restarts the shell after migrations have completed.
python3 - <<'PY'
import json
import os
from pathlib import Path
import re
import sys

plugins = Path(os.environ["HOME"]) / ".config/omarchy/plugins"
if not plugins.is_dir():
  raise SystemExit(0)

# This is a conservative source repair, not a JavaScript parser. Mask comments
# and literals without changing offsets, and leave files with ambiguous syntax
# or local names alone. The warning tells users which files need manual repair.
# Built-ins use Color.role and Connections { target: Color }.
literals = re.compile(r'''//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`''')
tokens = re.compile(r"[A-Za-z_$][\w$]*|[^\s]")
imports = re.compile(r"^[ \t]*\.?import[ \t]+[^\r\n]+", re.MULTILINE)
pragmas = re.compile(r"^[ \t]*\.?pragma[ \t]+[^\r\n]+", re.MULTILINE)
commons = re.compile(r"^\.?import[ \t]+qs\.Commons(?:[ \t]+\d+\.\d+)?(?:[ \t]+as[ \t]+([A-Za-z_]\w*))?[ \t]*$")

def warn(file, reason):
  print(f"Skipped {file}: {reason}; qualify the shell palette manually with an unshadowed qs.Commons import alias.", file=sys.stderr)

def qualified_member(code, i):
  # A single dot qualifies a member; spread/rest syntax (...Color) does not.
  return i > 0 and code[i - 1][0] == "." and (i < 2 or code[i - 2][0] != ".")

def ambiguous_slash(code, masked):
  # Accept ordinary arithmetic after a value, but never guess at a regex or
  # a slash following a control-statement condition. Ambiguous files are skipped.
  keywords = {"return", "throw", "case", "delete", "void", "typeof", "new", "in", "instanceof", "of", "yield", "await", "else", "do", "break", "continue", "debugger"}
  controls = {"if", "while", "for", "switch", "catch", "with"}
  parens = []
  expression_end = False
  for i, item in enumerate(code):
    value = item[0]
    if value == "/" and (not expression_end or (i and re.search(r"[\r\n]", masked[code[i - 1].end():item.start()]))):
      return True
    if value == "(":
      parens.append(i == 0 or code[i - 1][0] not in controls)
    if value == ")":
      expression_end = bool(parens and parens.pop())
    else:
      expression_end = value == "]" or (bool(re.fullmatch(r"[A-Za-z_$][\w$]*|\d", value)) and value not in keywords)
  return False

for plugin in sorted(plugins.iterdir()):
  # Never follow links out of a clone into another plugin or shared source.
  manifest = plugin / "manifest.json"
  if plugin.is_symlink() or not plugin.is_dir() or manifest.is_symlink():
    continue
  try:
    metadata = json.loads(manifest.read_text()).get("omarchy", {})
    source = metadata.get("clonedFrom") if isinstance(metadata, dict) else None
  except (FileNotFoundError, ValueError, AttributeError):
    continue
  if not isinstance(source, str) or not source.strip():
    continue

  for directory, dirs, files in os.walk(plugin, followlinks=False):
    dirs[:] = sorted(name for name in dirs if not (Path(directory) / name).is_symlink())
    for name in sorted(files):
      file = Path(directory) / name
      if file.suffix not in (".qml", ".js") or file.is_symlink():
        continue
      text = file.read_bytes().decode("utf-8")
      if not re.search(r"\bColor\b", text):
        continue
      opaque = list(literals.finditer(text))
      if any(item[0].startswith('`') and '${' in item[0] for item in opaque):
        warn(file, "template interpolation requires syntax-aware repair")
        continue
      masked = literals.sub(lambda item: re.sub(r"[^\r\n]", " ", item[0]), text)
      directives = list(imports.finditer(masked))
      headers = directives + list(pragmas.finditer(masked))
      code = [match for match in tokens.finditer(masked) if not any(header.start() <= match.start() < header.end() for header in headers)]
      # Escaped identifiers, unterminated literals, and regex-like slashes
      # require a real parser. Simple expression divisions are safe to retain.
      if ambiguous_slash(code, masked) or any(item[0] in ('\\', '"', "'", '`') for item in code):
        warn(file, "ambiguous slash, escaped identifier, or unterminated literal requires syntax-aware repair")
        continue
      references = []
      ambiguous_color = False
      for i, token in enumerate(code):
        if token[0] != "Color" or qualified_member(code, i):
          continue
        member = i + 1 < len(code) and code[i + 1][0] == "."
        target = i >= 2 and [part[0] for part in code[i - 2:i]] == ["target", ":"]
        if member or target:
          references.append(token)
        else:
          # Includes parameters, variable declarations, QML ids, and other
          # standalone uses whose binding cannot be determined lexically.
          ambiguous_color = True
      if not references:
        continue
      if ambiguous_color:
        warn(file, "Color may be a local binding or standalone expression")
        continue

      palette_imports = [commons.fullmatch(item[0].strip()) for item in directives]
      alias = next((item[1] for item in palette_imports if item and item[1]), None)
      add_import = alias is None
      if add_import:
        used_names = {item[0] for i, item in enumerate(code) if i + 1 == len(code) or code[i + 1][0] != "."}
        used_names.update(re.findall(r"\bas[ \t]+([A-Za-z_]\w*)", "\n".join(item[0] for item in directives)))
        alias = "Commons"
        while alias in used_names:
          alias = "Omarchy" + alias
      elif any(item[0] == alias and not qualified_member(code, i) and (i + 1 == len(code) or code[i + 1][0] != ".") for i, item in enumerate(code)):
        warn(file, f"existing palette alias {alias} may be locally shadowed")
        continue

      for token in reversed(references):
        text = text[:token.start()] + alias + ".Color" + text[token.end():]
      if add_import:
        newline = "\r\n" if "\r\n" in text else "\n"
        directive = (".import qs.Commons 1.0 as " if file.suffix == ".js" else "import qs.Commons as ") + alias
        # Retain unqualified imports: other built-in singleton names still
        # depend on them. Place JS imports after .pragma library, if present.
        lines = text.splitlines(keepends=True)
        # Header offsets come from masked source, so a commented-out import
        # can neither select an alias nor become the insertion point.
        position = max((masked[:header.end()].count("\n") + 1 for header in headers), default=0)
        if position and not lines[position - 1].endswith(("\n", "\r")):
          lines[position - 1] += newline
        lines.insert(position, directive + newline)
        text = "".join(lines)
      file.write_bytes(text.encode("utf-8"))
PY
