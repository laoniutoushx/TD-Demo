extends Resource
## Editable lighting data; no scene construction or rendering code.
@export var sun_color:Color=Color.WHITE
@export_range(0.0,5.0) var sun_energy:float=1.1
@export var sun_rotation:Vector3=Vector3(-42,-35,0)
@export var environment:Environment
