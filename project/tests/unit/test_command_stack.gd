extends GutTest
## Tests de core/model/commands: deshacer, rehacer, fusión y límite.


class Counter:
	extends RefCounted
	var value: int = 0


class AddCommand:
	extends MapCommand
	var amount: int = 0
	var refuse: bool = false

	func _init(n: int, refuse_apply: bool = false) -> void:
		amount = n
		refuse = refuse_apply

	func label_key() -> String:
		return "CMD_TEST_ADD"

	func apply(doc: Object) -> bool:
		if refuse:
			return false
		var c: Counter = doc as Counter
		c.value += amount
		return true

	func revert(doc: Object) -> void:
		var c: Counter = doc as Counter
		c.value -= amount

	func merge_with(next: MapCommand) -> bool:
		var other: AddCommand = next as AddCommand
		if other == null:
			return false
		amount += other.amount
		return true


func test_execute_undo_redo() -> void:
	var c: Counter = Counter.new()
	var s: CommandStack = CommandStack.new(c)
	assert_true(s.execute(AddCommand.new(5)))
	assert_true(s.execute(AddCommand.new(3)))
	assert_eq(c.value, 8)
	assert_true(s.undo())
	assert_eq(c.value, 5)
	assert_true(s.redo())
	assert_eq(c.value, 8)
	assert_true(s.undo())
	assert_true(s.undo())
	assert_eq(c.value, 0)
	assert_false(s.undo())
	assert_eq(s.redo_label_key(), "CMD_TEST_ADD")


func test_new_command_clears_redo() -> void:
	var c: Counter = Counter.new()
	var s: CommandStack = CommandStack.new(c)
	s.execute(AddCommand.new(1))
	s.undo()
	assert_true(s.can_redo())
	s.execute(AddCommand.new(2))
	assert_false(s.can_redo())
	assert_eq(c.value, 2)


func test_refused_command_changes_nothing() -> void:
	var c: Counter = Counter.new()
	var s: CommandStack = CommandStack.new(c)
	watch_signals(s)
	assert_false(s.execute(AddCommand.new(9, true)))
	assert_eq(c.value, 0)
	assert_false(s.can_undo())
	assert_signal_not_emitted(s, "changed")


func test_merge_makes_single_step() -> void:
	var c: Counter = Counter.new()
	var s: CommandStack = CommandStack.new(c)
	s.execute(AddCommand.new(1))
	s.execute(AddCommand.new(1), true)
	s.execute(AddCommand.new(1), true)
	assert_eq(c.value, 3)
	assert_eq(s.applied().size(), 1)
	s.undo()
	assert_eq(c.value, 0)


func test_limit_drops_oldest() -> void:
	var c: Counter = Counter.new()
	var s: CommandStack = CommandStack.new(c, 3)
	for i: int in 5:
		s.execute(AddCommand.new(1))
	assert_eq(s.applied().size(), 3)
	while s.undo():
		pass
	assert_eq(c.value, 2)
