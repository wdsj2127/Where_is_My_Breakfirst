# ============================================================
# fog_map_maker.gd - 战争迷雾层（FogMap）
# ============================================================
# 每格 FOG_SUBDIV×FOG_SUBDIV 像素细分。
# Image尺寸 = (WORLD_WIDTH×SUBDIV) × (WORLD_HEIGHT×SUBDIV)
#
# 渲染模型：
#   _fog_data 为二值：0.0=已探索, 1.0=未探索（探索不可逆）
#   每个细分像素的opacity实时计算：
#     未探索         → 1.0（黑色）
#     已探索+在视野内 → live_op（距离渐变，0=透明→explored_op=灰色）
#     已探索+不在视野 → explored_op（灰色）
#
#   opacity: 0=可见(透明), EXPLORED_OP=已探索(灰), 1=未探索(黑)
#
# 规则：
#   - 射线投射在细分像素空间运行，每像素独立判断可见性
#   - 视线半径VIEW_RADIUS，边缘EDGE_FADE_WIDTH格渐变
#   - 遇墙后只能延伸1.5格（含射线进入墙壁的那一格）
#   - y=0始终可见
#   - 只更新屏幕可见范围
# ============================================================

extends Node2D

@export var solid_map: TileMapLayer
@export var player: CharacterBody2D
@export var player_center_offset := Vector2(0, -69)

var map: Node2D
var _subdiv: int = 8
var _img_w: int = 0   # Image宽 = WORLD_WIDTH * SUBDIV
var _img_h: int = 0   # Image高 = WORLD_HEIGHT * SUBDIV
var _fog_data = []     # [_img_h][_img_w] float, 0.0=已探索, 1.0=未探索
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
var _fog_sprite: Sprite2D = null
var _cell_world_size: float = 0.0

var _last_vis_set: Dictionary = {}   # 细分像素级可见集合
var _last_player_pos := Vector2(-9999.0, -9999.0)  # 上次计算可见性时的玩家浮点位置


func _ready() -> void:
	map = get_parent()
	_subdiv = map.FOG_SUBDIV


func _get_player_center() -> Vector2:
	return player.global_position + player_center_offset


func init_fog() -> void:
	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	_img_w = w * _subdiv
	_img_h = h * _subdiv

	_fog_data.clear()
	_fog_data.resize(_img_h)
	for sy in range(_img_h):
		_fog_data[sy] = []
		_fog_data[sy].resize(_img_w)
		if sy < _subdiv:
			_fog_data[sy].fill(0.0)
		else:
			_fog_data[sy].fill(1.0)

	_cell_world_size = 32.0 * solid_map.scale.x

	_fog_image = Image.create(_img_w, _img_h, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color.BLACK)
	_fog_texture = ImageTexture.create_from_image(_fog_image)

	_fog_sprite = Sprite2D.new()
	_fog_sprite.texture = _fog_texture
	_fog_sprite.z_index = 100
	_fog_sprite.centered = false
	var sub_world: float = _cell_world_size / float(_subdiv)
	_fog_sprite.scale = Vector2(sub_world, sub_world)
	var origin_cell := Vector2i(-map.HALF_WIDTH, 0)
	var cell_center := solid_map.to_global(solid_map.map_to_local(origin_cell))
	var half_cell: float = 16.0 * solid_map.scale.x
	_fog_sprite.global_position = cell_center - Vector2(half_cell, half_cell)
	solid_map.get_parent().add_child(_fog_sprite)


# 返回细分像素坐标范围 [x_min, x_max, y_min, y_max]
func _get_visible_range() -> Array:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return [0, _img_w - 1, 0, _img_h - 1]
	var cam_pos := cam.global_position
	var sw: float = map.FOG_SCREEN_W
	var sh: float = map.FOG_SCREEN_H
	var half_w: int = map.HALF_WIDTH
	var l_cell := solid_map.local_to_map(solid_map.to_local(Vector2(cam_pos.x - sw * 0.5, 0))).x
	var r_cell := solid_map.local_to_map(solid_map.to_local(Vector2(cam_pos.x + sw * 0.5, 0))).x
	var t_cell: int = solid_map.local_to_map(solid_map.to_local(Vector2(0, cam_pos.y - sh * 0.5))).y
	var b_cell: int = solid_map.local_to_map(solid_map.to_local(Vector2(0, cam_pos.y + sh * 0.5))).y
	var x_min: int = maxi((l_cell + half_w) * _subdiv - _subdiv, 0)
	var x_max: int = mini((r_cell + half_w + 1) * _subdiv + _subdiv, _img_w - 1)
	var y_min: int = maxi(t_cell * _subdiv - _subdiv, 0)
	var y_max: int = mini((b_cell + 1) * _subdiv + _subdiv, _img_h - 1)
	return [x_min, x_max, y_min, y_max]


# 将世界坐标转换为细分像素浮点坐标
func _world_to_sub(world_pos: Vector2) -> Vector2:
	var local_pos := solid_map.to_local(world_pos)
	var fx: float = (local_pos.x / 32.0 + float(map.HALF_WIDTH)) * float(_subdiv)
	var fy: float = (local_pos.y / 32.0) * float(_subdiv)
	return Vector2(fx, fy)


func update_fog() -> void:
	if not player:
		return

	var player_center := _get_player_center()
	var pf := _world_to_sub(player_center)

	# 玩家移动超过0.5细分像素时重算可见性
	if (pf - _last_player_pos).length_squared() > 0.25:
		_last_player_pos = pf
		var vis_result = _compute_visibility(pf.x, pf.y)
		_last_vis_set = vis_result

		# 更新已探索标记
		var r := _get_visible_range()
		for key in _last_vis_set:
			var sy: int = key / _img_w
			var sx: int = key % _img_w
			if sy < r[2] or sy > r[3] or sx < r[0] or sx > r[1]:
				continue
			if sy < _subdiv:
				_fog_data[sy][sx] = 0.0
			elif _fog_data[sy][sx] > 0.0:
				_fog_data[sy][sx] = 0.0

	_render(pf.x, pf.y)


func _render(pfx: float, pfy: float) -> void:
	if not _fog_image:
		return

	var w: int = map.WORLD_WIDTH
	var view_radius: int = map.FOG_VIEW_RADIUS
	var edge_fade: float = map.FOG_EDGE_FADE_WIDTH
	var explored_op: float = map.FOG_EXPLORED_OPACITY
	var soften_passes: int = map.FOG_SOFTEN_PASSES

	var r := _get_visible_range()
	var x_min: int = r[0]; var x_max: int = r[1]
	var y_min: int = r[2]; var y_max: int = r[3]

	_fog_image.fill_rect(Rect2i(x_min, y_min, x_max - x_min + 1, y_max - y_min + 1), Color.BLACK)

	var fade_inner: float = float(view_radius) - edge_fade
	var vr_f: float = float(view_radius)
	var sub_f: float = float(_subdiv)

	# ---- 计算每个细分像素的opacity到临时缓冲 ----
	var rw: int = x_max - x_min + 1
	var rh: int = y_max - y_min + 1
	var op_buf = []
	op_buf.resize(rh)
	for ry in range(rh):
		op_buf[ry] = []
		op_buf[ry].resize(rw)

	for sy in range(y_min, y_max + 1):
		var ry: int = sy - y_min
		for sx in range(x_min, x_max + 1):
			var rx: int = sx - x_min
			if sy < _subdiv:
				op_buf[ry][rx] = 0.0
				continue

			var base_op: float = _fog_data[sy][sx]

			# 未探索→保持黑色
			if base_op > 0.99:
				op_buf[ry][rx] = 1.0
				continue

			# 已探索：判断该细分像素是否在当前视野内
			var key: int = sy * _img_w + sx
			var is_visible: bool = _last_vis_set.has(key)

			var opacity: float
			if is_visible:
				# 已探索+在视野内：用细分像素中心到玩家的距离计算渐变
				var dx: float = (float(sx) + 0.5 - pfx) / sub_f
				var dy: float = (float(sy) + 0.5 - pfy) / sub_f
				var dist: float = sqrt(dx * dx + dy * dy)
				if dist <= fade_inner:
					opacity = 0.0
				elif dist <= vr_f:
					opacity = explored_op * ((dist - fade_inner) / edge_fade)
				else:
					var outer: float = dist - vr_f
					if outer < edge_fade:
						opacity = explored_op + (1.0 - explored_op) * (outer / edge_fade)
					else:
						opacity = 1.0
			else:
				# 已探索+不在视野内：灰色
				opacity = explored_op

			op_buf[ry][rx] = opacity

	# ---- 软化模糊（3×3均值模糊，多次pass） ----
	for _p in range(soften_passes):
		var tmp = []
		tmp.resize(rh)
		for ry in range(rh):
			tmp[ry] = []
			tmp[ry].resize(rw)
		for ry in range(rh):
			for rx in range(rw):
				var sum: float = 0.0
				var cnt: int = 0
				for dy in range(-1, 2):
					var ny: int = ry + dy
					if ny < 0 or ny >= rh:
						continue
					for dx in range(-1, 2):
						var nx: int = rx + dx
						if nx < 0 or nx >= rw:
							continue
						sum += op_buf[ny][nx]
						cnt += 1
				tmp[ry][rx] = sum / float(cnt)
		op_buf = tmp

	# ---- 颜色映射写像素 ----
	for sy in range(y_min, y_max + 1):
		var ry: int = sy - y_min
		for sx in range(x_min, x_max + 1):
			var rx: int = sx - x_min
			if sy < _subdiv:
				_fog_image.set_pixel(sx, sy, Color.TRANSPARENT)
				continue

			var opacity: float = op_buf[ry][rx]

			if opacity < 0.01:
				_fog_image.set_pixel(sx, sy, Color.TRANSPARENT)
			elif opacity > 0.99:
				pass
			elif opacity <= explored_op:
				_fog_image.set_pixel(sx, sy, Color(0.3, 0.3, 0.3, opacity))
			else:
				var t2: float = (opacity - explored_op) / (1.0 - explored_op)
				var g: float = 0.3 * (1.0 - t2)
				_fog_image.set_pixel(sx, sy, Color(g, g, g, opacity))

	_fog_texture.update(_fog_image)


# 射线投射计算可见细分像素集合
# 在细分像素空间运行，步长=1细分像素
# 遇墙后只能延伸1.5格（含射线进入墙壁的那一格）
# 返回 Dictionary[细分像素key] = true
func _compute_visibility(pfx: float, pfy: float) -> Dictionary:
	var visible = {}
	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	var view_radius: int = map.FOG_VIEW_RADIUS
	var sub: int = _subdiv

	# y=0行始终可见
	for sx in range(_img_w):
		visible[sx] = true

	# 射线参数（细分像素空间）
	var radius_sub: float = float(view_radius) * float(sub)  # 视线半径（细分像素）
	var step_size: float = 1.0  # 步长=1细分像素
	var total_steps: int = int(ceilf(radius_sub / step_size))
	# 遇墙后允许再走的细分像素步数：1.5格含起始格 = 1.5*sub步，hit_wall那步已算1步，后续还需1.5*sub-1步
	var wall_extend_steps: int = int(1.5 * float(sub)) - 1

	var num_rays: int = 360  # 360条射线（每1度一条，细分后需要更多射线保证覆盖）

	for a in range(num_rays):
		var angle: float = deg_to_rad(float(a))
		var ddx: float = cos(angle) * step_size
		var ddy: float = sin(angle) * step_size
		var hit_wall := false
		var wall_steps: int = 0
		var fx: float = pfx
		var fy: float = pfy
		for si in range(total_steps):
			fx += ddx
			fy += ddy
			var sx: int = int(floor(fx))
			var sy: int = int(floor(fy))
			if sx < 0 or sx >= _img_w or sy < 0 or sy >= _img_h:
				break
			visible[sy * _img_w + sx] = true
			if hit_wall:
				wall_steps += 1
				if wall_steps >= wall_extend_steps:
					break
			else:
				# 检查该细分像素所属的格子是否为墙壁
				var cx: int = sx / sub
				var cy: int = sy / sub
				if cx >= 0 and cx < w and cy >= 0 and cy < h:
					if solid_map._block_data[cy][cx] != solid_map.BlockType.AIR:
						hit_wall = true

	return visible
