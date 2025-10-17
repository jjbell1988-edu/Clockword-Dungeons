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
const TERRAIN_VARIANTS := {
    TerrainType.WATER: 4,
    TerrainType.GRASS: 4,
    TerrainType.FOREST: 3,
    TerrainType.MOUNTAIN: 3
}

@onready var tile_map: TileMap = $TileMap
@onready var player: Node2D = $Player
@onready var player_sprite: Sprite2D = $Player/Sprite2D
@onready var camera: Camera2D = $Player/Camera2D

var terrain_grid: Array = []
var tile_sources: Dictionary = {}
var generated_tile_set: TileSet
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

var current_tile := Vector2i()
var target_tile := Vector2i()
var character_marker: Sprite2D

func _ready() -> void:
    rng.randomize()
    _configure_noise()
    _setup_tilemap()
    _create_player_visual()
    _generate_map()
    current_tile = Vector2i(MAP_SIZE.x / 2, MAP_SIZE.y / 2)
    target_tile = current_tile
    _snap_player_to_tile(current_tile)
    _create_character_marker()
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
    _update_character_marker(tile)

func _tile_to_world(tile: Vector2i) -> Vector2:
    var local := tile_map.map_to_local(tile) + Vector2(float(CELL_SIZE) * 0.5, float(CELL_SIZE) * 0.5)
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
    generated_tile_set = TileSet.new()
    generated_tile_set.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)

    for terrain_type in TERRAIN_DEFINITIONS.keys():
        var data := TERRAIN_DEFINITIONS[terrain_type]
        tile_sources[terrain_type] = []
        var variant_count := TERRAIN_VARIANTS.get(terrain_type, 1)
        for variant_index in range(variant_count):
            var atlas_source := TileSetAtlasSource.new()
            atlas_source.resource_name = "%s_%02d" % [data["name"], variant_index + 1]
            atlas_source.texture = _make_tile_texture(terrain_type, data["color"], variant_index)
            atlas_source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
            atlas_source.create_tile(Vector2i.ZERO)
            var source_id := generated_tile_set.get_next_source_id()
            generated_tile_set.add_source(atlas_source, source_id)
            tile_sources[terrain_type].append(source_id)

    tile_map.tile_set = generated_tile_set
    tile_map.set_layer_enabled(0, true)

func _generate_map() -> void:
    tile_map.clear()
    terrain_grid.resize(MAP_SIZE.x)
    for x in range(MAP_SIZE.x):
        terrain_grid[x] = []
        terrain_grid[x].resize(MAP_SIZE.y)

    for x in range(MAP_SIZE.x):
        for y in range(MAP_SIZE.y):
            var terrain_type := _pick_terrain_for_tile(x, y)
            terrain_grid[x][y] = terrain_type
            var variants: Array = tile_sources[terrain_type]
            var chosen_source := variants[rng.randi_range(0, variants.size() - 1)]
            tile_map.set_cell(0, Vector2i(x, y), chosen_source, Vector2i.ZERO)

    tile_map.notify_runtime_tile_data_update()

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

func _make_tile_texture(terrain_type: int, base_color: Color, variant_index: int) -> Texture2D:
    var image := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(base_color)
    var rng_local := RandomNumberGenerator.new()
    rng_local.seed = rng.randi()
    image.lock()

    match terrain_type:
        TerrainType.WATER:
            var deep_color := base_color.darkened(0.2)
            var highlight_color := base_color.lightened(0.35)
            for y in range(CELL_SIZE):
                var lerp_factor := float(y) / float(CELL_SIZE - 1)
                var row_color := deep_color.lerp(base_color, lerp_factor)
                for x in range(CELL_SIZE):
                    image.set_pixel(x, y, row_color)
            var offset := variant_index * 3
            for y in range(3, CELL_SIZE, 5):
                for x in range(CELL_SIZE):
                    if (x + y + offset) % 6 == 0:
                        image.set_pixel(x, y, highlight_color)
            for y in range(0, CELL_SIZE, 8):
                for x in range(0, CELL_SIZE, 8):
                    image.set_pixel(x, y, highlight_color.darkened(0.2))
        TerrainType.GRASS:
            var shadow_color := base_color.darkened(0.15)
            for y in range(CELL_SIZE):
                for x in range(CELL_SIZE):
                    var noise_val := rng_local.randf()
                    var tint := base_color.lerp(shadow_color, noise_val * 0.35)
                    image.set_pixel(x, y, tint)
            var blade_color := base_color.lightened(0.25)
            var tuft_count := 5 + variant_index * 2
            for _i in range(tuft_count):
                var tuft_center := Vector2i(rng_local.randi_range(2, CELL_SIZE - 3), rng_local.randi_range(2, CELL_SIZE - 3))
                for x_offset in range(-1, 2):
                    for y_offset in range(0, 3):
                        var pos := tuft_center + Vector2i(x_offset, -y_offset)
                        if pos.x >= 0 and pos.x < CELL_SIZE and pos.y >= 0 and pos.y < CELL_SIZE:
                            image.set_pixelv(pos, blade_color)
            for x in range(CELL_SIZE):
                if x % 5 == variant_index:
                    image.set_pixel(x, CELL_SIZE - 1, shadow_color)
        TerrainType.FOREST:
            var canopy_color := base_color.darkened(0.1)
            var canopy_highlight := base_color.lightened(0.2)
            var trunk_color := Color(0.25, 0.17, 0.11)
            var blob_centers := [
                Vector2i(CELL_SIZE // 3, CELL_SIZE // 3),
                Vector2i(CELL_SIZE // 2 + variant_index, CELL_SIZE * 2 // 3)
            ]
            for center in blob_centers:
                var radius := 4 + variant_index
                for y_offset in range(-radius, radius + 1):
                    for x_offset in range(-radius, radius + 1):
                        var pos := center + Vector2i(x_offset, y_offset)
                        if pos.x >= 0 and pos.x < CELL_SIZE and pos.y >= 0 and pos.y < CELL_SIZE:
                            var dist_sq := x_offset * x_offset + y_offset * y_offset
                            if dist_sq <= radius * radius:
                                var canopy_tint := canopy_color.lerp(canopy_highlight, clamp(1.0 - float(dist_sq) / float(radius * radius), 0.0, 1.0))
                                image.set_pixelv(pos, canopy_tint)
                var trunk_height := clamp(radius // 2, 2, CELL_SIZE - 2)
                for i in range(trunk_height):
                    var trunk_pos := Vector2i(center.x, min(center.y + i, CELL_SIZE - 1))
                    image.set_pixelv(trunk_pos, trunk_color)
        TerrainType.MOUNTAIN:
            var peak_color := base_color.lightened(0.4)
            var slope_color := base_color.darkened(0.1)
            var shadow_color := base_color.darkened(0.25)
            var peak_offset := variant_index - 1
            for y in range(CELL_SIZE):
                var slope_ratio := float(y) / float(CELL_SIZE - 1)
                var center_x := CELL_SIZE // 2 + peak_offset
                var half_width := int((1.0 - slope_ratio) * float(CELL_SIZE) * 0.35)
                var start_x := clamp(center_x - half_width, 0, CELL_SIZE - 1)
                var end_x := clamp(center_x + half_width, 0, CELL_SIZE - 1)
                for x in range(start_x, end_x + 1):
                    var color_tint := peak_color.lerp(slope_color, slope_ratio)
                    image.set_pixel(x, y, color_tint)
            for y in range(CELL_SIZE // 2, CELL_SIZE):
                for x in range(CELL_SIZE // 2 + peak_offset, CELL_SIZE):
                    var current := image.get_pixel(x, y)
                    image.set_pixel(x, y, current.lerp(shadow_color, 0.6))

    image.unlock()
    return ImageTexture.create_from_image(image)

func _create_character_marker() -> void:
    character_marker = Sprite2D.new()
    character_marker.texture = _make_character_marker_texture()
    character_marker.centered = true
    character_marker.z_index = 5
    add_child(character_marker)
    _update_character_marker(current_tile)

func _update_character_marker(tile: Vector2i) -> void:
    if character_marker == null:
        return
    var world_pos := _tile_to_world(tile)
    character_marker.global_position = world_pos

func _make_character_marker_texture() -> Texture2D:
    var image := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 0))
    image.lock()

    var center := Vector2i(CELL_SIZE // 2, CELL_SIZE // 2)
    var outer_radius := CELL_SIZE // 2
    var inner_radius := max(outer_radius - 3, 1)
    var highlight_color := Color(1.0, 0.95, 0.2, 0.9)
    var accent_color := Color(1.0, 0.45, 0.0, 0.9)

    for y in range(-outer_radius, outer_radius + 1):
        for x in range(-outer_radius, outer_radius + 1):
            var dist_sq := x * x + y * y
            if dist_sq <= outer_radius * outer_radius and dist_sq >= inner_radius * inner_radius:
                var pos := center + Vector2i(x, y)
                if pos.x >= 0 and pos.x < CELL_SIZE and pos.y >= 0 and pos.y < CELL_SIZE:
                    var tint := highlight_color if dist_sq < (outer_radius - 1) * (outer_radius - 1) else accent_color
                    image.set_pixelv(pos, tint)

    image.unlock()
    return ImageTexture.create_from_image(image)

func _create_player_visual() -> void:
    var image := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 0))
    image.lock()

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

    image.unlock()
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
