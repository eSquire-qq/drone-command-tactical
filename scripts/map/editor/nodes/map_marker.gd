@tool
class_name MapMarker
extends MapNode
## Службова точка місії: де заходять наші, куди відходить противник тощо.

## Яка точка.
## player_entry — в'їзд техніки (напрям — −Z вузла); foot_spawn — поява піхоти; dismount — точка висадки (можна кілька);
## medevac_entry — в'їзд евакуації; rally_point — збір; enemy_retreat — куди відходить противник;
## camera_start — початок камери; photo_center — центр знімка для брифінгу; enemy_fallback — загальний рубіж відходу противника;
## deploy_option — район висадки, який гравець може обрати на брифінгу (назва — у «Підпис»;
## точки висадки стають уздовж осі X вузла — повертайте вузол уздовж дороги).
@export_enum("player_entry", "foot_spawn", "dismount", "medevac_entry", "rally_point", "enemy_retreat", "camera_start", "photo_center", "enemy_fallback", "deploy_option") var kind: String = "player_entry":
	set(v):
		kind = v
		_touch()
## Назва району висадки (лише для deploy_option).
@export var label: String = "":
	set(v):
		label = v
		_touch()
## Пояснення для гравця (лише для deploy_option).
@export_multiline var desc: String = ""


const NAMES := {"player_entry": "Вʼїзд техніки", "foot_spawn": "Поява піхоти", "dismount": "Висадка", "medevac_entry": "Вʼїзд евакуації",
	"rally_point": "Збір", "enemy_retreat": "Відхід противника", "camera_start": "Камера", "photo_center": "Центр знімка", "enemy_fallback": "Рубіж відходу",
	"deploy_option": "Район висадки"}


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	var txt: String = NAMES.get(kind, kind)
	if kind == "deploy_option" and label != "":
		txt += ": " + label
	return {"mesh": cyl(0.6, 3.0), "color": Color(0.3, 0.7, 1.0) if kind in ["player_entry", "foot_spawn", "dismount", "medevac_entry", "rally_point", "camera_start", "deploy_option"] else Color(1.0, 0.4, 0.3) if kind != "photo_center" else Color(1, 1, 0.5), "y": 1.5, "text": txt}
