extends Node2D

## Map根节点：地图常量定义、生成调度、信号中转

# 地图尺寸
const WORLD_WIDTH = 32
const WORLD_HEIGHT = 128
const HALF_WIDTH = WORLD_WIDTH / 2  # x偏移量，使x从-16到+15
const FOUNDATION_WIDTH = 2  # 左右两侧地基列数

# 泥土/石头混合噪声
const DIRT_STONE_NOISE_FREQ = 0.08

# 空腔噪声
const CAVITY_THRESHOLD = 0.35
const CAVITY_NOISE_FREQ = 0.09
const CAVITY_MIN_DEPTH = 15

# 背景地图空腔阈值（更高=空腔更小）
const BACK_CAVITY_THRESHOLD = 0.45

# 挖掘限制
const DIG_MAX_DISTANCE = 250.0  # 玩家到方块最大距离（世界坐标）
const DIG_TIME_DIRT = 1.0      # 泥土挖掘时间（秒）
const DIG_TIME_STONE = 3.0     # 石头挖掘时间（秒）

@onready var solid_map: TileMapLayer = $SolidMap
@onready var back_map: TileMapLayer = $BackMap
@onready var sewer_pipe: TileMapLayer = $SewerPipe
@onready var fog_map: Node2D = $FogMap


func _ready() -> void:
	# 1. 生成主地形
	solid_map.generate_world()
	# 2. 生成背景地图（依赖SolidMap噪声）
	back_map._generate_back_world()
	# 3. 生成水管（依赖地图尺寸）
	sewer_pipe.generate_pipes()
	# 4. 初始化战争迷雾
	fog_map.init_fog()


func _process(_delta: float) -> void:
	fog_map.request_update()


## 处理玩家挖掘请求，转发给SolidMap
func _on_dig_requested(world_pos: Vector2) -> void:
	var player := get_node(^"../Player") as CharacterBody2D
	solid_map.handle_dig_request(world_pos, player)


## 处理玩家取消挖掘，转发给SolidMap
func _on_dig_cancelled() -> void:
	solid_map._cancel_dig()
