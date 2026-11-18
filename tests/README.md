# Offline regression checks

Run `python tests/run.py --haxe /absolute/path/to/haxe`.

These fixtures use small host/OpenFL doubles. They verify settings migration, seven-control layout, an original v0.2.8 curve oracle, collision/hazard sampling, cooperative jobs, earlier initial guidance with identical completed weighted costs, on-demand edge checks and fallback, route cache limits/reuse, bounded render windows, visibility masks, pause classification, and local 3/5/8-second JSONL measurements. They do not compile or render the native DRH client and cannot establish an FPS or CPU saving.

Test fixtures are excluded from release ZIPs.


Additional checks cover sliced collision/raster/clearance equivalence with the previous grid implementation, native tint matrix equivalence, hero+5 compass tangents, frame-budget calibration, first-real-work measurement anchoring, staged drawing load, countdown and stress-mesh disposal, plus result dialog Yes/No behavior. The final entry type check uses `entry_host` adapters and includes the real Main/Compass/UI sources. None of these doubles measures native GPU performance or proves hxScript/native compilation.
