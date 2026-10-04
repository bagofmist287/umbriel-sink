#!/usr/bin/env bash
# A long local reflow must still converge to desktop placement on the shorter
# common close clock. Residual Card corrections may not jump at teardown.
set -euo pipefail
windows() { "$UMBRIEL" windows --json; }
cat >> "$UMBRIEL_CONFIG" <<'CONFIG'

[animation]
enabled = false
[animation.windows_in]
enabled = false
[animation.windows_move]
duration_ms = 2000
curve = "linear"
[animation.overview]
duration_ms = 800
curve = "linear"
[animation.dim_unfocused]
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
zoom = 0.5
shortcuts = false
background_blur = false
workspace_wallpaper = false
[[window_rule]]
match.title = "^handoff-sink$"
default_floating = true
default_floating_size_px = {width=400,height=300}
default_position = {x=100,y=100,anchor="top_left"}
CONFIG
"$UMBRIEL" msg config-reload >/dev/null
FILL_COLOR=0xFF0000FF "$UMBRIEL_UNMAP_CLIENT" handoff-sink 400 300 >/dev/null 2>&1 &
for _ in $(seq 100); do windows | jq -e 'length == 1 and .[0].active' >/dev/null && break; sleep 0.025; done
windows | jq -e 'length == 1 and .[0].active' >/dev/null
"$UMBRIEL" msg window-sink >/dev/null
sed -i '0,/enabled = false/s//enabled = true/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload >/dev/null
"$UMBRIEL" msg overview-open >/dev/null
sleep 0.9
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 174 press 272 release 272
# Capture first, analyse later so image processing cannot advance the clock
# between sample selection and its measurement.
for i in $(seq 0 24); do grim "$UMBRIEL_RUNTIME_DIR/close-$i.png"; sleep 0.025; done
for i in $(seq 0 24); do magick "$UMBRIEL_RUNTIME_DIR/close-$i.png" -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/close-$i.rgb"; done
python3 - "$UMBRIEL_RUNTIME_DIR" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); frames=[]
for i in range(25):
    d=(p/f'close-{i}.rgb').read_bytes()
    pixels=[j for j in range(len(d)//3) if d[3*j:3*j+3]==bytes((0,0,255))]
    assert pixels, f'frame {i}: window vanished'
    xs=[j%1280 for j in pixels]; ys=[j//1280 for j in pixels]
    frames.append((min(xs),min(ys),max(xs)-min(xs)+1,max(ys)-min(ys)+1))
near=[f for f in frames if 320<=f[2]<400]
assert near, ('no sample near closing endpoint',frames)
for x,y,w,h in near:
    z=w/400; progress=2*(1-z)
    native_x=640*(1-z)+100*z
    assert x <= native_x+340*z*progress+3, ('local correction did not converge on common close clock',near)
assert frames[-1] == (100,100,400,300), ('teardown missed desktop geometry',frames)
PY
echo 'long local reflow converges to desktop geometry before the common close endpoint'
