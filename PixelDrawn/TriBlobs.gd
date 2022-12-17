extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false

const CELL_EDGE := 32.0
const SEA_COLOR := Color8(32, 32, 128, 255)
const GRID_COLOR := Color8(40, 40, 136, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)


var base_grid: BaseGrid
var tri_blob: TriBlob


class BasePoint:
	var _pos: Vector2
	var _connections: Array
	
	func _init(x: float, y: float) -> void:
		_pos = Vector2(x, y)
		_connections = []
		
	func add_connection(line: BaseLine) -> void:
		_connections.append(line)
	
	static func sort_vert_hortz(a: BasePoint, b: BasePoint) -> bool:
		if a._pos.y < b._pos.y:
			return true
		elif a._pos.y == b._pos.y and a._pos.x < b._pos.x:
				return true
		return false
	
	func equals(other: BasePoint) -> bool:
		return self._pos == other._pos
	
	func higher_connections() -> Array:
		# Return connection lines to "higher" points
		var higher_conns = []
		for con in _connections:
			var other = con.other_point(self)
			if sort_vert_hortz(self, other):
				higher_conns.append(con)
		return higher_conns

	func higher_connections_to_point(point) -> Array:
		# Return connection lines to "higher" points that connect to a given point
		var higher_conns = []
		for con in _connections:
			var other = con.other_point(self)
			if sort_vert_hortz(self, other):
				if other.has_connection_to_point(point):
					higher_conns.append(con)
		return higher_conns

	func has_connection_to_point(point) -> bool:
		for con in _connections:
			if con.other_point(self) == point:
				return true
		return false

	func connection_to_point(point) -> BaseLine:
		for con in _connections:
			if con.other_point(self) == point:
				return con
		return BaseLine.error()
	
	func error() -> BasePoint:
		printerr("Something needed a placeholder BasePoint")
		return BasePoint.new(0.0, 0.0)


class BaseLine:
	var _a: BasePoint
	var _b: BasePoint
	var _borders: Array
	
	func _init(a: BasePoint, b: BasePoint) -> void:
		if BasePoint.sort_vert_hortz(a, b):
			_a = a
			_b = b
		else:
			_a = b
			_b = a
		_borders = []

	func shared_point(other: BaseLine) -> BasePoint:
		if self._a == other._a or self._a == other._b:
			return self._a
		elif self._b == other._a or self._b == other._b:
			return _b
		else:
			return BasePoint.error()
	
	func other_point(this: BasePoint) -> BasePoint:
		if this == _a:
			return _b
		return _a
	
	static func sort_vert_hortz(a: BaseLine, b: BaseLine) -> bool:
		if BasePoint.sort_vert_hortz(a._a, b._a):
			return true
		elif a._a.equals(b._a) and BasePoint.sort_vert_hortz(a._b, b._b):
			return true
		return false
	
	func error() -> BaseLine:
		printerr("Something needed a placeholder BaseLine")
		return BaseLine.new(BasePoint.new(0.0, 0.0), BasePoint.new(0.0, 0.0))
	
	func set_border_of(triangle: BaseTriangle) -> void:
		_borders.append(triangle)
	
	func get_bordering_triangles() -> Array:
		return _borders


class BaseTriangle:
	var _points: Array
	var _edges: Array
	var _neighbours: Array
	
	func _init(a: BaseLine, b: BaseLine, c: BaseLine) -> void:
		_points = [a.shared_point(b), a.shared_point(c), b.shared_point(c)]
		_points.sort_custom(BasePoint, "sort_vert_hortz")
		_edges = [a, b, c]
		for edge in _edges:
			edge.set_border_of(self)

	func update_neighbours_from_edges() -> void:
		for edge in _edges:
			for tri in edge.get_bordering_triangles():
				if tri != self:
					_neighbours.append(tri)
	
	func get_points() -> Array:
		return _points


class BaseGrid:
	var _grid_points: Array = []
	var _grid_lines: Array = []
	var _grid_tris: Array = []
	
	func _init(edge_size: float, rect_size: Vector2) -> void:
		var tri_side = edge_size
		var tri_height = sqrt(0.75 * (tri_side * tri_side))
#		 |\       h^2 + (s/2)^2 = s^2
#		 | \s     h^2 = s^2 - (s/2)^2
#		h|  \     h^2 = s^2 - (s^2 / 4)
#		 |___\    h^2 = (1 - 1/4) * s^2
#		  s/2     h^2 = ( 3/4 * s^2 )
		
		var row_ind: int = 0
		for y in range (0.0 + tri_height, rect_size.y, tri_height):
			var points_row: Array = []
			var ind_offset: int = (row_ind % 2) * 2 - 1
			var offset: float = (row_ind % 2) * (tri_side / 2.0)
			var col_ind: int = 0
			for x in range(offset + (tri_side / 2.0), rect_size.x, tri_side):
				var new_point = BasePoint.new(x, y)
				var lines := []
				points_row.append(new_point)
				# Connect from the left
				if col_ind > 0:
					var existing_point: BasePoint = points_row[col_ind - 1]
					lines.append(_add_grid_line(existing_point, new_point))
				# Connect from above (the simpler way - left or right depends on row)
				if row_ind > 0 and col_ind < _grid_points[row_ind - 1].size():
					var existing_point = _grid_points[row_ind - 1][col_ind]
					lines.append(_add_grid_line(existing_point, new_point))
				# Connect from above (the other way)
				if row_ind > 0 and col_ind + ind_offset >= 0 and col_ind + ind_offset < _grid_points[row_ind - 1].size():
					var existing_point = _grid_points[row_ind - 1][col_ind + ind_offset]
					lines.append(_add_grid_line(existing_point, new_point))
				
				col_ind += 1
			_grid_points.append(points_row)
			row_ind += 1
		
		# Go through the points and create triangles "upstream"
		# I.e.: Triangles together with points only greater than the current point
		for row in _grid_points:
			for point in row:
				# Get connections, find connects between higher points
				for first_line in point.higher_connections():
					var second_point: BasePoint = first_line.other_point(point)
					for second_line in second_point.higher_connections_to_point(point):
						var third_point: BasePoint = second_line.other_point(second_point)
						var third_line: BaseLine = third_point.connection_to_point(point)
						_grid_tris.append(BaseTriangle.new(first_line, second_line, third_line))
		
		for tri in _grid_tris:
			tri.update_neighbours_from_edges()
	
	func _add_grid_line(a: BasePoint, b: BasePoint) -> BaseLine:
		var new_line := BaseLine.new(a, b)
		a.add_connection(new_line)
		b.add_connection(new_line)
		_grid_lines.append(new_line)
		return new_line
	
	static func draw_line_on_image(image: Image, a: Vector2, b: Vector2, col: Color) -> void:
		var longest_side = int(max(abs(a.x - b.x), abs(a.y - b.y))) + 1
		for p in range(longest_side):
			var t = (1.0 / longest_side) * p
			image.set_pixelv(lerp(a, b, t), col)
	
	func draw_grid(image: Image, color: Color) -> void:
		image.lock()
		
		for line in _grid_lines:
			draw_line_on_image(image, line._a._pos, line._b._pos, color)
		image.unlock()
	
	func get_triangles() -> Array:
		return _grid_tris


class TriBlob:
	var _grid: BaseGrid
	var _start: BaseTriangle
	
	func _init(grid: BaseGrid):
		_grid = grid
		var tris = grid.get_triangles()
		_start = tris[randi() % len(tris)]
	
	static func draw_triangle_on_image(image: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
		BaseGrid.draw_line_on_image(image, a, b, color)
		BaseGrid.draw_line_on_image(image, a, c, color)
		BaseGrid.draw_line_on_image(image, b, c, color)
	
	func draw_triangles(image: Image, color: Color) -> void:
		image.lock()
		var points := _start.get_points()
		draw_triangle_on_image(image, points[0]._pos, points[1]._pos, points[2]._pos, color)
		image.unlock()


func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	base_grid = BaseGrid.new(CELL_EDGE, rect_size)
	tri_blob = TriBlob.new(base_grid)
	
	ready = true

func _process(_delta) -> void:
	
	if not ready:
		return
	
	base_grid.draw_grid(image, GRID_COLOR)
	tri_blob.draw_triangles(image, LAND_COLOR)
	imageTexture.create_from_image(image)
	texture = imageTexture
	

