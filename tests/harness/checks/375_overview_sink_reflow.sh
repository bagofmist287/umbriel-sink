#!/usr/bin/env bash
# Local push/fill moves start at current card geometry, keep global zoom fixed,
# and never move the adjacent preview or replay the Overview opening clock.
set -euo pipefail
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do
    windows | jq -e "$1" > /dev/null && return 0
    sleep 0.025
  done
  echo "query did not settle: $1; $(windows)"; return 1
}
shot() {
  local previous="$UMBRIEL_RUNTIME_DIR/previous.png" current="$UMBRIEL_RUNTIME_DIR/current.png"
  grim "$previous"
  for _ in $(seq 100); do
    sleep 0.025
    grim "$current"
    if cmp -s "$previous" "$current"; then cp "$current" "$1"; return 0; fi
    cp "$current" "$previous"
  done
  echo 'frame did not settle'; return 1
}
green_top() {
  magick "$1" -crop 1x720+640+0 -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/column.rgb"
  python3 - "$UMBRIEL_RUNTIME_DIR/column.rgb" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
ys=[y for y in range(720) if d[y*3:y*3+3] == bytes((0,255,0))]
assert ys, 'green card is missing'
print(min(ys))
PY
}
cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
enabled = false
[animation.windows_in]
enabled = false
[animation.windows_move]
duration_ms = 800
curve = "linear"
[animation.overview]
duration_ms = 250
curve = "linear"
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
[[window_rule]]
match.title = "^reflow-float-"
default_floating = true
default_floating_size_px = {width=800, height=300}
EOF
"$UMBRIEL" msg config-reload > /dev/null
for spec in 'deep FFFF0000' 'top FF00FF00'; do
  read -r name color <<< "$spec"
  FILL_COLOR="0x$color" "$UMBRIEL_UNMAP_CLIENT" "reflow-float-$name" 800 300 > /dev/null 2>&1 &
  wait_query "any(.[]; .title == \"reflow-float-$name\" and .active)"
  "$UMBRIEL" msg window-sink > /dev/null
done
FILL_COLOR=0xFF0000FF REQUEST_FULLSCREEN=1 "$UMBRIEL_UNMAP_CLIENT" reflow-fullscreen 1280 720 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "reflow-fullscreen" and .active)'
"$UMBRIEL" msg workspace-switch:2 > /dev/null
FILL_COLOR=0xFFFF00FF "$UMBRIEL_UNMAP_CLIENT" reflow-float-next 800 300 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "reflow-float-next" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
"$UMBRIEL" msg workspace-switch:1 > /dev/null
sed -i '0,/enabled = false/s//enabled = true/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/before.png"
[[ $(green_top "$UMBRIEL_RUNTIME_DIR/before.png") -eq 270 ]]
"$UMBRIEL" msg window-sink > /dev/null
wait_query 'any(.[]; .title == "reflow-fullscreen" and .sunk)'
sleep 0.2
grim "$UMBRIEL_RUNTIME_DIR/push.png"
push=$(green_top "$UMBRIEL_RUNTIME_DIR/push.png")
((push > 250 && push < 269)) || { echo "push did not tween locally: y=$push"; exit 1; }
shot "$UMBRIEL_RUNTIME_DIR/pushed.png"
[[ $(green_top "$UMBRIEL_RUNTIME_DIR/pushed.png") -eq 249 ]]
"$UMBRIEL" msg window-pull > /dev/null
wait_query 'any(.[]; .title == "reflow-fullscreen" and (.sunk == false) and .focused)'
sleep 0.2
grim "$UMBRIEL_RUNTIME_DIR/fill.png"
fill=$(green_top "$UMBRIEL_RUNTIME_DIR/fill.png")
((fill > 250 && fill < 269)) || { echo "fill did not tween locally: y=$fill"; exit 1; }
shot "$UMBRIEL_RUNTIME_DIR/filled.png"
[[ $(green_top "$UMBRIEL_RUNTIME_DIR/filled.png") -eq 270 ]]
for image in push pushed fill filled; do
  # The Fullscreen texture stays 320 px wide throughout: restarting Overview
  # would enlarge it. The neighbour's pixels must also remain identical.
  blue_width=$(magick "$UMBRIEL_RUNTIME_DIR/$image.png" -crop 1280x1+0+400 -depth 8 txt:- | awk '/#0000FF/ {n++} END {print n+0}')
  [[ $blue_width -eq 320 ]] || { echo "global zoom replayed: blue width=$blue_width"; exit 1; }
  magick "$UMBRIEL_RUNTIME_DIR/before.png" -crop 220x100+530+510 +repage "$UMBRIEL_RUNTIME_DIR/neighbour-before.png"
  magick "$UMBRIEL_RUNTIME_DIR/$image.png" -crop 220x100+530+510 +repage "$UMBRIEL_RUNTIME_DIR/neighbour-after.png"
  magick compare -metric AE "$UMBRIEL_RUNTIME_DIR/neighbour-before.png" "$UMBRIEL_RUNTIME_DIR/neighbour-after.png" null:
done
echo 'Overview local Sink/Pull push and fill preserve shared zoom, frozen neighbour position, and intermediate geometry'
