"""Keep the runtime shared-edge topology when a managed display is scaled.

This is a geometry-only planner: it does not read or write configuration files,
apply profiles, or infer a manager's saved layout. Disconnected displays stay put.
"""

from collections import deque
import itertools
import json
import math
import re
import sys


def number(value):
  return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def rounded(value):
  return math.floor(value + 0.5)


def rectangle(monitor):
  width, height = monitor["width"], monitor["height"]
  if monitor.get("transform", 0) % 2:
    width, height = height, width
  return (monitor.get("x", 0), monitor.get("y", 0),
          rounded(width / monitor["scale"]), rounded(height / monitor["scale"]))


def overlaps(a, b):
  return all(min(a[axis] + a[axis + 2], b[axis] + b[axis + 2]) > max(a[axis], b[axis])
             for axis in (0, 1))


def shared_edge(a, b):
  """Direction and cross-axis anchor of b relative to touching rectangle a."""
  for axis in (0, 1):
    cross = 1 - axis
    if min(a[cross] + a[cross + 2], b[cross] + b[cross + 2]) <= max(a[cross], b[cross]):
      continue
    for direction in (1, -1):
      gap = (b[axis] - a[axis] - a[axis + 2] if direction == 1
             else a[axis] - b[axis] - b[axis + 2])
      if abs(gap) <= 1:
        # Preserve aligned edges or centres. On equal-size stacked displays,
        # prefer the right edge; side-by-side displays prefer the top edge.
        alignment = min((1, 0.5, 0) if axis == 1 else (0, 0.5, 1), key=lambda factor: abs(
          b[cross] + factor * b[cross + 2] - a[cross] - factor * a[cross + 2]))
        offset = b[cross] + alignment * b[cross + 2] - a[cross] - alignment * a[cross + 2]
        return axis, direction, alignment, offset
  return None


def place(parent, size, edge):
  axis, direction, alignment, offset = edge
  cross = 1 - axis
  result = [0, 0, *size]
  result[axis] = parent[axis] + parent[axis + 2] if direction == 1 else parent[axis] - size[axis]
  result[cross] = rounded(parent[cross] + alignment * parent[cross + 2] + offset - alignment * size[cross])
  return tuple(result)


def plan(monitors, name, scale):
  if not number(scale) or not 1 <= scale <= 4:
    raise ValueError("scale must be between 1 and 4")
  displays = []
  for monitor in monitors:
    if monitor.get("disabled", False) or monitor.get("mirrorOf", "none") not in (None, "", "none"):
      continue
    if monitor.get("width") == 0 or monitor.get("height") == 0:
      continue
    if not isinstance(monitor.get("name"), str) or not re.fullmatch(r"[A-Za-z0-9._-]+", monitor["name"]):
      raise ValueError("unsafe monitor name")
    for key in ("width", "height", "scale", "refreshRate"):
      if not number(monitor.get(key)) or monitor[key] <= 0:
        raise ValueError("invalid monitor mode or scale")
    for key in ("width", "height"):
      if not isinstance(monitor[key], int):
        raise ValueError("non-integer mode dimensions")
    for key in ("x", "y", "transform"):
      value = monitor.get(key, 0)
      if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("invalid monitor position or transform")
    if monitor.get("transform", 0) not in range(8):
      raise ValueError("invalid monitor transform")
    displays.append(dict(monitor))
  by_name = {m["name"]: m for m in displays}
  if len(by_name) != len(displays) or name not in by_name:
    raise ValueError("scaled monitor is missing, mirrored, disabled, or ambiguous")
  old = {m["name"]: rectangle(m) for m in displays}
  graph = {key: {} for key in old}
  for a, b in itertools.combinations(sorted(old), 2):
    if overlaps(old[a], old[b]):
      raise ValueError("existing displays overlap; arrange them in the monitor manager first")
    edge = shared_edge(old[a], old[b])
    if edge is not None:
      graph[a][b] = edge
      graph[b][a] = shared_edge(old[b], old[a])
  by_name[name]["scale"] = scale
  sizes = {key: rectangle(m)[2:] for key, m in by_name.items()}
  component = {name}
  queue = deque([name])
  while queue:
    for child in graph[queue.popleft()]:
      if child not in component:
        component.add(child)
        queue.append(child)
  positions = {key: old[key] for key in old.keys() - component}
  positions[name] = (*old[name][:2], *sizes[name])
  attempts = 0

  def fits(key, candidate):
    for other, placed in positions.items():
      if other == key:
        continue
      if overlaps(candidate, placed):
        return False
      after = shared_edge(candidate, placed)
      if other in graph[key]:
        if after is None or after[:2] != graph[key][other][:2]:
          return False
      elif after is not None:
        # A newly touching diagonal changes the graph on the next scale step
        # and can make an up/down round trip drift. Preserve topology exactly.
        return False
    return True

  def connected_layout():
    nonlocal attempts
    if len(positions) == len(old):
      return True
    # Prefer a direct anchor, but try another touching parent when cycles
    # would otherwise overlap. Cross-axis alignment follows the chosen parent;
    # every existing shared edge must still permit pointer travel.
    for child in sorted(component - positions.keys()):
      parents = sorted(graph[child].keys() & positions.keys(), key=lambda key: (key != name, key))
      for parent in parents:
        axis, direction, preferred, offset = graph[parent][child]
        cross = 1 - axis
        # Equal-size displays have several indistinguishable aligned anchors.
        # Try the alternatives before giving up on a cyclic layout.
        for alignment in (preferred, *[a for a in (0, 0.5, 1) if a != preferred]):
          alternate = (old[child][cross] + alignment * old[child][cross + 2]
                       - old[parent][cross] - alignment * old[parent][cross + 2])
          if abs(alternate) > abs(offset) + 0.0001:
            continue
          attempts += 1
          if attempts > 512:
            raise ValueError("layout is too constrained; use the monitor manager")
          candidate = place(positions[parent], sizes[child], (axis, direction, alignment, alternate))
          if fits(child, candidate):
            positions[child] = candidate
            if connected_layout():
              return True
            del positions[child]
    return False

  if not fits(name, positions[name]) or not connected_layout():
    raise ValueError("resize cannot preserve shared edges without overlap; use the monitor manager")
  for key, monitor in by_name.items():
    monitor["x"], monitor["y"] = positions[key][:2]
  return displays


def lua_rules(before, after, name):
  old = {m["name"]: m for m in before}
  rules = []
  for monitor in after:
    key = monitor["name"]
    if key != name and (monitor["x"], monitor["y"]) == (old[key].get("x", 0), old[key].get("y", 0)):
      continue
    rules.append(
      f'hl.monitor({{ output = {json.dumps(key)}, '
      f'mode = "{monitor["width"]}x{monitor["height"]}@{monitor["refreshRate"]:.10g}", '
      f'position = "{monitor["x"]}x{monitor["y"]}", '
      f'scale = {monitor["scale"]:.10g}, transform = {monitor.get("transform", 0)} }})')
  return ";\n".join(rules)


if __name__ == "__main__":
  try:
    snapshot = json.load(sys.stdin)
    target, requested = sys.argv[1], float(sys.argv[2])
    print(lua_rules(snapshot, plan(snapshot, target, requested), target))
  except (ValueError, KeyError, TypeError, IndexError) as error:
    print(f"Cannot scale while keeping displays connected: {error}", file=sys.stderr)
    sys.exit(1)
