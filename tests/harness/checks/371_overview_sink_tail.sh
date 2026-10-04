#!/usr/bin/env bash
# All five sources appear in an otherwise empty workspace. Only the two full
# entrances can be selected; the deeper tail never accepts click-through.
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
[appearance.sink]
visible_depth = 2
[overview]
zoom = 0.5
shortcuts = false
background_blur = false
workspace_wallpaper = false
[[window_rule]]
match.title = "^overview-tail-"
default_floating = true
default_floating_size_px = {width=400, height=300}
EOF
"$UMBRIEL" msg config-reload > /dev/null
for spec in 'a FFFF0000' 'b FFFFFF00' 'c FF00FFFF' 'd FF00FF00' 'e FF0000FF'; do
  read -r name color <<< "$spec"
  FILL_COLOR="0x$color" EXIT_ON_CLOSE=1 "$UMBRIEL_UNMAP_CLIENT" "overview-tail-$name" 400 300 > /dev/null 2>&1 &
  wait_query "any(.[]; .title == \"overview-tail-$name\" and .active)"
  "$UMBRIEL" msg window-sink > /dev/null
done
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/tail.png"
for spec in '151 FF0000' '154 FFFF00' '158 00FFFF' '165 00FF00' '190 0000FF'; do
  read -r y expected <<< "$spec"
  actual=$(magick "$UMBRIEL_RUNTIME_DIR/tail.png" -crop "1x1+640+$y" -format '%[hex:p{0,0}]' info:)
  [[ $actual == "$expected"* ]] || { echo "tail pixel y=$y expected $expected, got $actual"; exit 1; }
done
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 154 press 272 release 272
shot "$UMBRIEL_RUNTIME_DIR/tail-click.png"
wait_query 'length == 5 and all(.[]; .sunk and (.focused == false))'
cmp "$UMBRIEL_RUNTIME_DIR/tail.png" "$UMBRIEL_RUNTIME_DIR/tail-click.png"
# A full entrance remains an ordinary close target, even with the tail above
# it. Its removal must update both texture ordering and input ordering.
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 165 press 274 release 274
wait_query 'length == 4 and all(.[]; .title != "overview-tail-d")'
shot "$UMBRIEL_RUNTIME_DIR/tail-reflow.png"
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 190 press 272 release 272
wait_query 'any(.[]; .title == "overview-tail-e" and (.sunk == false) and .focused)'
wait_query '[.[] | select(.sunk)] | length == 3'
echo 'Overview shows an ordered bounded tail beyond visible depth and restricts selection to full entrances'
