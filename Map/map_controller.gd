# ============================================================
# map_controller.gd - 地图根节点控制器
# ============================================================
# 功能：地图常量定义、子层生成调度（SolidMap→BackMap→SewerPipe→FogMap）、
#       挖掘信号中转（Player↔SolidMap）、迷雾每帧更新
# 方法：
#   _ready()                      - 按序生成各层，将player传递给FogMap
#   _process(delta)               - 每帧更新战争迷雾
#   _on_dig_requested(world_pos)  - 转发玩家挖掘请求给SolidMap
#   _on_dig_cancelled()           - 转发玩家取消挖掘给SolidMap
# ============================================================

extends Node2D

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

# 迷雾参数
const FOG_SUBDIV = 8              # 每格细分数（1格=8×8像素）
const FOG_VIEW_RADIUS = 8         # 视线半径（格）
const FOG_EDGE_FADE_WIDTH = 5.0   # 视线边缘渐变宽度（格）
const FOG_EXPLORED_OPACITY = 0.85 # 已探索区域不透明度
const FOG_SOFTEN_PASSES = 2      # 迷雾软化模糊次数（3×3均值模糊）
const FOG_SCREEN_W = 1920         # 屏幕宽度（用于计算可见范围）
const FOG_SCREEN_H = 1080         # 屏幕高度（用于计算可见范围）

## 玩家引用（在main.tscn中选中Map节点，在Inspector拖入Player节点）
@export var player: CharacterBody2D

@onready var solid_map: TileMapLayer = $SolidMap
@onready var back_map: TileMapLayer = $BackMap
@onready var sewer_pipe: TileMapLayer = $SewerPipe
@onready var fog_map: Node2D = $FogMap


## 初始化：按序生成各层（SolidMap→BackMap→SewerPipe→FogMap），将player传递给FogMap
func _ready() -> void:
	# 1. 生成主地形
	solid_map.generate_world()
	# 2. 生成背景地图（依赖SolidMap噪声）
	back_map._generate_back_world()
	# 3. 生成水管（依赖地图尺寸）
	sewer_pipe.generate_pipes()
	# 4. 初始化战争迷雾（传递player引用）
	fog_map.player = player
	fog_map.init_fog()


## 每帧更新战争迷雾
## 参数 _delta: 帧间隔时间（秒），未使用
func _process(_delta: float) -> void:
	fog_map.update_fog()


## 转发玩家挖掘请求给SolidMap
## 参数 world_pos: 鼠标世界坐标
func _on_dig_requested(world_pos: Vector2) -> void:
	solid_map.handle_dig_request(world_pos, player)


## 转发玩家取消挖掘给SolidMap
func _on_dig_cancelled() -> void:
	solid_map.cancel_dig()
