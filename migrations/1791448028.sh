echo "Qualify palette references in cloned built-in shell plugins for Qt 6.12"

# #14553 fixed shipped plugins, but user clones still contain bare Color
# references. Keep their customizations and leave independent plugins alone.
# The update pipeline restarts the shell after migrations have completed.
python3 - <<'PY'
import json
import os
from pathlib import Path
import re

plugins = Path(os.environ["HOME"]) / ".config/omarchy/plugins"
if not plugins.is_dir():
  raise SystemExit(0)

# Ignore comments and string literals rather than rewriting documentation,
# labels, or already-qualified member accesses. These are the palette forms
# used by built-ins: Color.role and Connections { target: Color }.
tokens = re.compile(r'''//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`|[A-Za-z_$][\w$]*|[^\s]''')
imports = re.compile(r"^([ \t]*\.?import[ \t]+[^\r\n]+)", re.MULTILINE)
commons = re.compile(r"^\.?import[ \t]+qs\.Commons(?:[ \t]+\d+\.\d+)?(?:[ \t]+as[ \t]+([A-Za-z_]\w*))?[ \t]*(?://.*)?$")

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
      code = [match for match in tokens.finditer(text) if not match[0].startswith(('//', '/*', '"', "'", '`'))]
      references = []
      for i, token in enumerate(code):
        if token[0] != "Color" or (i and code[i - 1][0] == "."):
          continue
        member = i + 1 < len(code) and code[i + 1][0] == "."
        target = i >= 2 and [part[0] for part in code[i - 2:i]] == ["target", ":"]
        if member or target:
          references.append(token)
      if not references:
        continue

      directives = list(imports.finditer(text))
      palette_imports = [commons.fullmatch(item[0].strip()) for item in directives]
      alias = next((item[1] for item in palette_imports if item and item[1]), None)
      add_import = alias is None
      if add_import:
        used_aliases = set(re.findall(r"\bas[ \t]+([A-Za-z_]\w*)", "\n".join(item[0] for item in directives)))
        alias = "Commons"
        while alias in used_aliases:
          alias = "Omarchy" + alias

      for token in reversed(references):
        text = text[:token.start()] + alias + ".Color" + text[token.end():]
      if add_import:
        newline = "\r\n" if "\r\n" in text else "\n"
        directive = (".import qs.Commons 1.0 as " if file.suffix == ".js" else "import qs.Commons as ") + alias
        # Retain unqualified imports: other built-in singleton names still
        # depend on them. Place JS imports after .pragma library, if present.
        lines = text.splitlines(keepends=True)
        position = 0
        for i, line in enumerate(lines):
          if imports.match(line) or line.strip().startswith(("pragma ", ".pragma ")):
            position = i + 1
        if position and not lines[position - 1].endswith(("\n", "\r")):
          lines[position - 1] += newline
        lines.insert(position, directive + newline)
        text = "".join(lines)
      file.write_bytes(text.encode("utf-8"))
PY
