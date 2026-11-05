extends Node
## FactoryClock - the one fixed-rate simulation tick for machines (design/06-architecture.md A2).
##
## Every Building used to own a Timer. One shared tick instead gives: deterministic crafting (same inputs, same
## outputs, frame-rate independent), one place to apply power satisfaction / brownout, and throughput numbers
## that are exact multiples of TICK. Consumers connect to `tick` and advance their own state by `dt`.
##
## Runs in _physics_process so it shares the physics clock (and pauses with the tree).

signal tick(dt: float)

## 10 Hz. Recipe times are authored in seconds; at 0.1 s resolution a 2 s recipe is exactly 20 ticks.
const TICK := 0.1

## Total simulated seconds, for statistics and debugging.
var sim_time := 0.0
## Multiplier for tests and a future "fast forward"; 0 freezes every machine.
var speed := 1.0

var _accum := 0.0

func _physics_process(delta: float) -> void:
	_accum += delta * speed
	# Cap catch-up so a long hitch cannot run hundreds of ticks in one frame.
	var steps := 0
	while _accum >= TICK and steps < 10:
		_accum -= TICK
		steps += 1
		sim_time += TICK
		tick.emit(TICK)
	if steps == 10:
		_accum = 0.0

## Advance the simulation by `seconds` immediately (tests only).
func advance(seconds: float) -> void:
	var n := int(round(seconds / TICK))
	for i in n:
		sim_time += TICK
		tick.emit(TICK)
