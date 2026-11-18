# Performance and fast movement review, 2026-11-18

The reported exit-room hitches have plausible CPU causes in 0.2.11: up to 36 precomputed starts per tile, synchronous whole-route simplification inside a nominally sliced task, full-path ribbon generation, and search advancement before hidden-menu checks. This is code evidence, not a diagnosis from a measured low-end game session.

Changes: hide/pause first, then search. Exit, infinite exit, revive, Settings and results layers pause even when covered by another popup. Camera/mask work skips invisible compass graphics. Stationary near-waypoint checks no longer repeatedly invalidate routes. Extract at most 256 grid nodes / approximately 3,600 world units plus the final cell; retain full map connectivity in the shared reverse field. The first line only merges collinear validated edges. One bounded local shortcut candidate is refined per update; abandon unfinished refinement on tile departure. Normal-mode optional sampling is at most three starts in the current room, with cached progress on return; low-power mode skips it. No separate searches are repeated for fast players. Route prefixes refresh after 900 units of displacement, with forward guidance checked against six synthetic jumps of up to several rooms.

Low-power budget targets: 1ms for unresolved player-priority search, 0.35ms for other field search, around 30 guidance updates/s; normal mode used 3ms/1ms at up to roughly 60/s. These are cooperative search-loop deadlines, not hard per-frame guarantees or measured CPU consumption. Individual native collision calls and geometry refreshes can exceed a search-loop target. Initial grid rasterization/clearance construction remains synchronous; it is reused unchanged afterward and persistent trap cycles do not rebuild it.

Savings that can be stated from code: normal optional room samples 36 -> 3 (about 92% fewer per sampled room); low-power extra samples are off; route rendering layers 2 -> 1 when lighter effects are effective. Long straight ribbon subdivisions are 20 instead of 10 units. On such spans, combining one layer and half the segments gives about 75% fewer route vertices than the previous full-effects rendering of the same span. Curves, cap geometry, map size and previous Reduced Effects usage change that ratio. GPU draw work still includes the entire game. No device watts, battery life, game FPS percentage or low-end frame-time claim has been measured.

Offline checks: preferences migration/cache checks, six-flag/six-slider panel layout and reset, rough-turn preservation, nonpublication of unfinished refinement, tile-departure cancellation, current-room-only sampling capped at three, six multi-room movement/teleport samples, and all hidden-menu pause policies. The real core routing and panel code ran against host/graphics doubles; this is not native game compilation.

Research: HPA* supports reducing search space via entrances/regions (https://webdocs.cs.ualberta.ca/~jonathan/publications/ai_publications/jogd.pdf). Shared destination fields avoid repeating a search for every new position (https://www.redblobgames.com/pathfinding/tower-defense/index.html). The original JPS assumes uniform-cost grids (https://ojs.aaai.org/index.php/AAAI/article/view/7994), unlike these weighted hazard and clearance costs. Transparent overdraw increases GPU fragment work (https://developer.android.com/topic/performance/rendering/overdraw).

## Quality update 0.2.13

Normal-mode optional samples increased from three to six per room (a 3-by-2 arrangement), still prepared only around the current player room and capped at one new sample per update. Relative to the original 36 this is about 83% fewer optional starts, rather than the earlier 92% figure. Low-power mode still skips these extra alternatives.

After local shortcut refinement, one corner per update receives a short quadratic arc. Only new arc segments need bounded collision/hazard checks: connectors are subsets of already validated straight segments. Normal mode uses eight samples; low-power mode uses four. Unsafe arcs keep the original corner. Finished curves are published once and retained in an eight-entry identity cache. Geometry/floor changes clear it. Rendered meshes remain reused for identical routes; smoothing does not run every render frame.

Offline regression checks verified curved samples, preserved endpoints, no early publication, reuse of cached results, obstacle/hazard fallback, disposal, six-per-room preparation, fast multi-room jumps and tile-departure cancellation. No low-end device power measurement or native rendered verification was performed.

## Moving quality update 0.2.14

Separate the navigation route from the drawable visual route. Arrows can use the rough route immediately, but jagged rough geometry is not sent to the renderer. Shortcut and corner work are interleaved, publishing immutable finished curved prefixes instead of waiting for the entire section. Prefix publication is limited to once per 100ms except the first prefix and final result. Straight two-point routes appear immediately. Tile-entry work starts from the current position when the shared field has that cell ready.

Refinement runs up to four bounded steps per update, stopping after a cooperative target of 0.5ms normally / 0.25ms in low-power mode. Each individual step remains bounded by its local candidate checks; these targets do not establish native game frame-time guarantees.

Coordinate-keyed validated corner results survive replacement of the route array, so overlapping route prefixes reuse their arcs. The extra cache is capped at 128 entries normally or 32 with low-power mode and clears on geometry/floor changes. The existing completed-route cache remains bounded separately. Offline tests cover rough-preview suppression, progressive prefix publication while full work remains, immutable visual data, straight-line immediacy, cross-array corner reuse, hazard/wall fallback, disposal, tile departure and multi-room jumps. Native in-game visual/performance verification remains required.

## Continuous handoff 0.2.15

Retain an existing nearby curved visual while replacement geometry is being refined. Recentring the navigation prefix no longer clears it prematurely, and if a new field cell is not ready the existing navigation prefix is retained. Partial replacement visuals require at least 600 units ahead of the current player cell, avoiding prefixes completely hidden by the 184-unit player-distance mask or quickly outrun before the next publication. Completed short routes can still publish normally near their destination. Teleports away from the old visual and geometry/floor changes still discard it. Continuity regression tests cover preserved handoff, tiny-prefix rejection, valid replacement, teleport and floor disposal; the previous movement, curve, cache and pause checks also pass. These remain offline checks, not rendered native verification.

## Drawable swap and closer start 0.2.16

Prepare replacement ribbons off-display, apply their visibility mask, and attach them before disposing the previous meshes. A replacement entirely outside the visible mask is rejected without replacing the currently displayed route. Rejected identical candidates retry only after player movement or a settings/route change, avoiding repeated unnecessary mesh preparation. Incomplete new prefixes no longer shorten a usable displayed line below its remaining coverage, capped at 2,300 units for the handoff test. This targets apparent fades/blinks caused by shortened replacement geometry, not a timed alpha animation (there was none in the route swap).

The line's head threshold changes from 184 to 34 world units, exactly 150 closer to the player. End-fade styling remains. This slightly increases visible line area; it does not add search nodes. Offline visibility-mask, continuity, curve, fast-movement and pause regressions pass; native rendering still needs verification.

Power estimates remain unmeasured. For illustration only: on a hypothetical 60-FPS laptop, reducing compass time from 1ms to 0.5ms per frame saves 0.5/16.67 = 3% of the total frame-time budget. It is not a claim that this mod has those timings, that FPS rises 3%, or that electrical power falls 3%. The strongest expected benefit is fewer route-preparation spikes while moving; normal idle operation after preparation may show little power difference. Curves and the closer line add some rendering work, while caching and bounded local computation remove repeated work.

## Distance adjustment 0.2.17

Set the shared line-head threshold to 135 world units at the user's request, replacing 34. Both replacement preflight and live visibility use this same constant.
