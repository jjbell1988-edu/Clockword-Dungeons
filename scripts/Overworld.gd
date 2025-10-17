extends Node2D

const MAP_SIZE := Vector2i(200, 200)
const CELL_SIZE := 32
const MOVE_SPEED := 300.0

enum TerrainType { WATER, GRASS, FOREST, MOUNTAIN }

const TERRAIN_DEFINITIONS := {
    TerrainType.WATER: {"color": Color(0.1, 0.3, 0.8), "name": "Water"},
    TerrainType.GRASS: {"color": Color(0.2, 0.6, 0.2), "name": "Grass"},
    TerrainType.FOREST: {"color": Color(0.1, 0.45, 0.12), "name": "Forest"},
    TerrainType.MOUNTAIN: {"color": Color(0.45, 0.42, 0.35), "name": "Mountain"}
}

@onready var tile_map: TileMap = $TileMap
@onready var player: Node2D = $Player
@onready var player_sprite: Sprite2D = $Player/Sprite2D
@onready var camera: Camera2D = $Player/Camera2D

var terrain_grid: Array = []
var tile_sources: Dictionary = {}
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

var current_tile := Vector2i()
var target_tile := Vector2i()

func _ready() -> void:
    rng.randomize()
    _configure_noise()
    _setup_tilemap()
    _create_player_visual()
    _generate_map()
    current_tile = Vector2i(MAP_SIZE.x / 2, MAP_SIZE.y / 2)
    target_tile = current_tile
    _snap_player_to_tile(current_tile)
    _configure_camera_limits()

func _process(_delta: float) -> void:
    _handle_keyboard_input()

func _physics_process(delta: float) -> void:
    var target_position := _tile_to_world(target_tile)
    if player.global_position.distance_to(target_position) < 1.0:
        _snap_player_to_tile(target_tile)
    else:
        player.global_position = player.global_position.move_toward(target_position, MOVE_SPEED * delta)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.LEFT:
        var mouse_pos := (event as InputEventMouseButton).position
        var local_pos := tile_map.to_local(mouse_pos)
        var clicked_tile := tile_map.local_to_map(local_pos)
        if _tile_in_bounds(clicked_tile) and _terrain_is_walkable(terrain_grid[clicked_tile.x][clicked_tile.y]):
            target_tile = clicked_tile

func _handle_keyboard_input() -> void:
    var direction := Vector2i.ZERO
    if Input.is_action_just_pressed("ui_left"):
        direction.x = -1
    elif Input.is_action_just_pressed("ui_right"):
        direction.x = 1
    elif Input.is_action_just_pressed("ui_up"):
        direction.y = -1
    elif Input.is_action_just_pressed("ui_down"):
        direction.y = 1

    if direction != Vector2i.ZERO:
        _try_move(direction)

func _try_move(direction: Vector2i) -> void:
    var candidate := target_tile + direction
    if _tile_in_bounds(candidate) and _terrain_is_walkable(terrain_grid[candidate.x][candidate.y]):
        target_tile = candidate

func _snap_player_to_tile(tile: Vector2i) -> void:
    var world_pos := _tile_to_world(tile)
    player.global_position = world_pos
    current_tile = tile

func _tile_to_world(tile: Vector2i) -> Vector2:
    var local := tile_map.map_to_local(tile)
    return tile_map.to_global(local)

func _terrain_is_walkable(terrain_type: int) -> bool:
    return terrain_type != TerrainType.WATER

func _tile_in_bounds(tile: Vector2i) -> bool:
    return tile.x >= 0 and tile.y >= 0 and tile.x < MAP_SIZE.x and tile.y < MAP_SIZE.y

func _configure_noise() -> void:
    noise.seed = rng.randi()
    noise.frequency = 0.01
    noise.fractal_octaves = 4
    noise.fractal_lacunarity = 2.0
    noise.fractal_gain = 0.5

func _setup_tilemap() -> void:
    var tile_set := TileSet.new()
    tile_set.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)

    for terrain_type in TERRAIN_DEFINITIONS.keys():
        var data := TERRAIN_DEFINITIONS[terrain_type]
        var atlas_source := TileSetAtlasSource.new()
        atlas_source.resource_name = data["name"]
        atlas_source.texture = _make_tile_texture(terrain_type, data["color"])
        atlas_source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
        atlas_source.create_tile(Vector2i.ZERO)
        var source_id := tile_set.get_next_source_id()
        tile_set.add_source(atlas_source, source_id)
        tile_sources[terrain_type] = source_id

    tile_map.tile_set = tile_set

func _generate_map() -> void:
    terrain_grid.resize(MAP_SIZE.x)
    for x in range(MAP_SIZE.x):
        terrain_grid[x] = []
        terrain_grid[x].resize(MAP_SIZE.y)

    for x in range(MAP_SIZE.x):
        for y in range(MAP_SIZE.y):
            var terrain_type := _pick_terrain_for_tile(x, y)
            terrain_grid[x][y] = terrain_type
            tile_map.set_cell(0, Vector2i(x, y), tile_sources[terrain_type])

func _pick_terrain_for_tile(x: int, y: int) -> int:
    var height := noise.get_noise_2d(float(x), float(y))
    if height < -0.25:
        return TerrainType.WATER
    elif height < 0.2:
        return TerrainType.GRASS
    elif height < 0.45:
        return TerrainType.FOREST
    else:
        return TerrainType.MOUNTAIN

func _make_tile_texture(terrain_type: int, base_color: Color) -> Texture2D:
    var image := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(base_color)

    match terrain_type:
        TerrainType.WATER:
            var wave_color := base_color.lightened(0.25)
            for y in range(4, CELL_SIZE, 6):
                for x in range(CELL_SIZE):
                    if (x + y) % 5 < 2:
                        image.set_pixel(x, y, wave_color)
        TerrainType.GRASS:
            var blade_color := base_color.lightened(0.2)
            for _i in range(CELL_SIZE * 2):
                var px := rng.randi_range(0, CELL_SIZE - 1)
                var py := rng.randi_range(0, CELL_SIZE - 1)
                image.set_pixel(px, py, blade_color)
        TerrainType.FOREST:
            var canopy_color := base_color.darkened(0.1)
            var trunk_color := Color(0.2, 0.15, 0.1)
            var centers := [
                Vector2i(CELL_SIZE // 3, CELL_SIZE // 3),
                Vector2i(CELL_SIZE * 2 // 3, CELL_SIZE * 2 // 3)
            ]
            for center in centers:
                for y_offset in range(-4, 5):
                    for x_offset in range(-4, 5):
                        var pos := center + Vector2i(x_offset, y_offset)
                        if pos.x >= 0 and pos.x < CELL_SIZE and pos.y >= 0 and pos.y < CELL_SIZE:
                            if x_offset * x_offset + y_offset * y_offset <= 12:
                                image.set_pixelv(pos, canopy_color)
                var trunk_pos := Vector2i(center.x, min(center.y + 3, CELL_SIZE - 1))
                image.set_pixelv(trunk_pos, trunk_color)
        TerrainType.MOUNTAIN:
            var ridge_color := base_color.lightened(0.3)
            var shadow_color := base_color.darkened(0.2)
            for y in range(CELL_SIZE):
                var ratio := float(y) / float(CELL_SIZE)
                var half_width := int(ratio * float(CELL_SIZE) * 0.5)
                var start_x := clamp((CELL_SIZE // 2) - half_width, 0, CELL_SIZE - 1)
                var end_x := clamp((CELL_SIZE // 2) + half_width, 0, CELL_SIZE - 1)
                for x in range(start_x, end_x + 1):
                    image.set_pixel(x, y, ridge_color)
            for y in range(CELL_SIZE // 2, CELL_SIZE):
                for x in range(CELL_SIZE // 2, CELL_SIZE):
                    image.set_pixel(x, y, shadow_color)

    return ImageTexture.create_from_image(image)

func _create_player_visual() -> void:
    var image := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 0))

    var center := Vector2i(CELL_SIZE // 2, CELL_SIZE // 2)
    var radius := CELL_SIZE // 3
    var body_color := Color(0.95, 0.88, 0.2)
    var border_color := Color(0.2, 0.2, 0.2, 0.8)

    for y in range(-radius - 1, radius + 2):
        for x in range(-radius - 1, radius + 2):
            var pos := center + Vector2i(x, y)
            if pos.x >= 0 and pos.x < CELL_SIZE and pos.y >= 0 and pos.y < CELL_SIZE:
                var dist_sq := x * x + y * y
                if dist_sq <= radius * radius:
                    image.set_pixelv(pos, body_color)
                elif dist_sq <= (radius + 1) * (radius + 1):
                    image.set_pixelv(pos, border_color)

    player_sprite.texture = ImageTexture.create_from_image(image)
    player_sprite.centered = true
    player_sprite.scale = Vector2(0.5, 0.5)

func _configure_camera_limits() -> void:
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = MAP_SIZE.x * CELL_SIZE
    camera.limit_bottom = MAP_SIZE.y * CELL_SIZE
    camera.position = Vector2.ZERO
    camera.zoom = Vector2(1.5, 1.5)
