class_name Prof
extends RefCounted
## Lightweight CPU profiler for game systems (`-- --profile`). Wrapped hot
## functions add their wall time per tag; AutoTest prints the totals per
## window. Off by default: one bool check per call.

static var on := false
static var acc := {}
static var calls := {}
static var peak := {}


static func add(tag: String, t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	acc[tag] = acc.get(tag, 0) + dt
	if dt > int(peak.get(tag, 0)):
		peak[tag] = dt
	calls[tag] = calls.get(tag, 0) + 1


## Returns lines "tag ms/frame (calls/frame)" sorted by cost, then resets.
static func report(frames: int) -> String:
	var keys := acc.keys()
	keys.sort_custom(func(a, b): return acc[a] > acc[b])
	var out := PackedStringArray()
	var total := 0
	for k in keys:
		total += int(acc[k])
	for k in keys:
		out.append("%s %.2f ms (%d)" % [k, float(acc[k]) / 1000.0 / frames, int(calls[k] / frames)])
	var pk := peak.keys()
	pk.sort_custom(func(a, b): return peak[a] > peak[b])
	var ptxt := PackedStringArray()
	for i in mini(4, pk.size()):
		ptxt.append("%s %.1f" % [pk[i], float(peak[pk[i]]) / 1000.0])
	out.append("| PEAK ms: " + ", ".join(ptxt))
	acc.clear()
	calls.clear()
	peak.clear()
	return "sum %.2f ms/frame | " % (float(total) / 1000.0 / frames) + ", ".join(out)
