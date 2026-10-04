# Workspaces Overview

The overview displays every workspace and lets you navigate, focus, close, and
move windows.

## Settings and behavior

```toml
[overview]
zoom = 0.5
scroll_factor_horizontal = 1.0
scroll_factor_vertical = 1.0
background_blur = true
workspace_wallpaper = true
shortcuts = true
shortcut_keys = "1234567890"
```

| Key | Default | Description |
| --- | --- | --- |
| `zoom` | `0.5` | Workspace preview scale from 0.1 to 0.75. |
| `scroll_factor_horizontal` | `1.0` | Horizontal gesture and wheel sensitivity. |
| `scroll_factor_vertical` | `1.0` | Vertical gesture and wheel sensitivity. |
| `background_blur` | `true` | Blur the desktop behind the overview. |
| `workspace_wallpaper` | `true` | Show each output's background inside its workspace previews. |
| `shortcuts` | `true` | Show and accept keyboard shortcut badges. |
| `shortcut_keys` | `"1234567890"` | Preferred keys for shortcut badges. |

Background blur uses `[appearance.blur]`. Preview backgrounds use
`colors.overview.workspace_background` when wallpaper mirroring is disabled or
no background surface is available.

### Open and navigate

Press `Mod+O` by default, or use an
[overview action](actions.md#overview). Opening the overview temporarily hides
scratchpads and pinned windows.

- Click a window to focus it and close the overview.
- Middle-click a window to close it.
- Drag a window to move it to another workspace.
- Use the wheel to navigate vertically and Shift+wheel horizontally.
- Use a four-finger swipe to open or close the overview.

Two-finger scrolling and three-finger swipes navigate continuously. Movement
along the output's [workspace axis](workspaces.md#workspace-axis) moves between
workspaces. Movement across it pans a scrolling workspace preview. Dwindle and
Master layouts have no strip to pan.

Touchpad `natural_scroll` controls gesture direction. The horizontal and
vertical overview factors adjust gesture distance and wheel sensitivity without
changing application scrolling.

#### Which window actions act on

One card carries the full focused-border color while the overview is open. It
is the target for focus, close, and other window actions. Each other workspace
keeps a fainter marker showing which card will receive focus when selected.

The current output follows the cursor. Output-changing actions move the cursor
to their destination as usual.

#### Keyboard shortcuts

Normal `[keybinds]` remain active in the overview. Directional focus actions
select neighboring cards, and workspace or output actions keep their normal
fallback behavior.

Shortcut badges provide direct, unmodified key sequences for visible window
cards. When there are more cards than keys, Umbriel creates multi-key labels.
Backspace removes the last key from a pending sequence. Escape clears the
sequence first and closes the overview when no sequence is pending.

Set `shortcuts = false` to disable badges. A normal keybind takes precedence
over a badge. `shortcut_keys` must contain at least two unique printable ASCII
characters.

### Move windows

Drag a window onto another workspace preview to move it. In a dynamic workspace
list, dropping into a gap creates a workspace at that position. Static
workspace inventories accept drops only onto existing previews.

The destination layout shows an insertion preview before the drop. Empty
dynamic workspaces may disappear immediately after their last window is moved
or closed.

### Appearance

Overview cards reuse each window's borders, corner radius, opacity, blur, and
color presentation. Shortcut badges use `colors.overview.badge`.

Configure overview colors under
[`[colors.overview]`](appearance.md#overview-colors).

### Sink in Overview

Sink cards are centred on their workspace preview and
places them behind tiled, floating and Fullscreen foreground cards. The first
`appearance.sink.visible_depth` entries expose selectable tops; deeper entries
form a bounded decorative tail. A short window only accepts clicks within its
actual content height. Selecting an entrance unwinds and closes Overview.

The following settings control this presentation:

```toml
[overview.sink]
exposure_height = 24
tail_height = 12
tail_decay = 0.5

[animation.overview.sink]
mode = "balanced"
```

Heights use logical pixels in the final Overview view. `exposure_height` accepts
integers from 1 to 256; `tail_height` accepts 0 to 256. `tail_decay` must be a
finite number strictly between 0 and 1. Height values outside the range are
clamped with a diagnostic; invalid decay values or animation modes retain their
defaults. Modes are `performance`, `balanced`, and `smooth` (default `balanced`);
there is no separate Sink duration. The former `type` key and its values are no
longer supported. The geometry uses `appearance.sink.visible_depth` for the number
of full entrances, with a bounded tail beyond that depth.

`performance` snaps Sink size, expansion and foreground offset while the ordinary
Overview zoom continues. `balanced` interpolates Sink size, expansion and
foreground offset on the shared Overview progress; independent depth opacity and
self blur switch off on the open command and return on the close command.
`smooth` also interpolates independent depth opacity and self-blur strength on
that same progress. The modes do not stagger layers. All animated components
finish with Overview and follow the same state function when reversing.
Global or Overview animation disable snaps the transition in every mode.

At fully open Overview, all modes retain unscaled Sink source dimensions and
cancel its independent depth opacity and self blur. The foreground moves down
by half the stack's exposed height. A smooth deep tail fades from/to its hidden
desktop state; it still has no selectable entrance. Self-blur interpolation has
an effect only when `appearance.sink.self_blur` is enabled. Performance costs
vary with window sizes, hardware and configured effects; these names describe
which transitions run, rather than a measured frame-rate guarantee.

Overview reserves configured Sink capacity for every workspace, including empty
ones. Local removal does not move neighbouring previews. The reservation also
includes source geometry, chrome and animation bounds; navigation and drop
coordinates share its layout.

`window-sink` and `window-pull` also work while Overview is open. They use the
logical focused window or active workspace on the pointer's output and retain
Overview. Pull preserves the workspace's LIFO order and each window's tiled or
floating placement. Sink/Pull are ignored during card dragging or closing.

Local stack changes push cards apart or fill the gap from their current positions,
using `animation.windows_move`; they keep the predicted workspace gaps and do not
restart the opening zoom. `performance`, or disabled global, Overview or move animation,
snaps this local change. Selecting a Sink entrance by click or shortcut unwinds
to that window and immediately starts closing. Keyboard input remains withheld
until Overview releases the scene and the window's requested content commits
(with the existing bounded Pull deadline for unresponsive clients).
