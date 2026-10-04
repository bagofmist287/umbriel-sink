#!/usr/bin/env bash
# Overview logical selection must not deliver keyboard focus early. A slow
# resize, re-Sink generation cancellation, and click-Unwind cross the close
# handoff while the original desktop commit barrier remains intact.
set -euo pipefail
readonly CLIENT_LOG="$UMBRIEL_RUNTIME_DIR/overview-slow.log"
windows() { "$UMBRIEL" windows --json; }
wait_query() {
  for _ in $(seq 100); do
    windows | jq -e "$1" > /dev/null && return 0
    sleep 0.025
  done
  echo "query did not settle: $1; $(windows)"; return 1
}
enters() { grep -c '^keyboard-enter' "$CLIENT_LOG" || true; }
wait_overview() {
  for _ in $(seq 100); do
    jq -se "last | .data.open == $1" "$UMBRIEL_RUNTIME_DIR/overview-events.log" > /dev/null && return 0
    sleep 0.025
  done
  echo "Overview did not become $1"; return 1
}
cat >> "$UMBRIEL_CONFIG" <<'EOF'

[layout]
mode = "master"
[animation]
enabled = false
[animation.windows_in]
enabled = false
[animation.windows_move]
duration_ms = 1000
curve = "linear"
[animation.overview]
duration_ms = 500
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
EOF
"$UMBRIEL" msg config-reload > /dev/null
mkfifo "$UMBRIEL_RUNTIME_DIR/control"
exec {control_fd}<>"$UMBRIEL_RUNTIME_DIR/control"
HOLD_RESIZE=1 "$UMBRIEL_SEAT_LOG_CLIENT" overview-slow <&"$control_fd" > "$CLIENT_LOG" 2>&1 &
wait_query 'any(.[]; .title == "overview-slow" and .active)'
# Keep a keyboard alive so absence of enter cannot merely mean the headless
# seat had no keyboard. Other pointer commands may create short-lived peers.
"$UMBRIEL_POINTER_CLIENT" 1280 720 mod none pause 15000 > /dev/null 2>&1 &
"$UMBRIEL" msg "window-focus:$(windows | jq -r '.[] | select(.title == "overview-slow") | .id')" > /dev/null
for _ in $(seq 100); do [[ $(enters) -ge 1 ]] && break; sleep 0.025; done
baseline=$(enters)
[[ $baseline -ge 1 ]]
"$UMBRIEL" msg window-sink > /dev/null
FILL_COLOR=0xFFFF0000 "$UMBRIEL_UNMAP_CLIENT" overview-slow-peer 1280 720 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "overview-slow-peer" and .active)'
sed -i '0,/enabled = false/s//enabled = true/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" subscribe overview > "$UMBRIEL_RUNTIME_DIR/overview-events.log" &
"$UMBRIEL" msg overview-open > /dev/null
wait_overview true
# Await the opening endpoint by equal consecutive frames, before testing a
# different transition. The test never assumes a sleep means it has completed.
grim "$UMBRIEL_RUNTIME_DIR/previous.png"
for _ in $(seq 100); do
  sleep 0.025
  grim "$UMBRIEL_RUNTIME_DIR/current.png"
  if cmp -s "$UMBRIEL_RUNTIME_DIR/previous.png" "$UMBRIEL_RUNTIME_DIR/current.png"; then break; fi
  cp "$UMBRIEL_RUNTIME_DIR/current.png" "$UMBRIEL_RUNTIME_DIR/previous.png"
done
"$UMBRIEL" msg window-pull > /dev/null
wait_query 'any(.[]; .title == "overview-slow" and (.sunk == false) and .focused)'
wait_overview true
"$UMBRIEL_POINTER_CLIENT" 1280 720 tap 30
[[ $(enters) -eq $baseline ]] || { echo 'Overview Pull delivered keyboard enter'; exit 1; }
! grep -q '^keyboard-key code=30' "$CLIENT_LOG"
"$UMBRIEL" msg window-sink > /dev/null
wait_query 'any(.[]; .title == "overview-slow" and .sunk)'
# Click its current exposed top while local reflow is still running. Input and
# pixels must agree, and the close must begin now rather than after the move.
grim "$UMBRIEL_RUNTIME_DIR/click.png"
magick "$UMBRIEL_RUNTIME_DIR/click.png" -crop 1x720+640+0 -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/column.rgb"
click_y=$(python3 - "$UMBRIEL_RUNTIME_DIR/column.rgb" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
ys=[y for y in range(720) if d[y*3:y*3+3] == bytes((51,136,204))]
assert ys, 'slow Sink has no exposed top'
print(min(ys)+2)
PY
)
"$UMBRIEL_POINTER_CLIENT" 1280 720 move 640 "$click_y" press 272 release 272
wait_query 'any(.[]; .title == "overview-slow" and (.sunk == false) and .focused)'
if "$UMBRIEL" msg window-sink > "$UMBRIEL_RUNTIME_DIR/closing-action.log" 2>&1; then
  echo 'Sink selection did not immediately begin Overview closing'; exit 1
fi
grep -q 'Overview closing' "$UMBRIEL_RUNTIME_DIR/closing-action.log"
wait_overview false
[[ $(enters) -eq $baseline ]] || { echo 'Overview close bypassed the held resize commit'; exit 1; }
if [[ ${OVERVIEW_COMMIT_SWITCH_TARGET:-0} == 1 ]]; then
  peer_id=$(windows | jq -r '.[] | select(.title == "overview-slow-peer") | .id')
  "$UMBRIEL" msg "window-focus:$peer_id" >/dev/null
  wait_query 'any(.[]; .title == "overview-slow-peer" and .focused)'
fi
printf x >&"$control_fd"
exec {control_fd}>&-
if [[ ${OVERVIEW_COMMIT_SWITCH_TARGET:-0} == 1 ]]; then
  # Cover both successful commit and the 1200ms degradation boundary. Neither
  # may resurrect a selection the user replaced after Overview closed.
  sleep 1.3
  wait_query 'any(.[]; .title == "overview-slow-peer" and .focused)'
  [[ $(enters) -eq $baseline ]] || { echo 'obsolete Overview Pull stole focus after a new selection'; exit 1; }
  echo 'a newer desktop focus choice cancels the deferred Overview Pull selection'
  exit 0
fi
for _ in $(seq 100); do [[ $(enters) -gt $baseline ]] && break; sleep 0.025; done
[[ $(enters) -gt $baseline ]] || { echo 'committed selected Pull did not restore keyboard focus'; exit 1; }
"$UMBRIEL_POINTER_CLIENT" 1280 720 tap 30
for _ in $(seq 100); do grep -q '^keyboard-key code=30 state=pressed' "$CLIENT_LOG" && break; sleep 0.025; done
grep -q '^keyboard-key code=30 state=pressed' "$CLIENT_LOG"
echo 'Overview Pull holds input, re-Sink cancels its old generation, click-Unwind closes immediately, and commit restores focus'
