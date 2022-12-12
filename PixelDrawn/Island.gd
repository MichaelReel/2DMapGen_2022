extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false
onready var points_done := false
onready var fill_done := false
onready var distance_done := false
onready var rivers_done := false

const SEA_COLOR := Color8(32, 32, 128, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)
const COAST_START_DIR : float = 0.0
const MAX_POINT_SPACE : float = 3.0
const MAX_POINT_SPACE_SQR : float = MAX_POINT_SPACE * MAX_POINT_SPACE
const POINT_INSERT_RATIO : float = 0.7
const FILL_DIRS : Array = [
	Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT
]

var coast_drawer : CoastDrawer
var image_filler : ImageFiller
var inland_distancer : InlandDistancer


class CoastDrawer:
	var _angle : float = 0.0
	var _rect_size : Vector2
	var _center : Vector2
	var _min_ratio : float
	var _max_ratio : float
	var _point_list : PoolVector2Array
	var _rng : RandomNumberGenerator
	
	func _init(rect_size : Vector2, min_ratio: float, max_ratio: float) -> void:
		_rect_size = rect_size
		_center = rect_size / 2.0
		_min_ratio = min_ratio
		_max_ratio = max_ratio
		_rng = RandomNumberGenerator.new()
#		_rng.seed = hash("island")
		_rng.seed = OS.get_system_time_msecs()
		_point_list = _get_initial_points()
	
	func _get_initial_points() -> PoolVector2Array:
		var angle := 0.0
		var point_list := PoolVector2Array()
		while angle < PI * 2:
			point_list.append(_get_point_at_angle(angle))
			angle += 0.25 * PI
		point_list.append(point_list[0])
		return point_list
	
	func _get_point_at_angle(angle: float) -> Vector2:
		var ratio = lerp(_min_ratio, _max_ratio, _rng.randf()) * 0.5
		var width_ratio = _rect_size.x * ratio
		var height_ratio = _rect_size.y * ratio
		var point : Vector2 = Vector2(
			cos(angle) * width_ratio, sin(angle) * height_ratio
		) + _center
		return point
	
	func process_sub_points() -> bool:
		var acted = false
		var new_point_list := PoolVector2Array()
		for i in range(_point_list.size() - 1):
			var a : Vector2 = _point_list[i]
			var b : Vector2 = _point_list[i + 1]
			new_point_list.append(a)
			if a.distance_squared_to(b) >= MAX_POINT_SPACE_SQR:
				var new_point : Vector2 = _get_point_between(a, b)
				new_point_list.append(new_point)
				acted = true
		
		new_point_list.append(new_point_list[0])
		_point_list = new_point_list
		return acted
	
	func _get_point_between(a: Vector2, b: Vector2) -> Vector2:
		var mid_point = lerp(a, b, 0.5)
		var tangent = (b - a).tangent()
		return mid_point + tangent * (_rng.randf() - 0.5) * POINT_INSERT_RATIO
	
	func draw_points(image: Image) -> void:
		image.lock()
		for i in range(_point_list.size() - 1):
			var a = _point_list[i]
			var b = _point_list[i + 1]
			draw_line(image, a, b, COAST_COLOR)
		image.unlock()
	
	func draw_line(image: Image, a: Vector2, b: Vector2, col: Color):
		var longest_side = int(max(abs(a.x - b.x), abs(a.y - b.y))) + 1
		for p in range(longest_side):
			var t = (1.0 / longest_side) * p
			image.set_pixelv(lerp(a, b, t), col)


class ImageFiller:
	var _fill_point_pool : Array
	var _fill_color : Color
	var _replace_color : Color
	var _edge_point_pool : Array
	
	func _init(rect_size : Vector2, fill_color: Color, replace_color: Color) -> void:
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
			var point : Vector2 = _fill_point_pool.pop_front()
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


class InlandDistancer:
	var _edge_point_pool
	var _next_level_pool
	var _low_color : Color = Color8(0, 140, 0, 255)
	var _high_color : Color = Color8(255, 140, 255, 255)
	var _height : float = 0.0
	var _per_level : float = 1.0 / 256.0
	
	func _init(edge_points: Array) -> void:
		_edge_point_pool = edge_points
		_next_level_pool = []
	
	func raise_inland(image: Image) -> bool:
		if _edge_point_pool.empty():
			return true
			
		var frame_end = OS.get_ticks_msec() + 30
		image.lock()
		
		while OS.get_ticks_msec() < frame_end and not _edge_point_pool.empty():
			var point : Vector2 = _edge_point_pool.pop_front()
			
			image.set_pixelv(point, lerp(_low_color, _high_color, _height))
			for dir in FILL_DIRS:
				var neighbour = point + dir
				var neighbour_color = image.get_pixelv(neighbour)
				# TODO: Kind of feel like LAND_COLOR should be local
				if neighbour_color.is_equal_approx(LAND_COLOR) and not _next_level_pool.has(neighbour):
					_next_level_pool.append(neighbour)
			
			if _edge_point_pool.empty():
				_edge_point_pool = _next_level_pool
				_next_level_pool = []
				_height += _per_level
		
		image.unlock()
		return false


class RiverPathMaker:
	var _mouth_point_pool : Array
	
	func _init(mouth_point_pool : Array) -> void:
		_mouth_point_pool = mouth_point_pool


func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	coast_drawer = CoastDrawer.new(rect_size, 0.5, 0.8)
	coast_drawer.draw_points(image)
	
	image_filler = ImageFiller.new(rect_size, LAND_COLOR, SEA_COLOR)
	
	ready = true

func _process(_delta) -> void:
	if not ready:
		return
	
	if not points_done:
		imageTexture.create_from_image(image)
		texture = imageTexture
		points_done = not coast_drawer.process_sub_points()
		image.fill(SEA_COLOR)
		coast_drawer.draw_points(image)
		return
	
	if not fill_done:
		fill_done = image_filler.fill_from_center(image)
		if fill_done:
			inland_distancer = InlandDistancer.new(image_filler._edge_point_pool)
			print (str(inland_distancer._edge_point_pool.size()))
		imageTexture.create_from_image(image)
		texture = imageTexture
		return

	if not distance_done:
		distance_done = inland_distancer.raise_inland(image)
		imageTexture.create_from_image(image)
		texture = imageTexture
		return
	
	if not rivers_done:
		print("doing rivers")
		rivers_done = true
