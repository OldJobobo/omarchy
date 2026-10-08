echo "Rename Color to ShellColor in cloned built-in shell plugins"

# The shell palette singleton is now ShellColor: Qt 6.12's QtQuick Color
# singleton hides any same-named type in files with a bare `import QtQuick`.
# Clones copied the built-in code that still said Color, so their themed colors
# went blank. Only clones are rewritten; third-party plugins belong to their
# authors.

plugins_dir="$HOME/.config/omarchy/plugins"
[[ -d $plugins_dir ]] || exit 0

for manifest in "$plugins_dir"/*/manifest.json; do
  [[ -f $manifest ]] || continue

  cloned_from=$(jq -r '.omarchy.clonedFrom // empty' "$manifest" 2>/dev/null) || continue
  [[ -n $cloned_from ]] || continue

  while IFS= read -r -d '' file; do
    sed -i 's/\<Color\./ShellColor./g' "$file"
  done < <(grep -rlZ '\<Color\.' --include=*.qml --include=*.js "${manifest%/manifest.json}/")
done
