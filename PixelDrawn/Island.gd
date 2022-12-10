extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false

const SEA_COLOR := Color8(32, 32, 128, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const COAST_START_DIR : float = 0.0

var coast_drawer : CoastDrawer


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
		_rng.seed = hash("island")
		_point_list = _get_points()
	
	func _get_points() -> PoolVector2Array:
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


func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	coast_drawer = CoastDrawer.new(rect_size, 0.5, 0.95)
	
	coast_drawer.draw_points(image)
	
	ready = true


func _process(_delta) -> void:
	if not ready:
		return

#	var imageTexture := ImageTexture.new()
	imageTexture.create_from_image(image)
	texture = imageTexture
