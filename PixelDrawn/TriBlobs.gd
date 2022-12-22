extends TextureRect

onready var status_label := $RichTextLabel
onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var rng := RandomNumberGenerator.new()
onready var ready := false
onready var blob_done := false
onready var edges_done := false
onready var regions_done := false
onready var borders_done := false

const CELL_EDGE := 16.0
const SEA_COLOR := Color8(32, 32, 64, 255)
const GRID_COLOR := Color8(40, 40, 96, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)
const CURSOR_COLOR := Color8(128, 32, 128, 255)

const REGION_COLORS := [
	Color8(  0,   0, 192, 255),
	Color8(  0, 192,   0, 255),
	Color8(192,   0,   0, 255),
	Color8(  0, 192, 192, 255),
	Color8(192, 192,   0, 255),
	Color8(192,   0, 192, 255),
]

const FRAME_TIME_MILLIS := 30

var base_grid: BaseGrid
var land_blob: TriBlob
var mouse_tracker: MouseTracker
var region_manager: RegionManager


class BasePoint:
	var _pos: Vector2
	var _connections: Array
	var _polygons: Array
	
	func _init(x: float, y: float) -> void:
		_pos = Vector2(x, y)
		_connections = []
		
	func add_connection(line: BaseLine) -> void:
		_connections.append(line)
	
	func add_polygon(polygon: BaseTriangle) -> void:
		if not polygon in _polygons:
			_polygons.append(polygon)
	
	static func sort_vert_hortz(a: BasePoint, b: BasePoint) -> bool:
		"""This will sort by Y desc, then X asc"""
		if a._pos.y > b._pos.y:
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
	
	func get_cornering_triangles() -> Array:
		return _polygons
		
	func _get_line_ids() -> String:
		var ids_string : String = ""
		var first := true
		for line in _connections:
			ids_string += "" if first else ", "
			first = false
			ids_string += "%d" % line.get_instance_id()
		return ids_string
	
	func _to_string() -> String:
		return "%d: %s: { %s }" % [get_instance_id(), _pos, _get_line_ids()]


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
	
	func _to_string() -> String:
		return "%d: { %d -> %d }" % [get_instance_id(), _a.get_instance_id(), _b.get_instance_id()]


class BaseTriangle:
	var _points: Array
	var _edges: Array
	var _neighbours: Array
	var _corner_neighbours: Array
	var _parent: Object = null
	var _pos: Vector2
	var _index_row: int
	var _index_col: int
	
	func _init(a: BaseLine, b: BaseLine, c: BaseLine, index_col: int, index_row: int) -> void:
		_points = [a.shared_point(b), a.shared_point(c), b.shared_point(c)]
		_points.sort_custom(BasePoint, "sort_vert_hortz")
		_index_col = index_col
		_index_row = index_row
		_edges = [a, b, c]
		for point in _points:
			point.add_polygon(self)
		for edge in _edges:
			edge.set_border_of(self)
		_pos = (_points[0]._pos + _points[1]._pos + _points[2]._pos) / 3.0

	func update_neighbours_from_edges() -> void:
		for edge in _edges:
			for tri in edge.get_bordering_triangles():
				if tri != self:
					_neighbours.append(tri)
		for point in _points:
			for tri in point.get_cornering_triangles():
				if not tri in _neighbours and not tri in _corner_neighbours and not tri == self:
					_corner_neighbours.append(tri)
	
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

	func get_corner_neighbours_with_parent(parent: Object) -> Array:
		var parented_corner_neighbours = []
		for corner_neighbour in _corner_neighbours:
			if corner_neighbour.get_parent() == parent:
				parented_corner_neighbours.append(corner_neighbour)
		return parented_corner_neighbours
	
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
	
	func count_corner_neighbours_with_parent(parent: Object) -> int:
		return get_corner_neighbours_with_parent(parent).size()
	
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
	
	func _get_neighbour_ids() -> String:
		var neighbour_ids : String = ""
		var first := true
		for neighbour in _neighbours:
			neighbour_ids += "\n  " if first else ",\n  "
			first = false
			neighbour_ids += "%d" % neighbour.get_instance_id()
		return neighbour_ids
	
	func _get_corner_neighbour_ids() -> String:
		var corner_neighbour_ids : String = ""
		var first := true
		for corner_neighbour in _corner_neighbours:
			corner_neighbour_ids += "\n  " if first else ",\n  "
			first = false
			corner_neighbour_ids += "%d" % corner_neighbour.get_instance_id()
		return corner_neighbour_ids

	func get_status() -> String:
		var status : String = ""
		status += "%d (%d, %d) %s\n" % [ get_instance_id(), _index_col, _index_row, _pos ]
		status += "Corner Neighbours: [%s\n]" % _get_corner_neighbour_ids()
		status += "Edge Neighbours: [%s\n]" % _get_neighbour_ids()
		status += "Lines: [\n  %s,\n  %s,\n  %s\n]\n" % _edges
		status += "Points: [\n  %s,\n  %s,\n  %s\n]\n" % _points
		status += "Parent: %s" % _parent
		return status

class BaseGrid:
	var _tri_side: float
	var _tri_height: float
	var _grid_points: Array = []  # Array of rows of points
	var _grid_lines: Array = []
	var _grid_tris: Array = []
	var _cell_count: int = 0
	
	func _init(edge_size: float, rect_size: Vector2) -> void:
		_tri_side = edge_size
		_tri_height = sqrt(0.75 * (_tri_side * _tri_side))
#		 |\       h^2 + (s/2)^2 = s^2
#		 | \s     h^2 = s^2 - (s/2)^2
#		h|  \     h^2 = s^2 - (s^2 / 4)
#		 |___\    h^2 = (1 - 1/4) * s^2
#		  s/2     h^2 = ( 3/4 * s^2 )
		
		# Lay out points and connect them to any existing points
		var row_ind: int = 0
		for y in range (0.0 + _tri_height, rect_size.y, _tri_height):
			var points_row: Array = []
			var ind_offset: int = (row_ind % 2) * 2 - 1
			var offset: float = (row_ind % 2) * (_tri_side / 2.0)
			var col_ind: int = 0
			for x in range(offset + (_tri_side / 2.0), rect_size.x, _tri_side):
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
		var tri_row_ind : int = 0
		for row in _grid_points:
			var tri_row : Array = []
			var tri_col_ind : int = 0
			for point in row:
				# Get connections, find connects between higher points
				for first_line in point.higher_connections():
					var second_point: BasePoint = first_line.other_point(point)
					for second_line in second_point.higher_connections_to_point(point):
						var third_point: BasePoint = second_line.other_point(second_point)
						var third_line: BaseLine = third_point.connection_to_point(point)
						tri_row.append(BaseTriangle.new(first_line, second_line, third_line, tri_col_ind, tri_row_ind))
						_cell_count += 1
						tri_col_ind += 1
			if not tri_row.empty():
				_grid_tris.append(tri_row)
				tri_row_ind += 1
		
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
		var grid_row = int((point.y - _tri_height) / _tri_height)
		grid_row = min(grid_row, len(_grid_tris) - 1)
		var row_pos = int((point.x - _tri_side / 2.0) / _tri_side)
		row_pos = min(row_pos, len(_grid_tris[grid_row]) - 1)
		
		
		var nearest : BaseTriangle = _grid_tris[grid_row][row_pos]
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
	
	func get_some_triangles(count: int) -> Array:
		"""This *could* be random, but for now will use the last added triangles"""
		return _cells.slice(len(_cells)-count, len(_cells)-1)
	
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
	var _status_label: RichTextLabel
	
	func _init(grid: BaseGrid, status_label: RichTextLabel) -> void:
		_grid = grid
		_status_label = status_label
	
	func update_mouse_coords(mouse_coords) -> void:
		_mouse_coords = mouse_coords
	
	func draw_triangle_closest_to_mouse(image: Image, color: Color) -> void:
		image.lock()
		var triangle: BaseTriangle = _grid.get_nearest_triangle_to(_mouse_coords)
		triangle.draw_triangle_on_image(image, color)
		image.unlock()
		# Get triangle stats
		var status_str : String = triangle.get_status()
		_status_label.bbcode_enabled = true
		_status_label.bbcode_text = status_str


class Region:
	var _parent: TriBlob
	var _debug_color: Color
	var _cells: Array
	var _region_front: Array
	var _border_cells: Array
	
	func _init(parent: TriBlob, start_triangle: BaseTriangle, debug_color: Color) -> void:
		_parent = parent
		_debug_color = debug_color
		_cells = []
		_region_front = [start_triangle]
	
	func expand_tick() -> bool:
		if _region_front.empty():
			return true
		_region_front.shuffle()
		add_triangle_as_cell(_region_front.back())
		return false
	
	func add_triangle_as_cell(triangle: BaseTriangle) -> void:
		triangle.set_parent(self)
		_cells.append(triangle)
		# Remove this one from the _blob_front
		_region_front.erase(triangle)
		# Add neighbours to _blob_front
		for neighbour in triangle.get_neighbours_with_parent(_parent):
			if not neighbour in _region_front:
				_region_front.append(neighbour)

	func draw_triangles(image: Image) -> void:
		for cell in _cells:
			if not cell in _border_cells:
				cell.draw_triangle_on_image(image, _debug_color)
	
	func find_borders() -> void:
		for cell in _cells:
			if cell.count_neighbours_with_parent(self) < 3:
				_border_cells.append(cell)
			elif cell.count_corner_neighbours_with_parent(self) < 9:
				_border_cells.append(cell)


class RegionManager:
	var _regions: Array
	
	func _init(parent: TriBlob, colors: Array) -> void:
		var start_triangles = parent.get_some_triangles(len(colors))
		_regions = []
		for i in range(len(colors)):
			_regions.append(Region.new(parent, start_triangles[i], colors[i]))
	
	func expand_tick() -> bool:
		var frame_end = OS.get_ticks_msec() + FRAME_TIME_MILLIS
		
		while OS.get_ticks_msec() < frame_end:
			var done = true
			for region in _regions:
				if not region.expand_tick():
					done = false
			if done: return true
		return false
	
	func draw_triangles(image: Image) -> void:
		image.lock()
		for region in _regions:
			region.draw_triangles(image)
		image.unlock()
	
	func find_borders() -> void:
		for region in _regions:
			region.find_borders()


func _ready() -> void:
	status_label.text = "Starting..."
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
#	rng.seed = hash("island")
	rng.seed = OS.get_system_time_msecs()
	
	base_grid = BaseGrid.new(CELL_EDGE, rect_size)
	mouse_tracker = MouseTracker.new(base_grid, status_label)
	
	var island_cells_target : int = (base_grid.get_cell_count() / 2)

	land_blob = TriBlob.new(base_grid, rng, island_cells_target)
	
	ready = true

func _process(_delta) -> void:
	
	if not ready:
		return
	
	elif not blob_done:
		status_label.text = "Ready..."
		blob_done = land_blob.expand_tick()
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
	
	elif not edges_done:
		status_label.text = "Island defined..."
		edges_done = true
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
		region_manager = RegionManager.new(land_blob, REGION_COLORS)
	
	elif not regions_done:
		status_label.text = "Perimeter defined..."
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		regions_done = region_manager.expand_tick()
		region_manager.draw_triangles(image)
		imageTexture.create_from_image(image)
		texture = imageTexture
	
	elif not borders_done:
		status_label.text = "Regions defined..."
		borders_done = true
		region_manager.find_borders()
	
	else:
		status_label.text = ""
		base_grid.draw_grid(image, GRID_COLOR)
		region_manager.draw_triangles(image)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		mouse_tracker.update_mouse_coords(get_viewport().get_mouse_position())
		mouse_tracker.draw_triangle_closest_to_mouse(image, CURSOR_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
