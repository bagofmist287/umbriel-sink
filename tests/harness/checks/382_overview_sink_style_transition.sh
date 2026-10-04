#!/usr/bin/env bash
# Real framebuffer size and alpha pin symmetric opening/closing handoff.
# A separate red card measures the actual shared clock at screenshot time.
set -euo pipefail
wait_query() {
  for _ in $(seq 100); do "$UMBRIEL" windows --json | jq -e "$1" >/dev/null && return 0; sleep 0.025; done
  echo "query did not settle: $1"; return 1
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
cat >> "$UMBRIEL_CONFIG" <<'CONFIG'

[animation]
enabled = false
[animation.windows_in]
enabled = false
[animation.windows_move]
enabled = false
[animation.overview]
duration_ms = 1200
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
levels = [{scale=0.4, opacity=0.25, blur_strength=1.0}, {scale=0.4, opacity=0.25, blur_strength=1.0}]
self_blur = false
blur_radius = 32
blur_samples = 17
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
match.title = "^style-sink$"
default_floating = true
default_floating_size_px = {width=800,height=300}
[[window_rule]]
match.title = "^style-clock$"
default_floating = true
default_floating_size_px = {width=400,height=32}
default_position = {x=0,y=640,anchor="top_left"}
CONFIG
"$UMBRIEL" msg config-reload >/dev/null
FILL_COLOR=0xFF0000FF "$UMBRIEL_UNMAP_CLIENT" style-sink 800 300 >/dev/null 2>&1 &
wait_query 'any(.[]; .title == "style-sink" and .active and .w == 800)'
"$UMBRIEL" msg window-sink >/dev/null
FILL_COLOR=0xFFFF0000 "$UMBRIEL_UNMAP_CLIENT" style-clock 400 32 >/dev/null 2>&1 &
wait_query 'any(.[]; .title == "style-clock" and .active and .w == 400)'
sed -i '0,/enabled = false/s//enabled = true/' "$UMBRIEL_CONFIG"
for blur in false true; do
  sed -i "s/^self_blur = .*/self_blur = $blur/" "$UMBRIEL_CONFIG"
  for mode in performance balanced smooth; do
    sed -i "s/^mode = .*/mode = \"$mode\"/" "$UMBRIEL_CONFIG"
    "$UMBRIEL" msg config-reload >/dev/null
    for direction in open close; do
      "$UMBRIEL" msg "overview-$direction" >/dev/null
      sleep 0.4
      grim "$UMBRIEL_RUNTIME_DIR/$blur-$mode-$direction.png"
      magick "$UMBRIEL_RUNTIME_DIR/$blur-$mode-$direction.png" -depth 8 "RGB:$UMBRIEL_RUNTIME_DIR/frame.rgb"
      python3 - "$UMBRIEL_RUNTIME_DIR/frame.rgb" "$mode" "$direction" "$blur" <<'PY'
import sys
from pathlib import Path
pixels = Path(sys.argv[1]).read_bytes()
mode, direction, blur = sys.argv[2:]
def pixel(x, y):
    i = (y * 1280 + x) * 3
    return pixels[i:i+3]
red = [(x,y) for y in range(720) for x in range(1280) if pixel(x,y) == bytes((255,0,0))]
assert red, 'clock card missing'
zoom = (max(x for x,y in red) - min(x for x,y in red) + 1) / 400
p = (1 - zoom) / .5
assert .1 < p < .9, f'missed transition: {p}'
style = (1 if direction == 'open' else 0) if mode == 'performance' else p
expected_width = (320 + 480 * style) * zoom
blue = [(x,y) for y in range(720) for x in range(1280) if pixel(x,y)[2] > 2 and pixel(x,y)[0:2] == bytes((0,0))]
assert blue, 'sink card missing'
left, right = min(x for x,y in blue), max(x for x,y in blue)
assert abs(right - left + 1 - expected_width) <= 4, (mode,direction,blur,p,right-left+1,expected_width)
assert abs((left + right + 1) / 2 - 640) <= 1, 'lost horizontal centre'
top, bottom = min(y for x,y in blue), max(y for x,y in blue)
y = (top + bottom) // 2
center = pixel(640,y)[2]
alpha_progress = p if mode == 'smooth' else (1 if direction == 'open' else 0)
expected_alpha = 255 * (.25 + .75 * alpha_progress)
assert abs(center - expected_alpha) <= 3, (mode,direction,blur,p,center,expected_alpha)
edge_ratio = pixel(left + 2,y)[2] / center
has_blur = blur == 'true' and (mode == 'smooth' or direction == 'close')
assert (edge_ratio < .9 if has_blur else edge_ratio > .97), (mode,direction,blur,p,edge_ratio)
print(f'{mode} {direction} blur={blur}: p={p:.3f}, width={right-left+1}, alpha={center}, edge={edge_ratio:.3f}')
PY
      # Reversing midway must still obey the same size/effect state function.
      if [[ $direction == open && $mode != performance ]]; then
        "$UMBRIEL" msg overview-close >/dev/null
        sleep 0.05
        "$UMBRIEL" msg overview-open >/dev/null
      fi
      settle
    done
  done
done
echo 'All three modes honor size, alpha, blur and centred geometry in both directions'
