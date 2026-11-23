# Resource audit - 2026-11-17

Offline tests use the production routing and ribbon code with mock host/OpenFL/Starling objects. They do not measure the game process, GPU memory, FPS, or device power.

## Changes

- Visibility-mask comparison no longer builds a temporary string and character array.
- Reuse fade-distance buffers and scratch points.
- Apply cap/fade vertex edits only within 25 world units of visible ends; interior vertices use the copied geometry directly.
- Ribbon subdivisions use at most 10 world units instead of 5: roughly half the long-straight-route points and vertices. Authored curved points are preserved.
- Fades remain vertex alpha within the same two ribbon meshes; no extra render pass, blur filter, or render texture.

## Repeated measurements

150 moving-mask changes on a fixed 4,000-segment ribbon, Haxe interpreter with graphics stubs:

| Run | Before (ms) | After (ms) |
|---|---:|---:|
| 1 | 649.44 | 221.17 |
| 2 | 655.80 | 215.76 |
| 3 | 653.80 | 221.93 |

Mean reduction about 66.4%. This isolates ribbon-update CPU work, not whole-game CPU. Both versions used the same segment count; the subdivision reduction is additional.

Twelve complete cache builds alternating 20/30 tiles, 36 anchors per tile, drawing creation, display switching, destruction and cache clearing: passed. Cached routes, fields, edge checks, scene mounts, texture lists and vertex buffers were empty after cleanup. Interpreter live heap after full collection: 10,381.89 KiB after match 1; 10,382.63 KiB after matches 2-12. No continuing retained growth in this simulation. This heap includes the interpreter and test harness.

Fade checks: zero-alpha endpoints, gradual 25-unit fade, rounded silhouette, opaque middle and buffer cleanup passed. Independent 3D/Pathfinder resource release and restoration passed.

## Lifecycle review

Outside a match, only settings/shortcut and match-lifecycle subscriptions remain. Floor arrival creates match-owned UI, planner, geometry subscriptions and frame updates. Floor exit cancels geometry and frame handlers, clears routes/caches and releases drawing resources. Invisible Pathfinder keeps shared route guidance only when a compass needs it. Disabling all displays clears navigation caches. Native renderer/driver allocators can retain reusable memory after disposal; actual process/GPU behavior requires an in-game profiling run.

All-three-off now calls the same navigation teardown used at match exit: destroys the drawing objects, clears and drops the planner, drops hero/goal references, removes the navigation frame handler, and cancels geometry subscriptions. The lightweight floating settings controls and floor/hero lifecycle listeners remain for reactivation; no route building or navigation animation runs until a display is selected again. The global Enable Gate Compass row is no longer registered; the configurable shortcut retains enable state in a private data file.
