extends Node2D

## 战争迷雾：未探索=黑色，已探索不在视线=灰色，视线内=透明
## 视线只能穿过一层方块，以格为单位

@export var solid_map: TileMapLayer

# 迷雾状态
enum FogState { VISIBLE, EXPLORED, UNEXPLORED }

# 视线参数
const VIEW_RADIUS = 8
const PLAYER_GLOW_DEPTH = 40

var map: Node2D
var _fog_data = []
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
var _fog_sprite: Sprite2D = null
var _player_glow: PointLight2D = null
var _last_player_cell := Vector2i(-999, -999)
var _visual_dirty := true


func _ready() -> void:
	map = get_parent()


## 初始化迷雾（由map_controller调用）
func init_fog() -> void:
	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	_fog_data.clear()
	_fog_data.resize(h)
	for y in range(h):
		_fog_data[y] = []
		_fog_data[y].resize(w)
		_fog_data[y].fill(FogState.UNEXPLORED)

	# 创建迷雾图像
	_fog_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color.BLACK)
	_fog_texture = ImageTexture.create_from_image(_fog_image)

	# 创建迷雾精灵
	_fog_sprite = Sprite2D.new()
	_fog_sprite.texture = _fog_texture
	_fog_sprite.z_index = 100
	_fog_sprite.centered = false
	var cell_world_size: float = 32.0 * solid_map.scale.x
	_fog_sprite.scale = Vector2(cell_world_size, cell_world_size)
	# 图像(0,0)对齐格子(-HALF_WIDTH, 0)的左上角世界位置
	var origin_cell := Vector2i(-map.HALF_WIDTH, 0)
	var cell_center := solid_map.to_global(solid_map.map_to_local(origin_cell))
	var half_cell: float = 16.0 * solid_map.scale.x
	_fog_sprite.global_position = cell_center - Vector2(half_cell, half_cell)
	solid_map.get_parent().add_child(_fog_sprite)

	_ensure_player_glow()
	_visual_dirty = true


## 每帧更新迷雾（由map_controller调用）
func update_fog() -> void:
	var player := get_node_or_null(^"../../Player") as CharacterBody2D
	if not player:
		return

	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	var half_w: int = map.HALF_WIDTH

	# 计算玩家所在格子
	var player_local := solid_map.to_local(player.global_position + Vector2(0, -69))
	var player_cell := solid_map.local_to_map(player_local)
	var px: int = player_cell.x + half_w
	var py: int = player_cell.y

	# 玩家格子未变则跳过视线计算
	if player_cell == _last_player_cell:
		if _visual_dirty:
			_update_fog_visual()
			_visual_dirty = false
		_update_player_glow(py)
		return
	_last_player_cell = player_cell

	# 计算视线
	var visible_set = _compute_visibility(px, py, w, h)

	# 更新迷雾数据
	for y in range(h):
		for x in range(w):
			if visible_set.has(y * w + x):
				_fog_data[y][x] = FogState.VISIBLE
			elif _fog_data[y][x] == FogState.VISIBLE:
				_fog_data[y][x] = FogState.EXPLORED

	_visual_dirty = true
	_update_fog_visual()
	_update_player_glow(py)


## 更新迷雾图像
func _update_fog_visual() -> void:
	if not _fog_image:
		return
	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	_fog_image.fill(Color.TRANSPARENT)
	for y in range(h):
		for x in range(w):
			var fog: int = _fog_data[y][x]
			if fog == FogState.VISIBLE:
				continue
			var color := Color.BLACK if fog == FogState.UNEXPLORED else Color(0.3, 0.3, 0.3, 0.85)
			_fog_image.set_pixel(x, y, color)
	_fog_texture.update(_fog_image)


## 计算从玩家位置出发的可见格子集合
## 视线只能穿过一层实心方块
func _compute_visibility(px: int, py: int, w: int, h: int) -> Dictionary:
	var visible = {}
	if px >= 0 and px < w and py >= 0 and py < h:
		visible[py * w + px] = true

	for angle_step in range(360):
		var angle: float = deg_to_rad(float(angle_step))
		var dx: float = cos(angle)
		var dy: float = sin(angle)
		var solid_count := 0
		var fx: float = float(px) + 0.5
		var fy: float = float(py) + 0.5
		for _step in range(VIEW_RADIUS):
			fx += dx
			fy += dy
			var cx: int = int(floor(fx))
			var cy: int = int(floor(fy))
			if cx < 0 or cx >= w or cy < 0 or cy >= h:
				break
			visible[cy * w + cx] = true
			if solid_map._block_data[cy][cx] != solid_map.BlockType.AIR:
				solid_count += 1
				if solid_count > 1:
					break
	return visible


## 确保玩家发光光源存在
func _ensure_player_glow() -> void:
	if _player_glow:
		return
	var player := get_node_or_null(^"../../Player")
	if not player:
		return
	_player_glow = PointLight2D.new()
	_player_glow.color = Color(1.0, 0.9, 0.7, 1.0)
	_player_glow.energy = 0.0
	_player_glow.texture = _create_light_texture()
	_player_glow.z_index = 10
	player.add_child(_player_glow)


## 创建圆形渐变光纹理
func _create_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = [Color.WHITE, Color.WHITE, Color.TRANSPARENT]
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex


## 更新玩家发光强度
func _update_player_glow(player_y: int) -> void:
	if not _player_glow:
		return
	if player_y >= PLAYER_GLOW_DEPTH:
		var ratio: float = float(player_y - PLAYER_GLOW_DEPTH) / float(map.WORLD_HEIGHT - PLAYER_GLOW_DEPTH)
		_player_glow.energy = lerpf(0.5, 3.0, ratio)
		_player_glow.scale = Vector2.ONE * lerpf(3.0, 8.0, ratio)
	else:
		_player_glow.energy = 0.0
