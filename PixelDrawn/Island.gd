extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false
onready var points_done := false
onready var fill_done := false
onready var distance_done := false
onready var rivers_done := false
onready var coast_image_step: Image = Image.new()

const SEA_COLOR := Color8(32, 32, 128, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)
const COAST_START_DIR: float = 0.0
const COAST_MIN_EXTENT: float = 0.5
const COAST_MAX_EXTENT: float = 0.8
const MAX_POINT_SPACE: float = 10.0
const MAX_POINT_SPACE_SQR: float = MAX_POINT_SPACE * MAX_POINT_SPACE
const POINT_INSERT_SPREAD: float = 0.5
const FILL_DIRS: Array = [
	Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT
]

var coast_drawer: CoastDrawer
var image_filler: ImageFiller
var inland_distancer: InlandDistancer
var river_path_maker: RiverPathMaker


class BaseStep:
	var _rng: RandomNumberGenerator
	
	func _init() -> void:
		_rng = RandomNumberGenerator.new()
		_rng.seed = hash("island")
#		_rng.seed = OS.get_system_time_msecs()
	
	static func draw_line_on_image(image: Image, a: Vector2, b: Vector2, col: Color) -> void:
		var longest_side = int(max(abs(a.x - b.x), abs(a.y - b.y))) + 1
		for p in range(longest_side):
			var t = (1.0 / longest_side) * p
			image.set_pixelv(lerp(a, b, t), col)
	
	func _get_point_between(a: Vector2, b: Vector2) -> Vector2:
		var mid_point = lerp(a, b, 0.5)
		var tangent = (b - a).tangent()
		return mid_point + tangent * (_rng.randf() - 0.5) * POINT_INSERT_SPREAD


class CoastDrawer extends BaseStep:
	var _angle: float = 0.0
	var _rect_size: Vector2
	var _center: Vector2
	var _min_ratio: float
	var _max_ratio: float
	var _point_list: PoolVector2Array
	var _river_mouth_list: Array
	
	func _init(rect_size: Vector2, min_ratio: float, max_ratio: float).() -> void:
		_rect_size = rect_size
		_center = rect_size / 2.0
		_min_ratio = min_ratio
		_max_ratio = max_ratio
		_point_list = _get_initial_points()
		_river_mouth_list = Array(_point_list)
		_point_list.append(_point_list[0])
	
	func _get_initial_points() -> PoolVector2Array:
		var angle := 0.0
		var point_list := PoolVector2Array()
		while angle < PI * 2:
			point_list.append(_get_point_at_angle(angle))
			angle += 0.25 * PI
		return point_list
	
	func _get_point_at_angle(angle: float) -> Vector2:
		var ratio = lerp(_min_ratio, _max_ratio, _rng.randf()) * 0.5
		var width_ratio = _rect_size.x * ratio
		var height_ratio = _rect_size.y * ratio
		var point: Vector2 = Vector2(
			cos(angle) * width_ratio, sin(angle) * height_ratio
		) + _center
		return point
	
	func process_sub_points() -> bool:
		var done = true
		var new_point_list := PoolVector2Array()
		for i in range(_point_list.size() - 1):
			var a: Vector2 = _point_list[i]
			var b: Vector2 = _point_list[i + 1]
			new_point_list.append(a)
			if a.distance_squared_to(b) >= MAX_POINT_SPACE_SQR:
				var new_point: Vector2 = _get_point_between(a, b)
				new_point_list.append(new_point)
				done = false
		
		new_point_list.append(new_point_list[0])
		_point_list = new_point_list
		return done
	
	func draw_points(image: Image) -> void:
		image.lock()
		for i in range(_point_list.size() - 1):
			var a = _point_list[i]
			var b = _point_list[i + 1]
			draw_line_on_image(image, a, b, COAST_COLOR)
		image.unlock()
	


class ImageFiller extends BaseStep:
	var _fill_point_pool: Array
	var _fill_color: Color
	var _replace_color: Color
	var _edge_point_pool: Array
	
	func _init(rect_size: Vector2, fill_color: Color, replace_color: Color).() -> void:
		_fill_point_pool = [rect_size / 2.0]
		_fill_color = fill_color
		_replace_color = replace_color
		_edge_point_pool = []
	
	func fill_from_center(fill_image: Image) -> bool:
		if _fill_point_pool.empty():
			return true
		
		var frame_end = OS.get_ticks_msec() + 30
		fill_image.lock()
		
		while OS.get_ticks_msec() < frame_end and not _fill_point_pool.empty():
			var point: Vector2 = _fill_point_pool.pop_front()
			fill_image.set_pixelv(point, _fill_color)
			
			var empty_neighbours := 0
			var coast_neighbours := 0
			for dir in FILL_DIRS:
				var neighbour = point + dir
				var neighbour_color = fill_image.get_pixelv(neighbour)
				if neighbour_color.is_equal_approx(_replace_color):
					fill_image.set_pixelv(neighbour, _fill_color)
					_fill_point_pool.push_back(neighbour)
					empty_neighbours += 1
				# TODO: Kind of feel like COAST_COLOR should be class level
				if neighbour_color.is_equal_approx(COAST_COLOR):
					coast_neighbours += 1
			
			if empty_neighbours == 0 and coast_neighbours > 0:
				_edge_point_pool.append(point)
			
		
		fill_image.unlock()
		return false


class InlandDistancer extends BaseStep:
	var _edge_point_pool
	var _next_level_pool
	var _low_color: Color = Color8(0, 140, 0, 255)
	var _high_color: Color = Color8(255, 140, 255, 255)
	var _height: float = 0.0
	var _per_level: float = 1.0 / 256.0
	
	func _init(edge_points: Array).() -> void:
		_edge_point_pool = edge_points
		_next_level_pool = []
	
	func raise_inland(image: Image) -> bool:
		if _edge_point_pool.empty():
			return true
			
		var frame_end = OS.get_ticks_msec() + 30
		image.lock()
		
		while OS.get_ticks_msec() < frame_end and not _edge_point_pool.empty():
			var point: Vector2 = _edge_point_pool.pop_front()
			
			image.set_pixelv(point, lerp(_low_color, _high_color, _height))
			for dir in FILL_DIRS:
				var neighbour = point + dir
				var neighbour_color = image.get_pixelv(neighbour)
				# TODO: Kind of feel like LAND_COLOR should be class level
				if neighbour_color.is_equal_approx(LAND_COLOR) and not _next_level_pool.has(neighbour):
					_next_level_pool.append(neighbour)
			
			if _edge_point_pool.empty():
				_edge_point_pool = _next_level_pool
				_next_level_pool = []
				_height += _per_level
		
		image.unlock()
		return false


class RiverPathMaker extends BaseStep:
	var _mouth_point_pool: Array
	var _rivers: Array
	var _center: Vector2
	
	func _init(rect_size: Vector2, mouth_point_pool: Array).() -> void:
		_mouth_point_pool = mouth_point_pool
		_center = rect_size / 2.0
		_rivers = _get_initial_rivers()
	
	
	func _get_initial_rivers() -> Array:
		var rivers: Array = []
		for mouth in _mouth_point_pool:
			var head: Vector2 = lerp(_center, mouth, 0.1)
			var river: PoolVector2Array = PoolVector2Array([head, mouth])
			rivers.append(river)
		return rivers
		
	func process_sub_points() -> bool:
		var done = true
		var new_rivers: Array = []
		for river in _rivers:
			var new_river_points := PoolVector2Array([river[0]])
			for i in range(river.size() - 1):
				var a: Vector2 = river[i]
				var b: Vector2 = river[i + 1]
				if a.distance_squared_to(b) >= MAX_POINT_SPACE_SQR:
					var new_point: Vector2 = _get_point_between(a, b)
					new_river_points.append(new_point)
					done = false
				new_river_points.append(b)

			new_rivers.append(new_river_points)
		_rivers = new_rivers
		return done
	
	func draw_points(image: Image) -> void:
		image.lock()
		for river in _rivers:
			for i in range(river.size() - 1):
				var a = river[i]
				var b = river[i + 1]
				draw_line_on_image(image, a, b, RIVER_COLOR)
		image.unlock()


func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	coast_drawer = CoastDrawer.new(rect_size, COAST_MIN_EXTENT, COAST_MAX_EXTENT)
	coast_drawer.draw_points(image)
	
	image_filler = ImageFiller.new(rect_size, LAND_COLOR, SEA_COLOR)
	
	ready = true

func _process(_delta) -> void:
	
	if not ready:
		return
	
	if not points_done:
		imageTexture.create_from_image(image)
		texture = imageTexture
		points_done = coast_drawer.process_sub_points()
		image.fill(SEA_COLOR)
		coast_drawer.draw_points(image)
		if points_done:
			river_path_maker = RiverPathMaker.new(rect_size, coast_drawer._river_mouth_list)
			coast_image_step.copy_from(image)
		return
	
	if not rivers_done:
		print("doing rivers")
		rivers_done = river_path_maker.process_sub_points()
		image.copy_from(coast_image_step)
		river_path_maker.draw_points(image)
		return
	
	if not fill_done:
		fill_done = image_filler.fill_from_center(image)
		if fill_done:
			inland_distancer = InlandDistancer.new(image_filler._edge_point_pool)
		imageTexture.create_from_image(image)
		texture = imageTexture
		return
	
	if not distance_done:
		distance_done = inland_distancer.raise_inland(image)
		imageTexture.create_from_image(image)
		texture = imageTexture
		return
	
