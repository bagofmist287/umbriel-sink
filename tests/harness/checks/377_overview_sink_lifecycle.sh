#!/usr/bin/env bash
# harness: outputs=2
# Fractional/mixed-axis projections, source evacuation during motion, close,
# geometry reload and lock must retain one owner and deterministic membership.
set -euo pipefail
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do windows | jq -e "$1" >/dev/null && return 0; sleep 0.025; done
  echo "query did not settle: $1; $(windows)"; return 1
}
wait_overview() {
  for _ in $(seq 100); do
    jq -se "last | .data.open == $1" "$UMBRIEL_RUNTIME_DIR/events" >/dev/null && return 0
    sleep 0.025
  done
  echo "Overview did not become $1"; return 1
}
shot() {
  local output=$1 target=$2
  grim -o "$output" "$UMBRIEL_RUNTIME_DIR/previous.png"
  for _ in $(seq 100); do
    sleep 0.025
    grim -o "$output" "$target"
    if cmp -s "$target" "$UMBRIEL_RUNTIME_DIR/previous.png"; then return 0; fi
    cp "$target" "$UMBRIEL_RUNTIME_DIR/previous.png"
  done
  echo 'frame did not settle'; return 1
}
cat >> "$UMBRIEL_CONFIG" <<'CONFIG'

[animation]
enabled = false
[animation.windows_in]
enabled = false
[animation.windows_move]
duration_ms = 400
curve = "linear"
[animation.overview]
duration_ms = 400
curve = "linear"
[animation.overview.sink]
mode = "smooth"
[appearance]
border_width = 0
outer_border_width = 0
corner_radius = 0
[appearance.shadow]
enabled = false
[appearance.blur]
enabled = false
[overview]
zoom = 0.4
shortcuts = false
background_blur = false
workspace_wallpaper = false
[overview.sink]
exposure_height = 64
tail_height = 32
[output."HEADLESS-1"]
scale = 1.25
workspaces = 3
workspace_axis = "vertical"
[output."HEADLESS-2"]
workspaces = 3
workspace_axis = "horizontal"
[[window_rule]]
match.title = "^lifecycle-"
default_floating = true
default_floating_size_px = {width=400,height=300}
CONFIG
"$UMBRIEL" msg config-reload >/dev/null
"$UMBRIEL" subscribe overview > "$UMBRIEL_RUNTIME_DIR/events" &
for output in HEADLESS-1 HEADLESS-2; do
  "$UMBRIEL" msg "workspace-switch:1/$output" >/dev/null
  FILL_COLOR=0xFF0000FF EXIT_ON_CLOSE=1 "$UMBRIEL_UNMAP_CLIENT" "lifecycle-$output" 400 300 >/dev/null 2>&1 &
  wait_query "any(.[]; .title == \"lifecycle-$output\" and .active)"
  "$UMBRIEL" msg window-sink >/dev/null
  wait_query "any(.[]; .title == \"lifecycle-$output\" and .sunk)"
done
"$UMBRIEL" msg overview-open >/dev/null
wait_overview true
for output in HEADLESS-1 HEADLESS-2; do
  shot "$output" "$UMBRIEL_RUNTIME_DIR/$output.png"
  magick "$UMBRIEL_RUNTIME_DIR/$output.png" -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/$output.rgb"
done
python3 - "$UMBRIEL_RUNTIME_DIR" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
for name, expected_width, expected_top in [('HEADLESS-1',200,176),('HEADLESS-2',160,184)]:
    d=(p/f'{name}.rgb').read_bytes()
    points=[(i%1280,i//1280) for i in range(len(d)//3) if d[3*i:3*i+3]==bytes((0,0,255))]
    assert points, f'{name}: source missing'
    xs,ys=zip(*points)
    assert abs((min(xs)+max(xs)+1)/2-640)<=1, (name, min(xs),max(xs))
    assert abs(max(xs)-min(xs)+1-expected_width)<=2, (name,min(xs),max(xs))
    assert abs(min(ys)-expected_top)<=2, (name,min(ys))
PY
# A large valid height/tail reload invalidates the frozen layout once and
# force-closes; it must not leave the old preview nodes behind.
sed -i 's/exposure_height = 64/exposure_height = 256/;s/tail_height = 32/tail_height = 256/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload >/dev/null
wait_overview false
"$UMBRIEL" msg overview-open >/dev/null
wait_overview true
shot HEADLESS-1 "$UMBRIEL_RUNTIME_DIR/high.png"
# Navigation reaches the next workspace even when an entrance overhangs the
# preview. Returning focus rebuilds the layout from the same capacity budget.
"$UMBRIEL" msg workspace-switch:2/HEADLESS-1 >/dev/null
"$UMBRIEL" msg workspace-switch:1/HEADLESS-1 >/dev/null
# Restore modest geometry, enable motion, remove an output during smooth opening.
sed -i 's/exposure_height = 256/exposure_height = 64/;s/tail_height = 256/tail_height = 0/;0,/enabled = false/s//enabled = true/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload >/dev/null
wait_overview false
"$UMBRIEL" msg overview-open >/dev/null
"$UMBRIEL" output-destroy HEADLESS-1 >/dev/null
wait_query 'length == 2 and all(.[]; .sunk and (.workspace | startswith("HEADLESS-2:")))'
wait_query 'any(.[]; .title == "lifecycle-HEADLESS-1" and .sink_depth == 0) and any(.[]; .title == "lifecycle-HEADLESS-2" and .sink_depth == 1)'
shot HEADLESS-2 "$UMBRIEL_RUNTIME_DIR/evacuated.png"
"$UMBRIEL" msg window-pull >/dev/null
wait_query 'any(.[]; .title == "lifecycle-HEADLESS-1" and (.sunk == false) and .focused)'
"$UMBRIEL" msg window-sink >/dev/null
id=$(windows | jq -r '.[] | select(.title == "lifecycle-HEADLESS-1") | .id')
"$UMBRIEL" msg "window-close:$id" >/dev/null
wait_query 'length == 1 and .[0].sunk and .[0].sink_depth == 0'
# Lock while the remaining card reflows. The copied scene may not enter capture.
mkfifo "$UMBRIEL_RUNTIME_DIR/lock-control"
exec {lock_fd}<>"$UMBRIEL_RUNTIME_DIR/lock-control"
"$UMBRIEL_LOCK_CLIENT" <&"$lock_fd" > "$UMBRIEL_RUNTIME_DIR/lock.log" 2>&1 &
for _ in $(seq 100); do grep -q '^locked$' "$UMBRIEL_RUNTIME_DIR/lock.log" && break; sleep 0.025; done
grep -q '^locked$' "$UMBRIEL_RUNTIME_DIR/lock.log"
wait_overview false
grim -o HEADLESS-2 "$UMBRIEL_RUNTIME_DIR/locked.png"
read -r red green blue < <(magick "$UMBRIEL_RUNTIME_DIR/locked.png" -crop 1x1+640+360 -format '%[fx:round(255*mean.r)] %[fx:round(255*mean.g)] %[fx:round(255*mean.b)]\n' info:)
((red>=13 && red<=19 && green>=29 && green<=35 && blue>=45 && blue<=51))
echo unlock >&"$lock_fd"
for _ in $(seq 100); do grep -q '^unlocked$' "$UMBRIEL_RUNTIME_DIR/lock.log" && break; sleep 0.025; done
grep -q '^unlocked$' "$UMBRIEL_RUNTIME_DIR/lock.log"
wait_query 'length == 1 and .[0].sunk and .[0].sink_depth == 0'
"$UMBRIEL" msg overview-open >/dev/null
"$UMBRIEL" msg window-pull >/dev/null
wait_query 'length == 1 and (.[0].sunk == false) and .[0].focused'
"$UMBRIEL" msg overview-close >/dev/null
wait_overview false
echo 'fractional centred cards, large geometry reload, mixed-axis evacuation during opening, local close and lock preserve ownership'
