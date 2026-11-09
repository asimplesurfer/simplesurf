class_name RiderStateMachine
extends Node
## Máquina de estados del Rider. Cada hijo que sea RiderState es un estado,
## y su nombre en minúsculas es su id (Riding -> &"riding").

signal state_changed(new_state: StringName, previous: StringName)

@export var initial_state: StringName = &"riding"

var states: Dictionary = {}
var current: RiderState
var current_name: StringName = &""


func setup(rider: Rider) -> void:
	for child in get_children():
		if child is RiderState:
			child.rider = rider
			child.state_machine = self
			states[StringName(String(child.name).to_lower())] = child
	transition_to(initial_state)


func transition_to(state_name: StringName) -> void:
	if not states.has(state_name):
		push_error("Estado desconocido: %s" % state_name)
		return
	var previous := current_name
	if current:
		current.exit()
	current = states[state_name]
	current_name = state_name
	current.enter(previous)
	state_changed.emit(state_name, previous)


func update(delta: float, input: RiderInput) -> void:
	if current:
		current.update(delta, input)
