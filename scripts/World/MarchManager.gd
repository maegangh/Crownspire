# ==============================================================================
# Crownspire MMO - March Manager Script
# Godot 4.6 / GDScript 2.0 Real-time campaign/march outbound & inbound logistics
# ==============================================================================

extends Node2D

# Signal sent when a march completes gathering or battle action
signal march_action_completed(target: Node2D, success: bool)
signal march_returned_home()

@export_category("Assets")
@export var march_icon_scene: PackedScene # PackedScene containing Sprite2D/AnimatedSprite2D representing a troop march

# Represents an active march sequence
class MarchData:
	var instance: Node2D
	var start_position: Vector2
	var target_node: Node2D
	var target_position: Vector2
	var speed: float
	var action_duration: float
	var current_state: String = "OUTBOUND" # OUTBOUND, ACTION, RETURN
	var timer: float = 0.0

var _active_marches: Array[MarchData] = []

func _process(delta: float) -> void:
	var completed_marches: Array[MarchData] = []
	
	for march in _active_marches:
		# Guard against targets getting deleted by other actions while in transit
		if not is_instance_valid(march.target_node) and march.current_state == "OUTBOUND":
			march.current_state = "RETURN"
			
		match march.current_state:
			"OUTBOUND":
				var current_pos = march.instance.global_position
				var dir = (march.target_position - current_pos).normalized()
				var distance = current_pos.distance_to(march.target_position)
				var move_step = march.speed * delta
				
				# Rotate to face target position smoothly
				if dir.length() > 0.1:
					march.instance.rotation = lerp_angle(march.instance.rotation, dir.angle(), 12.0 * delta)
				
				if move_step >= distance:
					march.instance.global_position = march.target_position
					march.current_state = "ACTION"
					march.timer = 0.0
					_on_march_reach_target(march)
				else:
					march.instance.global_position += dir * move_step
					
			"ACTION":
				march.timer += delta
				# Visual animation pulsing when active
				march.instance.scale = Vector2.ONE * (1.0 + 0.1 * sin(march.timer * 8.0))
				
				if march.timer >= march.action_duration:
					march.instance.scale = Vector2.ONE
					march.current_state = "RETURN"
					_on_march_action_finished(march)
					
			"RETURN":
				var current_pos = march.instance.global_position
				var dir = (march.start_position - current_pos).normalized()
				var distance = current_pos.distance_to(march.start_position)
				var move_step = march.speed * delta
				
				if dir.length() > 0.1:
					march.instance.rotation = lerp_angle(march.instance.rotation, dir.angle(), 12.0 * delta)
					
				if move_step >= distance:
					march.instance.global_position = march.start_position
					completed_marches.append(march)
				else:
					march.instance.global_position += dir * move_step
					
	for march in completed_marches:
		_cleanup_march(march)

# Dispatches a new march sequence across map coordinate pathways
func dispatch_march(from_pos: Vector2, target: Node2D, speed: float = 300.0, action_dur: float = 2.5) -> void:
	if not march_icon_scene:
		push_error("MarchManager: march_icon_scene asset is NULL!")
		return
		
	var icon_inst = march_icon_scene.instantiate() as Node2D
	icon_inst.global_position = from_pos
	add_child(icon_inst)
	
	var data = MarchData.new()
	data.instance = icon_inst
	data.start_position = from_pos
	data.target_node = target
	data.target_position = target.global_position
	data.speed = speed
	data.action_duration = action_dur
	data.current_state = "OUTBOUND"
	
	_active_marches.append(data)
	print("[MarchManager] Dispatched march toward target at position: ", data.target_position)

func _on_march_reach_target(march: MarchData) -> void:
	print("[MarchManager] March reached destination. Executing task on target: ", march.target_node.name)

func _on_march_action_finished(march: MarchData) -> void:
	print("[MarchManager] Task completed on target. Commencing return march.")
	
	# Emit complete metrics
	var success = true
	march_action_completed.emit(march.target_node, success)

func _cleanup_march(march: MarchData) -> void:
	_active_marches.erase(march)
	if is_instance_valid(march.instance):
		march.instance.queue_free()
	march_returned_home.emit()
	print("[MarchManager] March returned safely to stronghold.")
