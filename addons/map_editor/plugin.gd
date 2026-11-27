@tool
extends EditorPlugin
## Map editor plugin: the «Карта» main screen (MapView) — the open map with a
## game-like camera, the object palette and mouse editing.

var view: Control


func _enter_tree() -> void:
	view = preload("res://addons/map_editor/map_view.gd").new()
	view.plugin = self
	view.name = "MapView"
	EditorInterface.get_editor_main_screen().add_child(view)
	view.visible = false
	scene_changed.connect(_on_scene_changed)
	if OS.get_environment("MAPVIEW_SELFTEST") == "1":
		(func() -> void:
			await get_tree().create_timer(3.0).timeout
			EditorInterface.set_main_screen_editor("Карта")
			view.on_scene_changed()
			view.selftest()).call_deferred()


func _exit_tree() -> void:
	if view:
		view.queue_free()
		view = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Карта"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridMap", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if view:
		view.visible = visible


## Opening a map switches to the «Карта» screen.
func _on_scene_changed(root: Node) -> void:
	if root is MapScene:
		EditorInterface.set_main_screen_editor("Карта")
		if view:
			view.on_scene_changed()
