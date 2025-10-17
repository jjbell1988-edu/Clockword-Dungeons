@tool
extends EditorScript

const TILESET_PATH := "res://tilesets/Overworld.tres"
const OVERWORLD_SCRIPT_PATH := "res://scripts/Overworld.gd"

func _run() -> void:
    var overworld_script := load(OVERWORLD_SCRIPT_PATH)
    if overworld_script == null:
        push_error("Unable to load Overworld script at %s" % OVERWORLD_SCRIPT_PATH)
        return

    var overworld := overworld_script.new()
    if overworld == null:
        push_error("Unable to instantiate Overworld script.")
        return

    var tile_set := overworld._create_tileset()
    if tile_set == null:
        push_error("Failed to build TileSet from Overworld script.")
        return

    overworld._save_tileset_to_disk(tile_set)

    if ResourceLoader.exists(TILESET_PATH):
        push_info("Saved overworld TileSet to %s" % TILESET_PATH)
    else:
        push_error("TileSet save did not complete. Check the editor output for warnings.")
