#!/usr/bin/env bash
# Derive actual Overview progress from the Fullscreen card's width, rather than
# assuming the screenshot landed at a particular wall-clock instant. Both Sink
# layers and the foreground must use that same progress and finish together.
set -euo pipefail
wait_query() {
  for _ in $(seq 100); do
    "$UMBRIEL" windows --json | jq -e "$1" > /dev/null && return 0
    sleep 0.025
  done
  echo "query did not settle: $1"; return 1
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
[animation.windows_in]
enabled = false
[animation.windows_move]
enabled = false
[animation.overview]
duration_ms = 1000
curve = "linear"
[animation.overview.sink]
mode = "balanced"
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
levels = [{scale=1.0, opacity=1.0, blur_strength=0.0}, {scale=1.0, opacity=1.0, blur_strength=0.0}]
[overview]
zoom = 0.5
shortcuts = false
background_blur = false
workspace_wallpaper = false
[overview.sink]
exposure_height = 120
[[window_rule]]
match.title = "^animation-sink-"
default_floating = true
default_floating_size_px = {width=800, height=300}
EOF
"$UMBRIEL" msg config-reload > /dev/null
for spec in 'deep FF00FF00' 'top FF0000FF'; do
  read -r name color <<< "$spec"
  FILL_COLOR="0x$color" "$UMBRIEL_UNMAP_CLIENT" "animation-sink-$name" 800 300 > /dev/null 2>&1 &
  wait_query "any(.[]; .title == \"animation-sink-$name\" and .active)"
  "$UMBRIEL" msg window-sink > /dev/null
done
FILL_COLOR=0xFFFF0000 REQUEST_FULLSCREEN=1 "$UMBRIEL_UNMAP_CLIENT" animation-foreground 1280 720 > /dev/null 2>&1 &
wait_query 'any(.[]; .title == "animation-foreground" and .active)'
sed -i '0,/enabled = false/s//enabled = true/' "$UMBRIEL_CONFIG"
for type in performance balanced smooth; do
  sed -i "s/^mode = .*/mode = \"$type\"/" "$UMBRIEL_CONFIG"
  "$UMBRIEL" msg config-reload > /dev/null
  "$UMBRIEL" msg overview-open > /dev/null
  sleep 0.6
  grim "$UMBRIEL_RUNTIME_DIR/$type-moving.png"
  magick "$UMBRIEL_RUNTIME_DIR/$type-moving.png" -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/moving.rgb"
  python3 - "$UMBRIEL_RUNTIME_DIR/moving.rgb" "$type" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
kind = sys.argv[2]
assert len(data) == 1280 * 720 * 3
def pixel(x, y):
    i = (y * 1280 + x) * 3
    return data[i:i+3]
red = [x for x in range(1280) if pixel(x, 360) == bytes((255, 0, 0))]
assert red, 'foreground is missing'
zoom = len(red) / 1280
p = (1 - zoom) / 0.5
assert 0.55 < p < 0.95, f'screenshot missed the moving phase: {p}'
base = round((720 - round(720 * zoom)) / 2)
progress = 1 if kind == 'performance' else p
shift = 120 * progress
def top(color):
    ys = [y for y in range(720) if pixel(640, y) == bytes(color)]
    assert ys, f'missing color {color}'
    return min(ys)
assert abs(top((255, 0, 0)) - (base + shift)) <= 2, (kind, p, 'foreground offset')
collapsed = 210 * zoom
for depth, color in [(0, (0, 0, 255)), (1, (0, 255, 0))]:
    layer = progress
    expected = max(0, base + shift + collapsed - ((depth + 1) * 120 + collapsed) * layer)
    assert abs(top(color) - expected) <= 2, (kind, p, depth, top(color), expected)
print(f'{kind}: both layers and foreground share measured progress {p:.3f}')
PY
  # Reverse the common clock twice before it lands; no independent layer timer
  # may carry on after the final Overview open has settled.
  "$UMBRIEL" msg overview-close > /dev/null
  sleep 0.1
  "$UMBRIEL" msg overview-open > /dev/null
  shot "$UMBRIEL_RUNTIME_DIR/$type-settled.png"
done
magick compare -metric AE "$UMBRIEL_RUNTIME_DIR/performance-settled.png" "$UMBRIEL_RUNTIME_DIR/balanced-settled.png" null:
magick compare -metric AE "$UMBRIEL_RUNTIME_DIR/performance-settled.png" "$UMBRIEL_RUNTIME_DIR/smooth-settled.png" null:
# Omitting both selects the native default spring without a meaningless
# duration override (spring curves derive their own duration).
sed -i '/^curve = "linear"$/d; /^duration_ms = 1000$/d' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/spring-settled.png"
magick compare -metric AE "$UMBRIEL_RUNTIME_DIR/performance-settled.png" "$UMBRIEL_RUNTIME_DIR/spring-settled.png" null:
sed -i '0,/enabled = true/s//enabled = false/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" msg overview-open > /dev/null
shot "$UMBRIEL_RUNTIME_DIR/disabled.png"
magick compare -metric AE "$UMBRIEL_RUNTIME_DIR/performance-settled.png" "$UMBRIEL_RUNTIME_DIR/disabled.png" null:
echo 'performance/balanced/smooth share the Overview clock and foreground motion, reverse, and land together with spring or disabled animations'
