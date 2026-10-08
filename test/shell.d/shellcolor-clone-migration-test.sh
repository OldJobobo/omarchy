#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1791418757.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
plugins="$home/.config/omarchy/plugins"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

mkdir -p "$home"
run_migration
pass "the migration is a no-op without a plugins directory"

mkdir -p "$plugins/me.clock/parts" "$plugins/acme.weather" "$plugins/me.broken"
printf '%s\n' '{"id":"me.clock","omarchy":{"clonedFrom":"omarchy.clock"}}' >"$plugins/me.clock/manifest.json"
cat >"$plugins/me.clock/Clock.qml" <<'QML'
import QtQuick
import qs.Commons
Item {
  property color foreground: Color.foreground
  property color fill: bar ? bar.urgent : Color.bar.background
  property color kept: ShellColor.accent
  property color qualified: Commons.Color.accent
  property color other: XColor.accent
  // Bound to the central Color singleton.
}
QML
printf '%s\n' 'function tint() { return Color.accent }' >"$plugins/me.clock/parts/tint.js"

printf '%s\n' '{"id":"acme.weather"}' >"$plugins/acme.weather/manifest.json"
printf '%s\n' 'Item { property color c: Color.accent }' >"$plugins/acme.weather/Panel.qml"

printf '%s\n' '{ not json' >"$plugins/me.broken/manifest.json"
printf '%s\n' 'Item { property color c: Color.accent }' >"$plugins/me.broken/Panel.qml"

run_migration
cp "$plugins/me.clock/Clock.qml" "$test_tmp/first-run.qml"
run_migration

expected=$(cat <<'QML'
import QtQuick
import qs.Commons
Item {
  property color foreground: ShellColor.foreground
  property color fill: bar ? bar.urgent : ShellColor.bar.background
  property color kept: ShellColor.accent
  property color qualified: Commons.ShellColor.accent
  property color other: XColor.accent
  // Bound to the central Color singleton.
}
QML
)
[[ $(cat "$plugins/me.clock/Clock.qml") == "$expected" ]] ||
  fail "the migration renames Color references in a cloned built-in"
pass "the migration renames Color references in a cloned built-in"

[[ $(cat "$plugins/me.clock/parts/tint.js") == 'function tint() { return ShellColor.accent }' ]] ||
  fail "the migration reaches nested JavaScript in a clone"
pass "the migration reaches nested JavaScript in a clone"

cmp -s "$test_tmp/first-run.qml" "$plugins/me.clock/Clock.qml" ||
  fail "a second run leaves a migrated clone unchanged"
pass "a second run leaves a migrated clone unchanged"

[[ $(cat "$plugins/acme.weather/Panel.qml") == 'Item { property color c: Color.accent }' ]] ||
  fail "the migration leaves third-party plugins alone"
pass "the migration leaves third-party plugins alone"

[[ $(cat "$plugins/me.broken/Panel.qml") == 'Item { property color c: Color.accent }' ]] ||
  fail "the migration skips a plugin with an unreadable manifest"
pass "the migration skips a plugin with an unreadable manifest"
