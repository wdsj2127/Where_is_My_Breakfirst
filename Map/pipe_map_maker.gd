extends TileMapLayer

## 水管生成算法：从左右地基向内延伸，竖直为主，偶尔水平偏移
## 由SolidMap生成完毕后调用

@export var solid_map: TileMapLayer

# 水管参数
const PIPE_COUNT_PER_SIDE = 3
const PIPE_MIN_START_DEPTH = 8
const PIPE_MAX_HORIZONTAL = 6
const PIPE_HORIZONTAL_CHANCE = 0.3

# TileSet source ID
# 0=始末, 1=崭新出厂, 2=接缝1, 3=接缝2, 4=略有磨损, 5=拐弯1, 6=拐弯2
const _SOURCE_END = 0
const _SOURCE_NEW = 1
const _SOURCE_SEAM1 = 2
const _SOURCE_SEAM2 = 3
const _SOURCE_WORN = 4
const _SOURCE_BEND1 = 5
const _SOURCE_BEND2 = 6

enum Dir { VERTICAL, HORIZONTAL }

var map: Node2D
var _pipe_noise: FastNoiseLite
var _pipe_paths: Array = []


func _ready() -> void:
	map = get_parent()
	# 不在此处生成，等待SolidMap通知


## 由map_controller调用，开始生成水管
func generate_pipes() -> void:
	_pipe_noise = _create_noise(randi(), 0.1)
	clear()
	_pipe_paths.clear()

	if solid_map == null:
		return

	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	var fw: int = map.FOUNDATION_WIDTH

	# 左侧水管
	for i in range(PIPE_COUNT_PER_SIDE):
		var start_y := _get_pipe_start_y(i, h)
		_generate_single_pipe(fw - 1, start_y, 1, w, h, fw)

	# 右侧水管
	for i in range(PIPE_COUNT_PER_SIDE):
		var start_y := _get_pipe_start_y(i, h)
		_generate_single_pipe(w - fw, start_y, -1, w, h, fw)


## 创建噪声实例
@warning_ignore("shadowed_global_identifier")
static func _create_noise(seed: int, freq: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


## 计算第i根水管的起始y坐标
func _get_pipe_start_y(index: int, world_height: int) -> int:
	var spacing: int = (world_height - PIPE_MIN_START_DEPTH) / (PIPE_COUNT_PER_SIDE + 1)
	return PIPE_MIN_START_DEPTH + spacing * (index + 1)


## 生成单根水管
func _generate_single_pipe(start_x: int, start_y: int, dir_x: int, world_width: int, world_height: int, foundation_width: int) -> void:
	var path: Array = []
	var x := start_x
	var y := start_y
	var prev_dir := Dir.HORIZONTAL

	path.append({x = x, y = y, dir = Dir.HORIZONTAL})

	var h_steps := 0
	var initial_horizontal := 1 + int(_pipe_noise.get_noise_2d(x, y) > 0.0)
	for _i in range(initial_horizontal):
		x += dir_x
		if not _is_valid_pipe_pos(x, y, world_width, world_height, foundation_width):
			break
		path.append({x = x, y = y, dir = Dir.HORIZONTAL})
		h_steps += 1

	prev_dir = Dir.HORIZONTAL
	while y < world_height - 1:
		y += 1

		if h_steps < PIPE_MAX_HORIZONTAL and _pipe_noise.get_noise_2d(x, y) > (1.0 - PIPE_HORIZONTAL_CHANCE * 2.0):
			x += dir_x
			if not _is_valid_pipe_pos(x, y, world_width, world_height, foundation_width):
				x -= dir_x
			else:
				path.append({x = x, y = y, dir = Dir.HORIZONTAL, prev = prev_dir})
				h_steps += 1
				prev_dir = Dir.HORIZONTAL
				continue

		if not _is_valid_pipe_pos(x, y, world_width, world_height, foundation_width):
			break
		path.append({x = x, y = y, dir = Dir.VERTICAL, prev = prev_dir})
		prev_dir = Dir.VERTICAL

	_pipe_paths.append(path)
	_render_pipe(path)


## 判断坐标是否可用于水管
func _is_valid_pipe_pos(x: int, y: int, world_width: int, world_height: int, foundation_width: int) -> bool:
	if x <= foundation_width or x >= world_width - foundation_width:
		return false
	if y < 0 or y >= world_height:
		return false
	return true


## 渲染单根水管
func _render_pipe(path: Array) -> void:
	var half_width: int = map.HALF_WIDTH
	for i in range(path.size()):
		var point = path[i]
		var pos := Vector2i(point.x - half_width, point.y)
		var dir: int = point.dir

		var source_id: int
		var atlas_coords := Vector2i(0, 0)

		# 首尾用始末，拐弯处用拐弯贴图，中间随机选样式
		if i == 0 or i == path.size() - 1:
			source_id = _SOURCE_END
		elif dir == Dir.HORIZONTAL and point.get("prev", dir) == Dir.VERTICAL:
			source_id = _SOURCE_BEND1
		elif dir == Dir.VERTICAL and point.get("prev", dir) == Dir.HORIZONTAL:
			source_id = _SOURCE_BEND2
		else:
			source_id = _pick_body_style(point.x, point.y)

		var alt_tile := 1 if dir == Dir.HORIZONTAL else 0
		set_cell(pos, source_id, atlas_coords, alt_tile)


## 根据噪声选择水管中间段样式
func _pick_body_style(x: int, y: int) -> int:
	var val := _pipe_noise.get_noise_2d(x * 3.7, y * 3.7)
	if val > 0.3:
		return _SOURCE_NEW
	elif val > -0.1:
		return _SOURCE_WORN
	elif val > -0.4:
		return _SOURCE_SEAM1
	else:
		return _SOURCE_SEAM2


## 获取所有水管路径
func get_pipe_paths() -> Array:
	return _pipe_paths


## 重新生成水管
func regenerate() -> void:
	generate_pipes()
