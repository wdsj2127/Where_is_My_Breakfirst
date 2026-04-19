extends TileMapLayer

## 地形生成算法：泥土、石头、地基填充，噪声驱动硬石脉、空腔和目标点

enum BlockType { AIR, DIRT, STONE, FOUNDATION, HARD_STONE }

# 地图尺寸
const WORLD_WIDTH = 32
const WORLD_HEIGHT = 96
const FOUNDATION_WIDTH = 2  # 左右两侧地基列数

# 泥土/石头混合噪声
const DIRT_STONE_THRESHOLD = 0.0
const DIRT_STONE_NOISE_FREQ = 0.08

# 硬石脉噪声
const HARD_STONE_THRESHOLD = 0.65
const HARD_STONE_NOISE_FREQ = 0.12

# 空腔噪声
const CAVITY_THRESHOLD = 0.35
const CAVITY_NOISE_FREQ = 0.09
const CAVITY_MIN_DEPTH = 10

# TileSet source ID: 0=地基, 1=岩石, 2=泥土
const _SOURCE_FOUNDATION = 0
const _SOURCE_STONE = 1
const _SOURCE_DIRT = 2

# 地图数组
var _block_data = []
var target_position = Vector2i(-1, -1)

var _dirt_stone_noise: FastNoiseLite
var _hard_stone_noise: FastNoiseLite
var _cavity_noise: FastNoiseLite


func _ready() -> void:
	_init_noises()
	generate_world()


## 初始化噪声实例，种子由随机数生成
func _init_noises() -> void:
	var base_seed := randi()
	_dirt_stone_noise = _create_noise(base_seed, DIRT_STONE_NOISE_FREQ)
	_hard_stone_noise = _create_noise(base_seed + 1, HARD_STONE_NOISE_FREQ)
	_cavity_noise = _create_noise(base_seed + 2, CAVITY_NOISE_FREQ)


## 创建FBM分形噪声实例
@warning_ignore("shadowed_global_identifier")
static func _create_noise(seed: int, freq: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


## 世界生成主流程
func generate_world() -> void:
	_init_block_data()
	_fill_base_terrain()
	_generate_hard_stone()
	_generate_cavities()
	_generate_target_point()
	_render_to_tilemap()


## 初始化地块数据为全AIR
func _init_block_data() -> void:
	_block_data.clear()
	_block_data.resize(WORLD_HEIGHT)
	for y in range(WORLD_HEIGHT):
		_block_data[y] = []
		_block_data[y].resize(WORLD_WIDTH)
		_block_data[y].fill(BlockType.AIR)


## 填充基础地形：地基边界、地表泥土、地下泥土/石头混合
func _fill_base_terrain() -> void:
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			# 左右地基边界
			if x < FOUNDATION_WIDTH or x >= WORLD_WIDTH - FOUNDATION_WIDTH:
				_block_data[y][x] = BlockType.FOUNDATION
				continue
			# 地表第一行固定泥土
			if y == 0:
				_block_data[y][x] = BlockType.DIRT
				continue
			# 地表以下噪声驱动泥土/石头混合
			var noise_val := _dirt_stone_noise.get_noise_2d(x, y)
			_block_data[y][x] = BlockType.STONE if noise_val > DIRT_STONE_THRESHOLD else BlockType.DIRT


## 噪声驱动硬石脉生成，地表5格以下出现
func _generate_hard_stone() -> void:
	for y in range(5, WORLD_HEIGHT):  # 地表5格以下才出现硬石
		for x in range(FOUNDATION_WIDTH, WORLD_WIDTH - FOUNDATION_WIDTH):
			if _block_data[y][x] == BlockType.AIR or _block_data[y][x] == BlockType.FOUNDATION:
				continue
			if _hard_stone_noise.get_noise_2d(x, y) > HARD_STONE_THRESHOLD:
				_block_data[y][x] = BlockType.HARD_STONE


## 噪声驱动空腔生成，将符合条件的实心地块挖空
func _generate_cavities() -> void:
	for y in range(CAVITY_MIN_DEPTH, WORLD_HEIGHT):
		for x in range(FOUNDATION_WIDTH + 2, WORLD_WIDTH - FOUNDATION_WIDTH - 2):
			if _cavity_noise.get_noise_2d(x, y) > CAVITY_THRESHOLD:
				_block_data[y][x] = BlockType.AIR


## 从底部向前搜索，找到最深空腔即为目标点
func _generate_target_point() -> void:
	var min_x := FOUNDATION_WIDTH + 1
	var max_x := WORLD_WIDTH - FOUNDATION_WIDTH - 1
	for y in range(WORLD_HEIGHT - 1, CAVITY_MIN_DEPTH - 1, -1):
		for x in range(min_x, max_x):
			if _block_data[y][x] == BlockType.AIR:
				target_position = Vector2i(x, y)
				return
	target_position = Vector2i(-1, -1)


## 将地块数据渲染到TileMapLayer
func _render_to_tilemap() -> void:
	clear()
	for y in range(WORLD_HEIGHT):
		for x in range(WORLD_WIDTH):
			var block_type: int = _block_data[y][x]
			if block_type == BlockType.AIR:
				continue
			var source_id: int
			var atlas_coords: Vector2i
			match block_type:
				BlockType.DIRT:
					source_id = _SOURCE_DIRT
					atlas_coords = _get_atlas_coords(x, y, block_type)
				BlockType.STONE:
					source_id = _SOURCE_STONE
					atlas_coords = _get_atlas_coords(x, y, block_type)
				BlockType.FOUNDATION:
					source_id = _SOURCE_FOUNDATION
					atlas_coords = Vector2i(0, 0)
				BlockType.HARD_STONE:
					source_id = _SOURCE_STONE  # 暂用石头纹理占位
					atlas_coords = _get_atlas_coords(x, y, block_type)
				_:
					continue
			set_cell(Vector2i(x, y), source_id, atlas_coords, 0)


## 3x3图集坐标：根据同类型邻居选择边缘/角落/中心变体
func _get_atlas_coords(x: int, y: int, block_type: int) -> Vector2i:
	var has_top := _is_same_type(x, y - 1, block_type)
	var has_bottom := _is_same_type(x, y + 1, block_type)
	var has_left := _is_same_type(x - 1, y, block_type)
	var has_right := _is_same_type(x + 1, y, block_type)
	var ax := 1
	var ay := 1
	if not has_left and not has_top:
		ax = 0; ay = 0
	elif not has_right and not has_top:
		ax = 2; ay = 0
	elif not has_left and not has_bottom:
		ax = 0; ay = 2
	elif not has_right and not has_bottom:
		ax = 2; ay = 2
	elif not has_top:
		ay = 0
	elif not has_bottom:
		ay = 2
	elif not has_left:
		ax = 0
	elif not has_right:
		ax = 2
	return Vector2i(ax, ay)


## 判断坐标处是否为指定类型，越界返回false
func _is_same_type(x: int, y: int, block_type: int) -> bool:
	if x < 0 or x >= WORLD_WIDTH or y < 0 or y >= WORLD_HEIGHT:
		return false
	return _block_data[y][x] == block_type


## 获取目标点的世界像素坐标
func get_target_world_position() -> Vector2:
	return map_to_local(target_position)


## 重新生成世界（新随机种子）
func regenerate() -> void:
	_init_noises()
	generate_world()
