extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false

const CELL_EDGE := 256.0
const SEA_COLOR := Color8(32, 32, 128, 255)
const GRID_COLOR := Color8(40, 40, 136, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)

var base_grid : BaseGrid


class BaseConnection:
	var _other : BasePoint
	var _line : BaseLine
	
	func _init(other: BasePoint, line: BaseLine) -> void:
		_other = other
		_line = line


class BasePoint:
	var _pos : Vector2
	var _connections : Array
	
	func _init(x : float, y : float) -> void:
		_pos = Vector2(x, y)
		_connections = []
		
	func add_connection(other: BasePoint, line: BaseLine) -> void:
		_connections.append(BaseConnection.new(other, line))


class BaseLine:
	var _a : BasePoint
	var _b : BasePoint
	
	func _init(a: BasePoint, b: BasePoint) -> void:
		_a = a
		_b = b

	func shared_point(other: BaseLine) -> BasePoint:
		if self._a == other._a or self._a == other._b:
			return self._a
		elif self._b == other._a or self._b == other._b:
			return _b
		else:
			return BasePoint.new(0.0, 0.0)
		

class BaseTriangle:
	var _points : Array
	var _lines : Array
	
	func _init(a: BaseLine, b: BaseLine, c: BaseLine) -> void:
		_lines = [a, b, c]
		_points = [a.shared_point(b), a.shared_point(c), b.shared_point(c)]


class BaseGrid:
	var grid_points : Array = []
	var grid_lines : Array = []
	var grid_tris : Array = []
	
	func _init(edge_size: float, rect_size: Vector2) -> void:
		var tri_side = edge_size
		var tri_height = sqrt(0.75 * (tri_side * tri_side))
#		 |\       h^2 + (s/2)^2 = s^2
#		 | \s     h^2 = s^2 - (s/2)^2
#		h|  \     h^2 = s^2 - (s^2 / 4)
#		 |___\    h^2 = (1 - 1/4) * s^2
#		  s/2     h^2 = ( 3/4 * s^2 )
		
		var row_ind : int = 0
		for y in range (0.0 + tri_height, rect_size.y, tri_height):
			var points_row : Array = []
			var ind_offset : int = (row_ind % 2) * 2 - 1
			var offset : float = (row_ind % 2) * (tri_side / 2.0)
			var col_ind : int = 0
			for x in range(offset + (tri_side / 2.0), rect_size.x, tri_side):
				var new_point = BasePoint.new(x, y)
				var lines := []
				points_row.append(new_point)
				# Connect from the left
				if col_ind > 0:
					var existing_point : BasePoint = points_row[col_ind - 1]
					lines.append(_add_grid_line(existing_point, new_point))
				# Connect from above (the simpler way - left or right depends on row)
				if row_ind > 0 and col_ind < grid_points[row_ind - 1].size():
					var existing_point = grid_points[row_ind - 1][col_ind]
					lines.append(_add_grid_line(existing_point, new_point))
				# Connect from above (the other way)
				if row_ind > 0 and col_ind + ind_offset >= 0 and col_ind + ind_offset < grid_points[row_ind - 1].size():
					var existing_point = grid_points[row_ind - 1][col_ind + ind_offset]
					lines.append(_add_grid_line(existing_point, new_point))
		
				
				# Lol, no! We're not drawing triangles above - we have 3 lines to a point:
#				if lines.size() == 3:
#					grid_tris.append(BaseTriangle.new(lines[0], lines[1], lines[2]))
					
				col_ind += 1
			grid_points.append(points_row)
			row_ind += 1
	
	func _add_grid_line(a: BasePoint, b: BasePoint) -> BaseLine:
		var new_line := BaseLine.new(a, b)
		a.add_connection(b, new_line)
		b.add_connection(a, new_line)
		grid_lines.append(new_line)
		return new_line
	
	static func draw_line_on_image(image: Image, a: Vector2, b: Vector2, col: Color) -> void:
		var longest_side = int(max(abs(a.x - b.x), abs(a.y - b.y))) + 1
		for p in range(longest_side):
			var t = (1.0 / longest_side) * p
			image.set_pixelv(lerp(a, b, t), col)
	
	func draw_grid(image: Image, color: Color) -> void:
		image.lock()
		
		for line in grid_lines:
			draw_line_on_image(image, line._a._pos, line._b._pos, color)

		for tri in grid_tris:
			draw_line_on_image(image, tri._points[0]._pos, tri._points[1]._pos, COAST_COLOR)
#			draw_line_on_image(image, tri._points[1]._pos, tri._points[2]._pos, RIVER_COLOR)
#			draw_line_on_image(image, tri._points[0]._pos, tri._points[2]._pos, LAND_COLOR)
		image.unlock()



func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	base_grid = BaseGrid.new(CELL_EDGE, rect_size)
	
	ready = true

func _process(_delta) -> void:
	
	if not ready:
		return
	
	base_grid.draw_grid(image, GRID_COLOR)
	imageTexture.create_from_image(image)
	texture = imageTexture
	

