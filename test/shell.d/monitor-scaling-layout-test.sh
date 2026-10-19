#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

PYTHONDONTWRITEBYTECODE=1 python3 <<'PY'
import importlib.util
import itertools
import os
from pathlib import Path

path = Path(os.environ['ROOT']) / 'default/hypr/monitor-scaling-layout.py'
spec = importlib.util.spec_from_file_location('layout', path)
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)


def monitor(name, x=0, y=0, width=2560, height=1440, transform=0):
  return dict(name=name, x=x, y=y, width=width, height=height, scale=1,
              refreshRate=144.0, transform=transform, mirrorOf='none')


def desk():
  return [monitor('DP-1'),
          monitor('DP-2', 640, -1080, 1920, 1080),
          monitor('DP-3', 2560, -1120, transform=1)]


def rectangles(displays):
  result = {}
  for m in displays:
    w, h = m['width'], m['height']
    if m['transform'] % 2:
      w, h = h, w
    result[m['name']] = (m['x'], m['y'], round(w / m['scale']), round(h / m['scale']))
  return result


def contact(a, b):
  for axis in (0, 1):
    cross = 1 - axis
    shared = min(a[cross] + a[cross + 2], b[cross] + b[cross + 2]) - max(a[cross], b[cross])
    if shared > 0 and (abs(a[axis] + a[axis + 2] - b[axis]) <= 1 or
                       abs(b[axis] + b[axis + 2] - a[axis]) <= 1):
      return True
  return False


def assert_topology(before, after):
  a, b = rectangles(before), rectangles(after)
  for first, second in itertools.combinations(a, 2):
    left, right = b[first], b[second]
    assert not all(min(left[i] + left[i + 2], right[i] + right[i + 2]) > max(left[i], right[i])
                   for i in (0, 1)), (first, second, b)
    if contact(a[first], a[second]):
      assert contact(b[first], b[second]), (first, second, b)


original = desk()
planned = layout.plan(original, 'DP-1', 1.25)
r = rectangles(planned)
assert r == {'DP-1': (0, 0, 2048, 1152),
             'DP-2': (128, -1080, 1920, 1080),
             'DP-3': (2048, -1408, 1440, 2560)}, r
assert_topology(original, planned)
assert original == desk(), 'planner mutated its input'
print('ok - 1.25x desktop keeps DP-1/DP-3 connected and the top display right-aligned')

for target in ('DP-1', 'DP-2', 'DP-3'):
  current = desk()
  for scale in (1.25, 1.6, 2, 3.2, 4, 3.2, 2, 1.6, 1.25, 1):
    previous = current
    current = layout.plan(current, target, scale)
    assert_topology(previous, current)
    for a, b in zip(previous, current):
      for field in ('width', 'height', 'transform', 'refreshRate'):
        assert a[field] == b[field]
      if a['name'] != target:
        assert a['scale'] == b['scale']
  assert current == desk(), (target, current)
print('ok - every display round-trips all presets without gaps, overlap or position drift')

chain = [monitor(f'DP-{i + 1}', i * 2560) for i in range(4)]
planned = layout.plan(chain, 'DP-1', 1.25)
assert [m['x'] for m in planned] == [0, 2048, 4608, 7168]
assert_topology(chain, planned)
print('ok - shared-edge movement propagates through a chain of displays')

grid = [monitor('A', width=1920, height=1080),
        monitor('B', 1920, width=1920, height=1080),
        monitor('C', y=1080, width=1920, height=1080),
        monitor('D', 1920, 1080, 1920, 1080)]
planned = layout.plan(grid, 'A', 1.25)
assert_topology(grid, planned)
assert layout.plan(planned, 'A', 1) == grid
print('ok - a shared-edge cycle stays connected without enforcing incompatible alignments')

with_gap = [monitor('A'), monitor('B', 4000)]
planned = layout.plan(with_gap, 'A', 1.25)
assert planned[1] == with_gap[1]
assert 'output = "B"' not in layout.lua_rules(with_gap, planned, 'A')
print('ok - intentionally disconnected displays are not moved or rewritten')

extra = desk() + [dict(monitor('MIRROR'), mirrorOf='DP-1'),
                  dict(monitor('OFF'), disabled=True), monitor('MODELESS', width=0)]
planned = layout.plan(extra, 'DP-1', 1.25)
assert [m['name'] for m in planned] == ['DP-1', 'DP-2', 'DP-3']
print('ok - mirrors, disabled displays and modeless outputs do not participate in geometry')

for field, bad in [('name', 'DP-4"; os.execute("false")'), ('x', '0x0'),
                   ('scale', float('nan')), ('refreshRate', float('inf')), ('transform', True)]:
  broken = desk()
  broken[1][field] = bad
  try:
    layout.plan(broken, 'DP-1', 1.25)
  except (ValueError, TypeError):
    pass
  else:
    raise AssertionError(('unsafe monitor data accepted', field))
print('ok - unsafe or non-finite neighbouring monitor data is rejected before Lua generation')

broken = [monitor('A'), monitor('B', 100)]
try:
  layout.plan(broken, 'A', 1.25)
except ValueError:
  pass
else:
  raise AssertionError('existing overlap accepted')
print('ok - invalid existing overlap is refused instead of silently rearranged')

rules = layout.lua_rules(original, layout.plan(original, 'DP-1', 1.25), 'DP-1')
assert rules.count('hl.monitor(') == 3
assert 'scale = 1.25' in rules and 'position = "2048x-1408"' in rules
assert 'transform = 1' in rules and 'mode = "2560x1440@144"' in rules
print('ok - one Lua request carries the scaled display and only its moved neighbours')
PY
