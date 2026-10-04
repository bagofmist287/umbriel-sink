#!/usr/bin/env bash
# Baseline comparison diagnostic, not a permanent regression contract. Results
# describe the selected binary, including incomplete Overview action paths.
# Run inside the isolated harness; retain evidence outside its disposable runtime.
set -euo pipefail
: "${UMBRIEL_RUNTIME_DIR:?requires an isolated harness instance}"
: "${SINK_BASELINE_DIR:?requires a dedicated evidence directory}"
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do
    windows | jq -e "$1" > /dev/null && return 0
    sleep 0.025
  done
  echo "query did not settle: $1; $(windows)"
  return 1
}
settled_shot() {
  local target=$1 previous="$UMBRIEL_RUNTIME_DIR/previous.png" current="$UMBRIEL_RUNTIME_DIR/current.png"
  grim "$previous"
  for _ in $(seq 100); do
    sleep 0.025
    grim "$current"
    if cmp -s "$previous" "$current"; then cp "$current" "$target"; return 0; fi
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
self_blur = false
levels = [{scale=0.8, opacity=1.0, blur_strength=0.0}, {scale=0.7, opacity=1.0, blur_strength=0.0}]
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
match.title = "^baseline-floating$"
default_floating = true
default_floating_size_px = {width=400, height=300}
default_position = {x=100, y=100, anchor="top_left"}
EOF
"$UMBRIEL" msg config-reload > /dev/null
FILL_COLOR=0xFF0000FF EXIT_ON_CLOSE=1 "$UMBRIEL_UNMAP_CLIENT" baseline-floating 400 300 > "$UMBRIEL_RUNTIME_DIR/floating.log" 2>&1 &
wait_query 'any(.[]; .title == "baseline-floating" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
wait_query 'any(.[]; .title == "baseline-floating" and .sunk)'
settled_shot "$SINK_BASELINE_DIR/floating-desktop.png"
"$UMBRIEL" msg overview-open > /dev/null
settled_shot "$SINK_BASELINE_DIR/floating-overview.png"
windows > "$SINK_BASELINE_DIR/floating-windows.json"
"$UMBRIEL" msg overview-close > /dev/null
"$UMBRIEL" msg window-pull > /dev/null
wait_query 'any(.[]; .title == "baseline-floating" and (.sunk == false) and .active)'
"$UMBRIEL" msg window-close > /dev/null
wait_query 'length == 0'
FILL_COLOR=0xFFFF0000 REQUEST_FULLSCREEN=1 "$UMBRIEL_UNMAP_CLIENT" baseline-fullscreen 1280 720 > "$UMBRIEL_RUNTIME_DIR/fullscreen.log" 2>&1 &
wait_query 'any(.[]; .title == "baseline-fullscreen" and .active)'
"$UMBRIEL" msg window-sink > /dev/null
wait_query 'any(.[]; .title == "baseline-fullscreen" and .sunk)'
FILL_COLOR=0xFF00FF00 "$UMBRIEL_UNMAP_CLIENT" baseline-foreground 1280 720 > "$UMBRIEL_RUNTIME_DIR/foreground.log" 2>&1 &
wait_query 'any(.[]; .title == "baseline-foreground" and .active)'
settled_shot "$SINK_BASELINE_DIR/fullscreen-desktop.png"
"$UMBRIEL" msg overview-open > /dev/null
settled_shot "$SINK_BASELINE_DIR/fullscreen-overview.png"
windows > "$SINK_BASELINE_DIR/fullscreen-windows.json"
"$UMBRIEL" msg window-sink > "$SINK_BASELINE_DIR/sink-action.txt" 2>&1 || true
windows > "$SINK_BASELINE_DIR/after-sink-action.json"
"$UMBRIEL" msg window-pull > "$SINK_BASELINE_DIR/pull-action.txt" 2>&1 || true
windows > "$SINK_BASELINE_DIR/after-pull-action.json"
settled_shot "$SINK_BASELINE_DIR/after-pull-overview.png"
cp "$UMBRIEL_CONFIG" "$SINK_BASELINE_DIR/config.toml"
cp "$UMBRIEL_LOG" "$SINK_BASELINE_DIR/compositor.log"
echo "Sink diagnostic recorded in $SINK_BASELINE_DIR"
