#!/usr/bin/env bash
# Real textures and pointer selection pin Sink centring, unscaled dimensions,
# Fullscreen layering, and the shared foreground offset without animation.
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
assert_color() {
  local actual
  actual=$(magick "$1" -crop "1x1+$2+$3" -format '%[hex:p{0,0}]' info:)
  [[ $actual == "$4"* ]] || { echo "pixel $2,$3 expected $4, got $actual"; return 1; }
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
[appearance.sink]
levels = [{scale=0.6, opacity=0.1, blur_strength=0.0}, {scale=0.5, opacity=0.1, blur_strength=0.0}]
[colors]
backdrop = "#000000FF"
[colors.overview]
background_tint = "#000000FF"
workspace_background = "#000000FF"
[overview]
zoom = 0.5
shortcuts = false
background_blur = false
workspace_wallpaper = false
[[window_rule]]
match.title = "^overview-sink-floating$"
default_floating = true
default_floating_size_px = {width=400, height=300}
default_position = {x=100, y=100, anchor="top_left"}
[[window_rule]]
match.title = "^overview-sink-short$"
default_floating = true
default_floating_size_px = {width=80, height=32}
EOF
"$UMBRIEL" msg config-reload > /dev/null
FILL_COLOR=0xFF0000FF EXIT_ON_CLOSE=1 "$UMBRIEL_UNMAP_CLIENT" overview-sink-floating 400 300 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "overview-sink-floating" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/floating.png"
# Preview centre 640; original x=100 must not survive. h=24 and F=12
# place the full-opacity 200x150 source at 540,168.
assert_color "$UMBRIEL_RUNTIME_DIR/floating.png" 540 174 0000FF
assert_color "$UMBRIEL_RUNTIME_DIR/floating.png" 739 174 0000FF
assert_color "$UMBRIEL_RUNTIME_DIR/floating.png" 539 174 000000
assert_color "$UMBRIEL_RUNTIME_DIR/floating.png" 740 174 000000
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 174 press 272 release 272
wait_query 'any(.[]; .title == "overview-sink-floating" and (.sunk == false) and .focused)'
"$UMBRIEL" msg window-close > /dev/null
wait_query 'length == 0'

FILL_COLOR=0xFF00FFFF EXIT_ON_CLOSE=1 "$UMBRIEL_UNMAP_CLIENT" overview-sink-short 80 32 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "overview-sink-short" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/short.png"
assert_color "$UMBRIEL_RUNTIME_DIR/short.png" 640 183 00FFFF
assert_color "$UMBRIEL_RUNTIME_DIR/short.png" 640 184 000000
# Its projected height is 16, below the configured 24. The empty remainder
# belongs to the workspace background and must not pull the short window.
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 188 press 272 release 272
wait_query 'any(.[]; .title == "overview-sink-short" and .sunk)'
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/short-reopen.png"
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 174 press 272 release 272
wait_query 'any(.[]; .title == "overview-sink-short" and (.sunk == false) and .focused)'
"$UMBRIEL" msg window-close > /dev/null
wait_query 'length == 0'

FILL_COLOR=0xFFFF0000 REQUEST_FULLSCREEN=1 "$UMBRIEL_UNMAP_CLIENT" overview-sink-fullscreen 1280 720 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "overview-sink-fullscreen" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
FILL_COLOR=0xFF00FF00 "$UMBRIEL_UNMAP_CLIENT" overview-sink-foreground 1280 720 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "overview-sink-foreground" and .active)'
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/fullscreen.png"
assert_color "$UMBRIEL_RUNTIME_DIR/fullscreen.png" 640 174 FF0000
assert_color "$UMBRIEL_RUNTIME_DIR/fullscreen.png" 640 360 00FF00
# An overlap must select the ordinary foreground, not the Sunk Fullscreen.
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 360 press 272 release 272
wait_query 'any(.[]; .title == "overview-sink-foreground" and .focused)'
wait_query 'any(.[]; .title == "overview-sink-fullscreen" and .sunk)'
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/fullscreen-reopen.png"
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 174 press 272 release 272
wait_query 'any(.[]; .title == "overview-sink-fullscreen" and (.sunk == false) and .focused)'
echo 'Overview Sink cards centre stable source dimensions, cancel depth effects, and agree with foreground hit order'
