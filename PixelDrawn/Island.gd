extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false
onready var points_done := false
onready var fill_done := false

const SEA_COLOR := Color8(32, 32, 128, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)
const COAST_START_DIR : float = 0.0
const MAX_POINT_SPACE : float = 3.0
const MAX_POINT_SPACE_SQR : float = MAX_POINT_SPACE * MAX_POINT_SPACE
const POINT_INSERT_RATIO : float = 0.9
const FILL_DIRS : Array = [
	Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT
]

var coast_drawer : CoastDrawer
var image_filler : ImageFiller


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
	
	func _init(rect_size : Vector2, fill_color: Color):
		_fill_point_pool = [rect_size / 2.0]
		_fill_color = fill_color
	
	func fill_from_center(fill_image: Image) -> bool:
		if _fill_point_pool.empty():
			return true
		
		fill_image.lock()
		
		var point : Vector2 = _fill_point_pool.pop_front()
		if _fill_point_pool.empty():
			_replace_color = fill_image.get_pixelv(point)
		
		fill_image.set_pixelv(point, _fill_color)
		
		for dir in FILL_DIRS:
			var neighbour = point + dir
			var neighbour_color = fill_image.get_pixelv(neighbour)
			if neighbour_color.is_equal_approx(_replace_color):
				fill_image.set_pixelv(neighbour, _fill_color)
				_fill_point_pool.push_back(neighbour)
		
		fill_image.unlock()
		return false

func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	coast_drawer = CoastDrawer.new(rect_size, 0.5, 0.8)
	coast_drawer.draw_points(image)
	
	image_filler = ImageFiller.new(rect_size, LAND_COLOR)
	
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
		yield(VisualServer, "frame_post_draw")
		fill_done = image_filler.fill_from_center(image)
		imageTexture.create_from_image(image)
		texture = imageTexture
		return
