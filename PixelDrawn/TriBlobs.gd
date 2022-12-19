extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var rng := RandomNumberGenerator.new()
onready var ready := false
onready var blob_done := false
onready var edges_done := false

const CELL_EDGE := 32.0
const SEA_COLOR := Color8(32, 32, 128, 255)
const GRID_COLOR := Color8(40, 40, 136, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)
const CURSOR_COLOR := Color8(128, 32, 128, 255)
const FRAME_TIME_MILLIS := 30

var base_grid: BaseGrid
var land_blob: TriBlob
var mouse_tracker: MouseTracker


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
	
	func get_pos() -> Vector2:
		return _pos


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
	
	func draw_line_on_image(image: Image, col: Color) -> void:
		var a := _a.get_pos()
		var b := _b.get_pos()
		var longest_side = int(max(abs(a.x - b.x), abs(a.y - b.y))) + 1
		for p in range(longest_side):
			var t = (1.0 / longest_side) * p
			image.set_pixelv(lerp(a, b, t), col)

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
	var _parent: Object = null
	var _pos: Vector2
	
	func _init(a: BaseLine, b: BaseLine, c: BaseLine) -> void:
		_points = [a.shared_point(b), a.shared_point(c), b.shared_point(c)]
		_points.sort_custom(BasePoint, "sort_vert_hortz")
		_edges = [a, b, c]
		for edge in _edges:
			edge.set_border_of(self)
		_pos = (_points[0]._pos + _points[1]._pos + _points[2]._pos) / 3.0

	func update_neighbours_from_edges() -> void:
		for edge in _edges:
			for tri in edge.get_bordering_triangles():
				if tri != self:
					_neighbours.append(tri)
	
	func get_points() -> Array:
		return _points
	
	func get_parent() -> Object:
		return _parent
	
	func get_pos() -> Vector2:
		return _pos
	
	func set_parent(parent: Object) -> void:
		_parent = parent

	func get_neighbours_with_parent(parent: Object) -> Array:
		var parented_neighbours = []
		for neighbour in _neighbours:
			if neighbour.get_parent() == parent:
				parented_neighbours.append(neighbour)
		return parented_neighbours
	
	func get_neighbour_borders_with_parent(parent: Object) -> Array:
		var borders : Array = []
		for edge in _edges:
			for tri in edge.get_bordering_triangles():
				if tri != self and tri.get_parent() == parent:
					borders.append(edge)
		return borders
		
	func is_on_field_boundary() -> bool:
		return len(_neighbours) < len(_edges)
	
	func get_edges_on_field_boundary() -> Array:
		var boundary_edges : Array = []
		for edge in _edges:
			if len(edge.get_bordering_triangles()) == 1:
				boundary_edges.append(edge)
		return boundary_edges
	
	func count_neighbours_with_parent(parent: Object) -> int:
		return get_neighbours_with_parent(parent).size()
	
	func get_neighbours_no_parent() -> Array:
		return get_neighbours_with_parent(null)
	
	func draw_triangle_on_image(image: Image, color: Color) -> void:
		for line in _edges:
			line.draw_line_on_image(image, color)

	func get_closest_neighbour_to(point: Vector2) -> BaseTriangle:
		var closest = _neighbours[0]
		var current_sqr_dist = point.distance_squared_to(closest.get_pos())
		for neighbour in _neighbours.slice(1, _neighbours.size()):
			var next_sqr_dist = point.distance_squared_to(neighbour.get_pos())
			if next_sqr_dist < current_sqr_dist:
				closest = neighbour
				current_sqr_dist = next_sqr_dist
		return closest


class BaseGrid:
	var _grid_points: Array = []  # Array of rows of points
	var _grid_lines: Array = []
	var _grid_tris: Array = []
	var _cell_count: int = 0
	
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
			var tri_row : Array = []
			for point in row:
				# Get connections, find connects between higher points
				for first_line in point.higher_connections():
					var second_point: BasePoint = first_line.other_point(point)
					for second_line in second_point.higher_connections_to_point(point):
						var third_point: BasePoint = second_line.other_point(second_point)
						var third_line: BaseLine = third_point.connection_to_point(point)
						tri_row.append(BaseTriangle.new(first_line, second_line, third_line))
						_cell_count += 1
			if not tri_row.empty():
				_grid_tris.append(tri_row)
		
		for tri_row in _grid_tris:
			for tri in tri_row:
				tri.update_neighbours_from_edges()
	
	func _add_grid_line(a: BasePoint, b: BasePoint) -> BaseLine:
		var new_line := BaseLine.new(a, b)
		a.add_connection(new_line)
		b.add_connection(new_line)
		_grid_lines.append(new_line)
		return new_line
	
	func draw_grid(image: Image, color: Color) -> void:
		image.lock()
		
		for line in _grid_lines:
			line.draw_line_on_image(image, color)
		image.unlock()
	
	func get_cell_count() -> int:
		return _cell_count
	
	func get_middle_triangle() -> BaseTriangle:
		var mid_row = _grid_tris[_grid_tris.size() / 2]
		return mid_row[mid_row.size() / 2]
	
	func get_nearest_triangle_to(point: Vector2) -> BaseTriangle:
		# What are the coords again?
		# For now: Just find a nearish one, then follow the neighbours until we get there
		var nearest : BaseTriangle = get_middle_triangle()
		var current_sqr_dist : float = point.distance_squared_to(nearest.get_pos())
		var next_nearest : = nearest.get_closest_neighbour_to(point)
		var next_sqr_dist : float = point.distance_squared_to(next_nearest.get_pos())
		while point.distance_squared_to(next_nearest.get_pos()) < current_sqr_dist:
			nearest = next_nearest
			current_sqr_dist = next_sqr_dist
			next_nearest = nearest.get_closest_neighbour_to(point)
			next_sqr_dist = point.distance_squared_to(next_nearest.get_pos())
		return nearest


class TriBlob:
	var _grid: BaseGrid
	var _cells: Array
	var _rng: RandomNumberGenerator
	var _cell_limit: int
	var _blob_front: Array
	var _perimeter: Array
	
	func _init(grid: BaseGrid, rng: RandomNumberGenerator, cell_limit: int = 1):
		_grid = grid
		_cells = []
		_rng = rng
		_cell_limit = cell_limit
		_blob_front = []
		_perimeter = []
		var start = grid.get_middle_triangle()
		add_triangle_as_cell(start)
	
	func add_triangle_as_cell(triangle: BaseTriangle) -> void:
		triangle.set_parent(self)
		_cells.append(triangle)
		# Remove this one from the _blob_front
		if triangle in _blob_front:
			_blob_front.erase(triangle)  # Not a super fast action
		# Add neighbours to _blob_front
		for neighbour in triangle.get_neighbours_no_parent():
			if not neighbour in _blob_front:
				_blob_front.append(neighbour)
			
		if triangle.is_on_field_boundary():
			_perimeter.append_array(triangle.get_edges_on_field_boundary())
	
	func draw_triangles(image: Image, color: Color) -> void:
		image.lock()
		for cell in _cells:
			cell.draw_triangle_on_image(image, color)
		image.unlock()
	
	func get_perimeter_lines() -> Array:
		# using the _blob_front, get all the lines joining to parented cells
		while not _blob_front.empty():
			var outer_triangle = _blob_front.pop_back()
			var borders : Array = outer_triangle.get_neighbour_borders_with_parent(self)
			if borders.size() >= 3:
				# Assimilate surrounded cells
				_cells.append(outer_triangle)
			else:
				_perimeter.append_array(borders)
				
		return _perimeter
	
	func draw_perimeter_lines(image: Image, color: Color) -> void:
		image.lock()
		for line in get_perimeter_lines():
			line.draw_line_on_image(image, color)
		image.unlock()
	
	func expand_tick() -> bool:
		if _cells.size() >= _cell_limit:
			return true
		
		var frame_end = OS.get_ticks_msec() + FRAME_TIME_MILLIS
		
		while OS.get_ticks_msec() < frame_end and _cells.size() < _cell_limit:
			_blob_front.shuffle()  # Note: uses the global rng
			add_triangle_as_cell(_blob_front.back())
		
		return false
	

class MouseTracker:
	var _grid: BaseGrid
	var _mouse_coords: Vector2
	
	func _init(grid: BaseGrid) -> void:
		_grid = grid
	
	func update_mouse_coords(mouse_coords) -> void:
		_mouse_coords = mouse_coords
	
	func draw_triangle_closest_to_mouse(image: Image, color: Color) -> void:
		image.lock()
		var triangle: BaseTriangle = _grid.get_nearest_triangle_to(_mouse_coords)
		triangle.draw_triangle_on_image(image, color)
		image.unlock()


func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
#	rng.seed = hash("island")
	rng.seed = OS.get_system_time_msecs()
	
	base_grid = BaseGrid.new(CELL_EDGE, rect_size)
	mouse_tracker = MouseTracker.new(base_grid)
	
	var island_cells_target : int = (base_grid.get_cell_count() / 2)

	land_blob = TriBlob.new(base_grid, rng, island_cells_target)
	
	ready = true

func _process(_delta) -> void:
	
	if not ready:
		pass
	
	elif not blob_done:
		blob_done = land_blob.expand_tick()
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
	
	elif not edges_done:
		edges_done = true
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
	
	else:
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		mouse_tracker.update_mouse_coords(get_viewport().get_mouse_position())
		mouse_tracker.draw_triangle_closest_to_mouse(image, CURSOR_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
