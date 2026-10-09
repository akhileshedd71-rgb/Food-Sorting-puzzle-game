extends SceneTree
## Animation lifecycle and reduced-motion regressions. Does not touch saves.

var checks: int = 0
var failures: Array[String] = []
var host: Control


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	host = Control.new()
	host.size = Vector2(720, 1600)
	root.add_child(host)
	await process_frame
	await test_icons()
	await test_control_effects()
	await test_reduced_motion()
	await test_particle_lifetimes()
	await test_owner_lifetime()
	host.queue_free()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MOTION TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_icons() -> void:
	var coin := CoinIcon.new()
	var mark := BrandMark.new()
	host.add_child(coin)
	host.add_child(mark)
	coin.size = Vector2(48, 48)
	mark.size = Vector2(180, 180)
	check(coin.custom_minimum_size == Vector2(48, 48), "coin has a useful default size")
	check(mark.custom_minimum_size == Vector2(180, 180), "brand mark has a useful default size")
	check(coin.mouse_filter == Control.MOUSE_FILTER_IGNORE, "coin never steals input")
	check(mark.mouse_filter == Control.MOUSE_FILTER_IGNORE, "brand mark never steals input")
	coin.size = Vector2(96, 72)
	mark.size = Vector2(240, 180)
	await process_frame
	coin.queue_free()
	mark.queue_free()
	await process_frame


func test_control_effects() -> void:
	var card := Control.new()
	card.position = Vector2(70, 90)
	card.size = Vector2(200, 140)
	card.scale = Vector2(1.2, 0.85)
	card.modulate = Color(0.9, 0.8, 0.7, 0.82)
	card.pivot_offset = Vector2(7, 9)
	host.add_child(card)
	var resting_position := card.position
	var resting_scale := card.scale
	var resting_color := card.modulate
	var resting_pivot := card.pivot_offset
	var entrance := GardenMotion.enter(card)
	check(entrance != null and entrance.is_valid(), "entrance returns a bound tween")
	check(is_zero_approx(card.modulate.a), "entrance begins transparent")
	check(card.position == resting_position, "entrance leaves layout position untouched")
	await create_timer(0.06).timeout
	var press := GardenMotion.press(card)
	check(not entrance.is_valid(), "new control effect kills the stale tween")
	await press.finished
	check(card.scale.is_equal_approx(resting_scale), "press restores original nonuniform scale")
	check(card.modulate.is_equal_approx(resting_color), "superseding entrance restores intended opacity and tint")
	check(card.position == resting_position, "press leaves layout position untouched")
	check(card.pivot_offset == resting_pivot, "completed effect restores original pivot")
	var pulse := GardenMotion.pulse(card)
	await pulse.finished
	check(card.scale.is_equal_approx(resting_scale), "finite hint pulse returns to its resting scale")
	check(card.modulate.is_equal_approx(resting_color), "hint pulse preserves color and opacity")
	var repeated: Tween
	for i in range(40):
		repeated = GardenMotion.press(card)
	await process_frame
	var active_count: int = 0
	for candidate in get_processed_tweens():
		if candidate.is_valid() and candidate.is_running():
			active_count += 1
	check(active_count <= 1, "forty rapid presses keep only one active tween")
	await repeated.finished
	check(card.scale.is_equal_approx(resting_scale), "rapid press replacement cannot leave scale drift")
	card.queue_free()
	await process_frame


func test_reduced_motion() -> void:
	var card := Control.new()
	card.size = Vector2(100, 100)
	card.scale = Vector2(0.8, 0.8)
	card.modulate = Color(0.8, 0.9, 1, 0.7)
	host.add_child(card)
	var original_scale := card.scale
	var original_color := card.modulate
	var pending := GardenMotion.enter(card)
	check(GardenMotion.enter(card, true) == null, "reduced entrance returns no tween")
	check(not pending.is_valid(), "reduced entrance cancels pending motion")
	check(card.scale == original_scale and card.modulate == original_color, "reduced entrance shows stable final appearance")
	check(GardenMotion.press(card, true) == null, "reduced press stays static")
	check(GardenMotion.pulse(card, true) == null, "reduced hint stays static")
	check(card.scale == original_scale and card.modulate == original_color, "reduced effects preserve caller styling")
	card.queue_free()
	await process_frame
	var detached := Control.new()
	check(GardenMotion.enter(detached) == null, "detached controls do not create invalid tweens")
	detached.free()
	check(GardenMotion.enter(null) == null, "missing controls are safe to ignore")


func test_particle_lifetimes() -> void:
	var baseline := host.get_child_count()
	GardenMotion.coin_burst(host, Vector2(240, 400), 0)
	GardenMotion.coin_burst(host, Vector2(240, 400), -30)
	GardenMotion.match_burst(host, Vector2(240, 400), true)
	check(host.get_child_count() == baseline, "zero rewards and reduced matches create no decorative particles")
	for i in range(40):
		GardenMotion.coin_burst(host, Vector2(240, 400), 30)
		GardenMotion.match_burst(host, Vector2(240, 400))
	check(host.get_child_count() <= baseline + 8, "same-frame particle spam is bounded to eight layers")
	for child in host.get_children():
		if child is Control:
			check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "burst layer never intercepts gestures")
	await create_timer(1.05).timeout
	await process_frame
	check(host.get_child_count() == baseline, "all animated burst nodes clean themselves up")
	check(get_processed_tweens().is_empty(), "finished bursts leave no running tweens")
	GardenMotion.coin_burst(host, Vector2(240, 400), 30, true)
	var layer: Control = host.get_child(host.get_child_count() - 1)
	var initial_position := layer.position
	var reward: Label = layer.get_child(0)
	var initial_label_position := reward.position
	check(reward.text == "+30 Chef Coins", "reward feedback states the actual granted amount")
	await create_timer(0.10).timeout
	check(layer.position == initial_position and reward.position == initial_label_position, "reduced coin feedback stays still")
	check(get_processed_tweens().is_empty(), "reduced feedback starts no animation tween")
	await create_timer(1.15).timeout
	await process_frame
	check(host.get_child_count() == baseline, "reduced coin feedback has a finite lifetime")
	GardenMotion.coin_burst(host, Vector2.ZERO, 100)
	GardenMotion.match_burst(host, Vector2.ZERO)
	GardenMotion.cancel_all(host)
	check(host.get_child_count() == baseline, "screen-change cancellation immediately removes burst layers")
	await process_frame


func test_owner_lifetime() -> void:
	var card := Control.new()
	host.add_child(card)
	var reference: WeakRef = weakref(card)
	var tween := GardenMotion.pulse(card)
	GardenMotion.coin_burst(card, Vector2.ZERO, 30)
	GardenMotion.coin_burst(card, Vector2.ZERO, 100, true)
	card.queue_free()
	await process_frame
	await process_frame
	check(reference.get_ref() == null, "freeing screen owner also frees animation controls")
	check(not tween.is_valid(), "owner destruction invalidates its bound tween")
	await create_timer(1.15).timeout
	check(get_processed_tweens().is_empty(), "late reduced-motion cleanup safely ignores a freed owner")
	GardenMotion.cancel_all(null)
	GardenMotion.coin_burst(null, Vector2.ZERO, 30)
	GardenMotion.match_burst(null, Vector2.ZERO)
	check(true, "missing owners are safe for screen-transition callbacks")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
