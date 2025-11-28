extends StaticBody2D

@onready var damage_receiver := $DamageReceiver

func _ready() -> void:
	damage_receiver.damage_received.connect(on_damage_receive.bind())
	
	
func on_damage_receive(damage:int):
	
	queue_free()
