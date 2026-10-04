#!/usr/bin/env bash
# Predicted capacity separates adjacent previews. Removing a local stack leaves
# the neighbouring preview fixed, and its overhanging entrance still selects it.
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
cat >> "$UMBRIEL_CONFIG" <<'EOF'

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
[[window_rule]]
match.title = "^spacing-sink-"
default_floating = true
default_floating_size_px = {width=400, height=300}
EOF
"$UMBRIEL" msg config-reload > /dev/null
FILL_COLOR=0xFF00FF00 EXIT_ON_CLOSE=1 "$UMBRIEL_UNMAP_CLIENT" spacing-sink-first 400 300 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "spacing-sink-first" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
FILL_COLOR=0xFFFF0000 REQUEST_FULLSCREEN=1 "$UMBRIEL_UNMAP_CLIENT" spacing-foreground 1280 720 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "spacing-foreground" and .active)'
"$UMBRIEL" msg workspace-switch:2 > /dev/null
FILL_COLOR=0xFF0000FF "$UMBRIEL_UNMAP_CLIENT" spacing-sink-next 400 300 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "spacing-sink-next" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
"$UMBRIEL" msg workspace-switch:1 > /dev/null
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/before.png"
blue=$(magick "$UMBRIEL_RUNTIME_DIR/before.png" -crop 1x1+640+524 -format '%[fx:round(255*mean.b)]' info:)
[[ $blue -eq 255 ]] || { echo "neighbour entrance missing after capacity reservation: blue=$blue"; exit 1; }
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 264 press 274 release 274
wait_query 'length == 2 and all(.[]; .title != "spacing-sink-first")'
shot "$UMBRIEL_RUNTIME_DIR/after.png"
magick "$UMBRIEL_RUNTIME_DIR/before.png" -crop 120x100+580+510 +repage "$UMBRIEL_RUNTIME_DIR/neighbour-before.png"
magick "$UMBRIEL_RUNTIME_DIR/after.png" -crop 120x100+580+510 +repage "$UMBRIEL_RUNTIME_DIR/neighbour-after.png"
magick compare -metric AE "$UMBRIEL_RUNTIME_DIR/neighbour-before.png" "$UMBRIEL_RUNTIME_DIR/neighbour-after.png" null:
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 524 press 272 release 272
wait_query 'any(.[]; .title == "spacing-sink-next" and (.sunk == false) and .focused)'
echo 'Overview reserves empty and populated workspace capacity, freezes local spacing, and selects an overhanging neighbour'
