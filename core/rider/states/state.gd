class_name RiderState
extends Node
## Base de los estados del Rider. Los estados no conocen audio ni efectos:
## emiten señales del Rider y otros nodos reaccionan.

var rider: Rider
var state_machine: RiderStateMachine


func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float, _input: RiderInput) -> void:
	pass
