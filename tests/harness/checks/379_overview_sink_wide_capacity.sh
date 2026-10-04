#!/usr/bin/env bash
# A wide offset foreground can become a centred Sink without rebuilding gaps.
# Reserve its potential centred overhang before the initially empty stack grows.
set -euo pipefail
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do windows | jq -e "$1" >/dev/null && return 0; sleep 0.025; done
  echo "query did not settle: $1; $(windows)"; return 1
}
shot() {
  grim "$UMBRIEL_RUNTIME_DIR/previous.png"
  for _ in $(seq 100); do
    sleep 0.025
    grim "$1"
    if cmp -s "$1" "$UMBRIEL_RUNTIME_DIR/previous.png"; then return 0; fi
    cp "$1" "$UMBRIEL_RUNTIME_DIR/previous.png"
  done
  echo 'frame did not settle'; return 1
}
cat >> "$UMBRIEL_CONFIG" <<'CONFIG'

[animation]
enabled = false
[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0
[appearance.shadow]
enabled = false
[appearance.blur]
enabled = false
[overview]
zoom = 0.25
shortcuts = false
background_blur = false
workspace_wallpaper = false
[output."HEADLESS-1"]
workspaces = 3
workspace_axis = "horizontal"
[[window_rule]]
match.title = "^wide-capacity-blue$"
default_floating = true
default_floating_size_px = {width=1800,height=300}
default_position = {x=0,y=100,anchor="top_left"}
CONFIG
"$UMBRIEL" msg config-reload >/dev/null
FILL_COLOR=0xFFFF0000 REQUEST_FULLSCREEN=1 "$UMBRIEL_UNMAP_CLIENT" wide-capacity-red 1280 720 >/dev/null 2>&1 &
wait_query 'any(.[]; .title == "wide-capacity-red" and .active)'
"$UMBRIEL" msg workspace-switch:2 >/dev/null
FILL_COLOR=0xFF0000FF "$UMBRIEL_UNMAP_CLIENT" wide-capacity-blue 1800 300 >/dev/null 2>&1 &
wait_query 'any(.[]; .title == "wide-capacity-blue" and .active and .w == 1800)'
"$UMBRIEL" msg overview-open >/dev/null
shot "$UMBRIEL_RUNTIME_DIR/before.png"
"$UMBRIEL" msg window-sink >/dev/null
wait_query 'any(.[]; .title == "wide-capacity-blue" and .sunk)'
shot "$UMBRIEL_RUNTIME_DIR/after.png"
for phase in before after; do magick "$UMBRIEL_RUNTIME_DIR/$phase.png" -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/$phase.rgb"; done
python3 - "$UMBRIEL_RUNTIME_DIR" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
a=(p/'before.rgb').read_bytes(); b=(p/'after.rgb').read_bytes()
red=bytes((255,0,0)); blue=bytes((0,0,255))
ra={i for i in range(len(a)//3) if a[3*i:3*i+3]==red}
rb={i for i in range(len(b)//3) if b[3*i:3*i+3]==red}
bs={i for i in range(len(b)//3) if b[3*i:3*i+3]==blue}
assert ra and bs, 'neighbour or wide Sink missing'
assert ra == rb, ('local Sink moved or covered neighbour',len(ra),len(rb))
xs=[i%1280 for i in bs]
assert abs((min(xs)+max(xs)+1)/2-640)<=1, ('Sink lost centre',min(xs),max(xs))
assert max(xs)-min(xs)+1==450, ('source width changed',min(xs),max(xs))
assert max(i%1280 for i in rb) < min(xs), 'reserved gap permits wide Sink overlap'
PY
echo 'empty stack reserves offset wide foreground as a future centred Sink; neighbour stays fixed and uncovered'
