extends SceneTree


func _init() -> void:
	var ok := true

	# move_time: base 1.4 m/s, AGI 1, 70 kg → 10m takes ~7.14s
	var mt := TimeCalculator.move_time(10.0, 1, 70.0)
	ok = _check("move 10m AGI1 70kg ≈ 7.14s", absf(mt - 7.142857) < 0.01, ok)

	# Higher AGI → faster
	var mt2 := TimeCalculator.move_time(10.0, 3, 70.0)
	ok = _check("move 10m AGI3 faster than AGI1", mt2 < mt, ok)

	# Heavier → slower
	var mt3 := TimeCalculator.move_time(10.0, 1, 140.0)
	ok = _check("move 10m 140kg slower than 70kg", mt3 > mt, ok)

	# hack_time CCTV base=4.0, INT 1 → 4.0s
	var ht := TimeCalculator.hack_time("cctv", 1)
	ok = _check("hack cctv INT1 = 4.0s", absf(ht - 4.0) < 0.001, ok)

	# hack_time INT 2 → 2.0s
	var ht2 := TimeCalculator.hack_time("cctv", 2)
	ok = _check("hack cctv INT2 = 2.0s", absf(ht2 - 2.0) < 0.001, ok)

	# pick_lock complexity 1, INT 1 → 6.0s
	var pl := TimeCalculator.pick_lock_time(1, 1)
	ok = _check("pick_lock c1 INT1 = 6.0s", absf(pl - 6.0) < 0.001, ok)

	# pick_lock complexity 2, INT 2 → 6.0s
	var pl2 := TimeCalculator.pick_lock_time(2, 2)
	ok = _check("pick_lock c2 INT2 = 6.0s", absf(pl2 - 6.0) < 0.001, ok)

	# takedown STR 1 → 3.0s
	var td := TimeCalculator.takedown_time(1)
	ok = _check("takedown STR1 = 3.0s", absf(td - 3.0) < 0.001, ok)

	# takedown STR 3 → 1.0s
	var td3 := TimeCalculator.takedown_time(3)
	ok = _check("takedown STR3 = 1.0s", absf(td3 - 1.0) < 0.001, ok)

	# struggle duration STR 1, 1 guard → 3.5s
	var sd := TimeCalculator.struggle_duration(1, 1)
	ok = _check("struggle STR1 1guard = 3.5s", absf(sd - 3.5) < 0.001, ok)

	# struggle duration STR 1, 2 guards → 1.75s
	var sd2 := TimeCalculator.struggle_duration(1, 2)
	ok = _check("struggle STR1 2guards = 1.75s", absf(sd2 - 1.75) < 0.001, ok)

	quit(0 if ok else 1)


func _check(label: String, condition: bool, ok: bool) -> bool:
	if condition:
		print("  PASS  %s" % label)
	else:
		print("  FAIL  %s" % label)
	return ok and condition
