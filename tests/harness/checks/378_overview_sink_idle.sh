#!/usr/bin/env bash
# Opening and local stack reflow must stop scheduling frames at their endpoint.
set -euo pipefail
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do windows | jq -e "$1" >/dev/null && return 0; sleep 0.025; done
  echo "query did not settle: $1; $(windows)"; return 1
}
settle() {
  grim "$UMBRIEL_RUNTIME_DIR/previous.png"
  for _ in $(seq 100); do
    sleep 0.025
    grim "$UMBRIEL_RUNTIME_DIR/current.png"
    if cmp -s "$UMBRIEL_RUNTIME_DIR/previous.png" "$UMBRIEL_RUNTIME_DIR/current.png"; then return 0; fi
    cp "$UMBRIEL_RUNTIME_DIR/current.png" "$UMBRIEL_RUNTIME_DIR/previous.png"
  done
  echo 'frame did not settle'; return 1
}
idle() {
  local label=$1 before after
  before=$("$UMBRIEL" render-stats --json)
  sleep 1
  after=$("$UMBRIEL" render-stats --json)
  jq -en --argjson a "$before" --argjson b "$after" \
    '$b[0].rendered_frames == $a[0].rendered_frames and $b[0].frame_callbacks == $a[0].frame_callbacks' >/dev/null || {
      echo "$label kept repainting: $before -> $after"; return 1;
    }
  echo "$label idle: zero renders/callbacks over 1s"
}
cat >> "$UMBRIEL_CONFIG" <<'CONFIG'

[animation.windows_in]
enabled = false
[animation.windows_move]
duration_ms = 200
curve = "linear"
[animation.overview]
duration_ms = 200
curve = "linear"
[animation.overview.sink]
mode = "balanced"
[overview]
shortcuts = false
background_blur = false
workspace_wallpaper = false
[appearance.blur]
enabled = false
CONFIG
"$UMBRIEL" msg config-reload >/dev/null
for i in 1 2 3; do
  "$UMBRIEL_UNMAP_CLIENT" "idle-sink-$i" 800 600 >/dev/null 2>&1 &
  wait_query "any(.[]; .title == \"idle-sink-$i\" and .active)"
  "$UMBRIEL" msg window-sink >/dev/null
done
for type in performance balanced smooth; do
  sed -i "s/mode = \".*\"/mode = \"$type\"/" "$UMBRIEL_CONFIG"
  "$UMBRIEL" msg config-reload >/dev/null
  "$UMBRIEL" msg overview-open >/dev/null
  settle
  idle "$type opening"
  "$UMBRIEL" msg window-pull >/dev/null
  wait_query 'any(.[]; .title == "idle-sink-3" and (.sunk == false) and .focused)'
  "$UMBRIEL" msg window-sink >/dev/null
  wait_query 'length == 3 and all(.[]; .sunk)'
  settle
  idle "$type local reflow"
done
