class_name BaseController
extends Node
## Base de los controladores. Un controlador produce un RiderInput por frame.


func get_input(_delta: float) -> RiderInput:
	return RiderInput.new()
