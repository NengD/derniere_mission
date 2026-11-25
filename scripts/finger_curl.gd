class_name FingerCurl
extends SkeletonModifier3D
## Referme les doigts d'une main (ou des deux) par-dessus l'animation : les bibliothèques libres
## tiennent le pistolet main ouverte. `curl` : 0 = main ouverte, 1 = poing serré.

@export var curl := 1.0
@export var sides := PackedStringArray(["r", "l"])
@export var axis := Vector3(1, 0, 0)
@export var thumb_axis := Vector3(0, 0, 1)

const FINGERS := ["index", "middle", "ring", "pinky"]
const ANGLES := {"01": 55.0, "02": 75.0, "03": 50.0}
const THUMB := {"01": 10.0, "02": 25.0, "03": 30.0}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for s in sides:
		var sign := 1.0 if s == "r" else -1.0
		for f in FINGERS:
			for k in ANGLES:
				var i := sk.find_bone("%s_%s_%s" % [f, k, s])
				if i >= 0:
					var q := sk.get_bone_pose_rotation(i)
					sk.set_bone_pose_rotation(i, q * Quaternion(axis, deg_to_rad(ANGLES[k] * curl)))
		for k in THUMB:
			var i := sk.find_bone("thumb_%s_%s" % [k, s])
			if i >= 0:
				var q := sk.get_bone_pose_rotation(i)
				sk.set_bone_pose_rotation(i, q * Quaternion(thumb_axis, deg_to_rad(THUMB[k] * curl * sign)))
