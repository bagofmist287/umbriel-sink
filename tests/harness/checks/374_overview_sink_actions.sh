#!/usr/bin/env bash
# Explicit Sink/Pull use Overview's logical target, retain Overview, and preserve
# LIFO/base placement across all native layouts. Configured keys use the same path.
set -euo pipefail
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do
    windows | jq -e "$1" > /dev/null && return 0
    sleep 0.025
  done
  echo "query did not settle: $1; $(windows)"; return 1
}
id() { windows | jq -r --arg title "$1" '.[] | select(.title == $title) | .id'; }
focus() {
  "$UMBRIEL" msg "window-focus:$(id "$1")" > /dev/null
  wait_query "any(.[]; .title == \"$1\" and .focused)"
}
assert_open() {
  for _ in $(seq 100); do
    jq -se 'last | .data.open == true' "$UMBRIEL_RUNTIME_DIR/overview-events.log" > /dev/null && return 0
    sleep 0.025
  done
  echo 'Sink/Pull closed Overview'; return 1
}
cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
enabled = false
[overview]
shortcuts = false
[input.focus]
follows_mouse = false
[keybinds]
"Ctrl+S" = "window-sink"
"Ctrl+P" = "window-pull"
[[window_rule]]
match.title = "^overview-action-float$"
default_floating = true
default_floating_size_px = {width=400, height=300}
EOF
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" subscribe overview > "$UMBRIEL_RUNTIME_DIR/overview-events.log" &
for title in overview-action-first overview-action-second overview-action-float; do
  "$UMBRIEL_UNMAP_CLIENT" "$title" 400 300 > "$UMBRIEL_RUNTIME_DIR/$title.log" 2>&1 &
  # Map admission precedes its deferred map focus. Let that settle before
  # choosing the window to be operated on inside Overview.
  wait_query "any(.[]; .title == \"$title\" and .active)"
done
for layout in scrolling dwindle master; do
  "$UMBRIEL" msg "workspace-set-layout:$layout" > /dev/null
  focus overview-action-second
  "$UMBRIEL" msg overview-open > /dev/null
  assert_open
  "$UMBRIEL_POINTER_CLIENT" 1280 720 mod control tap 31 mod none
  wait_query 'any(.[]; .title == "overview-action-second" and .sunk and .sink_depth == 0)'
  assert_open
  focus overview-action-first
  "$UMBRIEL" msg window-sink > /dev/null
  wait_query 'any(.[]; .title == "overview-action-first" and .sink_depth == 0) and any(.[]; .title == "overview-action-second" and .sink_depth == 1)'
  assert_open
  "$UMBRIEL_POINTER_CLIENT" 1280 720 mod control tap 25 mod none
  wait_query 'any(.[]; .title == "overview-action-first" and (.sunk == false) and .focused and .base_placement == "tiled")'
  assert_open
  # Retarget before a client could have finished a pending resize. Re-Sink must
  # cancel its old Pull owner/generation, then return the same LIFO member.
  "$UMBRIEL" msg window-sink > /dev/null
  "$UMBRIEL" msg window-pull > /dev/null
  wait_query 'any(.[]; .title == "overview-action-first" and (.sunk == false) and .focused)'
  "$UMBRIEL" msg window-pull > /dev/null
  wait_query 'all(.[]; .sunk == false) and any(.[]; .title == "overview-action-second" and .focused)'
  focus overview-action-float
  "$UMBRIEL" msg window-sink > /dev/null
  assert_open
  "$UMBRIEL" msg window-pull > /dev/null
  wait_query 'any(.[]; .title == "overview-action-float" and (.sunk == false) and .focused and .base_placement == "floating" and .w == 400 and .h == 300)'
  assert_open
  "$UMBRIEL" msg overview-close > /dev/null
done
echo 'Overview Sink/Pull preserve Scrolling/Dwindle/Master LIFO, floating size, rapid retargeting, and configured key actions'
