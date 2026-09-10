extends Node
## Autoload: GameState
##
## Ports core/GameState.ts (GameStateMachine) — a stack-based state machine,
## not a flat variable. Every transition REPLACES the stack; PAUSED is the
## only state ever pushed/popped as an overlay on top of whatever was
## active before it. See GODOT_MIGRATION.md §2.

enum State {
	BOOT,
	MAIN_MENU,
	RUN_START,
	EXPLORATION,
	COMBAT,
	EVENT,
	SHOP,
	BOSS,
	VICTORY,
	DEFEAT,
	PAUSED,
}

signal changed(state: State, previous: State)

var current: State = State.BOOT:
	set(value):
		if value == current:
			return
		var previous := current
		current = value
		changed.emit(current, previous)

var _stack: Array[State] = [State.BOOT]

## Replaces the whole stack — the normal way to move between screens/phases.
func change_state(next: State) -> void:
	_stack = [next]
	current = next

## Pushes an overlay state (PAUSED) on top of whatever is currently active.
func push_state(next: State) -> void:
	_stack.push_back(next)
	current = next

## Pops the current overlay state, returning to whatever was under it.
func pop_state() -> void:
	if _stack.size() <= 1:
		push_error("GameState.pop_state called with nothing to pop back to")
		return
	_stack.pop_back()
	current = _stack.back()

func is_in(states: Array[State]) -> bool:
	return states.has(current)

## True while gameplay simulation should actually run. The Web build
## computed this ad hoc — `stateMachine.is(EXPLORATION, COMBAT, BOSS) &&
## !modalScreen` — with EVENT/SHOP declared but never actually entered
## (a confirmed gap, see GODOT_MIGRATION.md / README "GameState
## granularity"). Here EVENT and SHOP are real, exclusive states: entering
## one means simulation is paused for a modal interaction, same as PAUSED.
func is_simulating() -> bool:
	return is_in([State.EXPLORATION, State.COMBAT, State.BOSS])
