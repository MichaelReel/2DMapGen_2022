extends TextureRect

onready var status_label := $RichTextLabel
onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false
onready var blob_done := false
onready var edges_done := false
onready var regions_done := false
onready var sub_regions_done := false
onready var borders_done := false
onready var sub_borders_done := false
onready var rivers_done := false

const CELL_EDGE := 12.0
const SEA_COLOR := Color8(32, 32, 64, 255)
const GRID_COLOR := Color8(40, 40, 96, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := SEA_COLOR  # Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)
const CURSOR_COLOR := Color8(128, 32, 128, 255)
const RIVER_COUNT := 8

const REGION_COLORS := [
	Color8(  0,   0, 192, 255),
	Color8(  0, 192,   0, 255),
	Color8(192,   0,   0, 255),
	Color8(  0, 192, 192, 255),
	Color8(192, 192,   0, 255),
	Color8(192,   0, 192, 255),
]

const SUB_REGION_COLORS := [
	Color8(192, 128,  64, 255),
	Color8( 64, 192, 128, 255),
	Color8(128,  64, 192, 255),
]

const FRAME_TIME_MILLIS := 30
const SLOPE := sqrt(1.0 / 3.0)

var base_grid: BaseGrid
var land_blob: TriBlob
var mouse_tracker: MouseTracker
var region_manager: RegionManager
var sub_regions_manager: SubRegionManager
var river_manager: RiverManager


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
	
	static func sort_vert_inv_hortz(a: BasePoint, b: BasePoint) -> bool:
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
			if sort_vert_inv_hortz(self, other):
				higher_conns.append(con)
		return higher_conns
	
	func higher_connections_to_point(point) -> Array:
		# Return connection lines to "higher" points that connect to a given point
		var higher_conns = []
		for con in _connections:
			var other = con.other_point(self)
			if sort_vert_inv_hortz(self, other):
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
	
	func get_connections() -> Array:
		return _connections
	
	func _to_string() -> String:
		return "%d: %s: { %s }" % [get_instance_id(), _pos, _get_line_ids()]


class BaseLine:
	var _a: BasePoint
	var _b: BasePoint
	var _borders: Array
	
	func _init(a: BasePoint, b: BasePoint) -> void:
		if BasePoint.sort_vert_inv_hortz(a, b):
			_a = a
			_b = b
		else:
			_a = b
			_b = a
		_borders = []
	
	func get_points() -> Array:
		return [_a, _b]
	
	func shared_point(other: BaseLine) -> BasePoint:
		if self._a == other._a or self._a == other._b:
			return self._a
		elif self._b == other._a or self._b == other._b:
			return _b
		else:
			return BasePoint.error()
	
	func shares_a_point_with(other: BaseLine) -> bool:
		return (
			other.has_point(_a) or
			other.has_point(_b)
		)
	
	func has_point(point: BasePoint) -> bool:
		return _a == point or _b == point
	
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
	
	func center_in_ring(center: Vector2, min_distance: float, max_distance: float) -> bool:
		var min_squared: float = min_distance * min_distance
		var max_squared: float = max_distance * max_distance
		var line_center: Vector2 = (_a.get_pos() + _b.get_pos()) / 2.0
		var distance = line_center.distance_squared_to(center)
		return distance >= min_squared and distance <= max_squared
	
	func end_point_farthest_from(target: Vector2) -> BasePoint:
		if _a.get_pos().distance_squared_to(target) >= _b.get_pos().distance_squared_to(target):
			return _a
		else:
			return _b
	
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
	
	func get_edges() -> Array:
		return _edges
	
	func get_neighbours() -> Array:
		return _neighbours
	
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
		draw_filled_triangle_on_image(image, color)
	
	# Can use special-case flat top and bottom triangle fill algorithms for filling
	# E.g.: http://www.sunshine2k.de/coding/java/TriangleRasterization/TriangleRasterization.html
	
	func _draw_filled_flat_top_triangle_on_image(image: Image, color: Color) -> void:
		# Flat topped triangles are created with points (p) and edges (e) in a specific orders
		#              e1 
		#         p0 ------ p2     slope of e2 will always be half the side, divided by the height
		#           \      /       slope of e0 will be the negative of e2
		#         e0 \    / e2     SLOPE_e2 = (tri_side / 2) / sqrt(0.75 * (tri_side * tri_side))
		#             \  /         SLOPE_e2 = tri_side / ( 2 * sqrt(0.75) * tri_side )
		#              p1          SLOPE_e2 = 1 / sqrt(0.75 * 4)
		
		var start_x : float = _points[0].get_pos().x
		var end_x : float = _points[2].get_pos().x
		var start_y : int = int(_points[0].get_pos().y)
		var end_y : int = int(_points[1].get_pos().y)
		
		for y in range(start_y, end_y + 1):
			for x in range(int(start_x), int(end_x) + 1):
				image.set_pixel(x, y, color)
			start_x += SLOPE
			end_x -= SLOPE
		
	func _draw_filled_flat_bottom_triangle_on_image(image: Image, color: Color) -> void:
		# Flat bottomed triangles are created with points (p) and edges (e) in a specific orders
		#              p2 
		#             /  \
		#         e2 /    \ e1
		#           /      \
		#         p1 ------ p0
		#              e0
		
		var start_x : float = _points[2].get_pos().x
		var end_x : float = _points[2].get_pos().x
		var start_y : int = int(_points[2].get_pos().y)
		var end_y : int = int(_points[1].get_pos().y)
		
		for y in range(start_y, end_y + 1):
			for x in range(int(start_x), int(end_x) + 1):
				image.set_pixel(x, y, color)
			start_x -= SLOPE
			end_x += SLOPE
	
	func _is_flat_topped() -> bool:
		"""False implies flat bottomed as the grid only has this orientation"""
		# If the first and last points are on the same y axis, this is flat topped
		return _points[0].get_pos().y == _points[2].get_pos().y
	
	func draw_filled_triangle_on_image(image: Image, color: Color) -> void:
		if _is_flat_topped():
			_draw_filled_flat_top_triangle_on_image(image, color)
		else:
			_draw_filled_flat_bottom_triangle_on_image(image, color)
	
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
	var _center: Vector2
	var _near_center_edges: Array = []
	
	func _init(edge_size: float, rect_size: Vector2) -> void:
		_center = rect_size / 2.0
		_tri_side = edge_size
		_tri_height = sqrt(0.75) * _tri_side
		
#		 |\         h^2 + (s/2)^2 = s^2
#		 | \        h^2 = s^2 - (s/2)^2
#		 |  \s      h^2 = s^2 - (s^2 / 4)
#		h|   \      h^2 = (1 - 1/4) * s^2
#		 |    \     h^2 = ( 3/4 * s^2 )
#		 |_____\      h = sqrt(3/4 * s^2)
#		  (s/2)       h = sqrt(3/4) * s
		
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
		if new_line.center_in_ring(_center, 0.0, CELL_EDGE * 10.0):
			_near_center_edges.append(new_line)
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
	
	func get_river_head() -> BaseLine:
		_near_center_edges.shuffle()
		return _near_center_edges.pop_back()
	
	func get_center() -> Vector2:
		return _center


class TriBlob:
	var _grid: BaseGrid
	var _cells: Array
	var _cell_limit: int
	var _blob_front: Array
	var _perimeter: Array
	var _perimeter_done : bool
	
	func _init(grid: BaseGrid, cell_limit: int = 1):
		_grid = grid
		_cells = []
		_cell_limit = cell_limit
		_blob_front = []
		_perimeter = []
		_perimeter_done = false
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

	static func _get_chains_from_lines(perimeter: Array) -> Array:
		"""
		Given an array of unordered BaseLines on the perimeter of a shape
		Return an array, each element of which is an array of BaseLines ordered by
		the path around the perimeter. One of the arrays will be the outer shape and the
		rest will be internal "holes" in the shape.
		"""
		var perimeter_lines := perimeter.duplicate()
		# Identify chains by tracking each point in series of perimeter lines
		var chains: Array = []
		while not perimeter_lines.empty():
			# Next chain, pick the end of a line
			var chain_done = false
			var chain_flipped = false
			var chain: Array = []
			var next_chain_line: BaseLine = perimeter_lines.pop_back()
			var start_chain_point: BasePoint = next_chain_line.get_points().front()
			var next_chain_point: BasePoint = next_chain_line.other_point(start_chain_point)
			# Follow the lines until we reach back to the beginning
			while not chain_done:
				chain.append(next_chain_line)
				
				# Do we have a complete chain now?
				if len(chain) >= 3 and chain.front().shares_a_point_with(chain.back()):
					chains.append(chain)
					chain_done = true
					continue
				
				# Which directions can we go from here?
				var connections = next_chain_point.get_connections()
				var directions: Array = []
				for line in connections:
					# Skip the current line
					if line == next_chain_line:
						continue
					if perimeter_lines.has(line):
						directions.append(line)
				
				# If there's no-where to go, something went wrong
				if len(directions) <= 0:
					printerr("FFS: This line goes nowhere!")
				
				# If there's only one way to go, go that way
				elif len(directions) == 1:
					next_chain_line = directions.front()
					next_chain_point = next_chain_line.other_point(next_chain_point)
					perimeter_lines.erase(next_chain_line)
				
				else:
					# Any links that link back to start of the current chain?
					var loop = false
					for line in directions:
						if line.other_point(next_chain_point) == start_chain_point:
							loop = true
							next_chain_line = line
							next_chain_point = next_chain_line.other_point(next_chain_point)
							perimeter_lines.erase(line)
					
					if not loop:
						# Multiple directions with no obvious loop, 
						# Reverse the chain to extend it in the opposite direction
						if chain_flipped:
							# This chain has already been flipped, both ends are trapped
							# Push this chain back into the pool of lines and try again
							chain.append_array(perimeter_lines)
							perimeter_lines = chain
							chain_done = true
							continue
						
						chain.invert()
						var old_start_point : BasePoint = start_chain_point
						start_chain_point = next_chain_point
						next_chain_line = chain.pop_back()
						next_chain_point = old_start_point
						chain_flipped = true
		
		return chains
	
	func _add_non_perimeter_boundaries() -> void:
		"""
		Find triangles on the boundary front that aren't against the perimeter and
		assume they're inside the total shape. Add them and any unparented neighbours
		to the blob. 
		"""
		var remove_from_front: Array = []
		for front_triangle in _blob_front:
			var has_edge_in_perimeter := false
			for edge in front_triangle.get_edges():
				if edge in _perimeter:
					has_edge_in_perimeter = true
					break
			if not has_edge_in_perimeter:
				front_triangle.set_parent(self)
				_cells.append(front_triangle)
				remove_from_front.append(front_triangle)
				# Is there are any triangles adjacent that are null parented, add to _blob_front
				for neighbour_triangle in front_triangle.get_neighbours():
					if neighbour_triangle.get_parent() == null and not neighbour_triangle in _blob_front:
						_blob_front.append(neighbour_triangle)
		
		for front_triangle in remove_from_front:
			_blob_front.erase(front_triangle)
	
	func get_perimeter_lines() -> Array:
		if _perimeter_done:
			return _perimeter
		
		var blob_front := _blob_front.duplicate()
		
		# using the _blob_front, get all the lines joining to parented cells
		while not blob_front.empty():
			var outer_triangle = blob_front.pop_back()
			var borders : Array = outer_triangle.get_neighbour_borders_with_parent(self)
			_perimeter.append_array(borders)
		
		# Identify chains by tracking each point in series of perimeter lines
		var chains: Array = _get_chains_from_lines(_perimeter)
		
		# Set the _perimeter to the longest chain
		var max_chain: Array = chains.back()
		for chain in chains:
			if len(max_chain) < len(chain):
				max_chain = chain
		_perimeter = max_chain
		
		# Include threshold triangles that are not on the perimeter path
		_add_non_perimeter_boundaries()
		
		_perimeter_done = true
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
			_blob_front.shuffle()
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
	
	func remove_triangle_as_cell(triangle: BaseTriangle) -> void:
			triangle.set_parent(_parent)
			_cells.erase(triangle)
	
	func draw_triangles(image: Image) -> void:
		for cell in _cells:
			cell.draw_triangle_on_image(image, _debug_color)
	
	func find_borders() -> void:
		var border_cells: Array = []
		for cell in _cells:
			if cell.count_neighbours_with_parent(self) < 3:
				border_cells.append(cell)
			elif cell.count_corner_neighbours_with_parent(self) < 9:
				border_cells.append(cell)
		# Return the border cells to the parent
		for border_cell in border_cells:
			remove_triangle_as_cell(border_cell)
	
	func get_some_triangles(count: int) -> Array:
		var random_cells = []
		for _i in range(count):
			random_cells.append(_cells[randi() % len(_cells)])
		return random_cells
	
	func get_debug_color() -> Color:
		return _debug_color


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
	
	func get_regions() -> Array:
		return _regions


# I feel like I will look into refactoring this with the above:
class SubRegion:
	var _parent: Region
	var _debug_color: Color
	var _cells: Array
	var _region_front: Array
	
	func _init(parent: Region, start_triangle: BaseTriangle, debug_color: Color) -> void:
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
	
	func remove_triangle_as_cell(triangle: BaseTriangle) -> void:
			triangle.set_parent(_parent)
			_cells.erase(triangle)
	
	func draw_triangles(image: Image, color: Color = self._debug_color) -> void:
		for cell in _cells:
			cell.draw_triangle_on_image(image, color)
	
	func find_borders() -> void:
		var border_cells: Array = []
		for cell in _cells:
			if cell.count_neighbours_with_parent(self) < 3:
				border_cells.append(cell)
			elif cell.count_corner_neighbours_with_parent(self) < 9:
				border_cells.append(cell)
		# Return the border cells to the parent
		for border_cell in border_cells:
			remove_triangle_as_cell(border_cell)
	
	func get_some_triangles(count: int) -> Array:
		var random_cells = []
		for _i in range(count):
			random_cells.append(_cells[randi() % len(_cells)])
		return random_cells


class SubRegionManager:
	var _regions: Array
	
	func _init(parent_manager: RegionManager, colors: Array) -> void:
		_regions = []
		for parent in parent_manager.get_regions():
			var start_triangles = parent.get_some_triangles(len(colors))
			for i in range(len(colors)):
				_regions.append(SubRegion.new(parent, start_triangles[i], colors[i]))
	
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
	
	func sub_region_for_edge(edge: BaseLine):
		for tri in edge.get_bordering_triangles():
			var sub_region = tri.get_parent()
			if sub_region in _regions:
				return sub_region
		
		return null


class RiverManager:
	var _rivers: Array
	var _grid: BaseGrid
	var _subregion_manager: SubRegionManager
	
	func _init(grid:BaseGrid, subregion_manager: SubRegionManager, river_count: int) -> void:
		_grid = grid
		_subregion_manager = subregion_manager
		_rivers = []
		for _i in range(river_count):
			_rivers.append(create_river())
	
	func create_river() -> Array:
		"""Create a chain of edges from near center to outer bounds"""
		var center := _grid.get_center()
		var start_edge := _grid.get_river_head()
		var river := [start_edge]
		# get furthest end from center, then extend the river until it hits the boundary
		var connection_point: BasePoint = start_edge.end_point_farthest_from(center)
		while len(connection_point.get_connections()) >= 6:
			# Get a random edge that moves away from the center
			var connections: Array = Array(connection_point.get_connections())
			connections.shuffle()
			var try_edge : BaseLine = connections.pop_back()
			while not connections.empty() and try_edge.end_point_farthest_from(center) == connection_point:
				try_edge = connections.pop_back()
			# This shouldn't happen:
			if try_edge.end_point_farthest_from(center) == connection_point:
				printerr("All edges point towards the center")
			
			# Move along the random edge
			river.append(try_edge)
			connection_point = try_edge.other_point(connection_point)
		
		return river
	
	func identify_lakes_on_course(river: Array) -> Array:
		# TODO: Need to modify - want to only draw the river parts that aren't between 
		# the first entry edge on the lake and the last exit edge on the lake
		# Maybe even split rivers
		var lakes := []
		for edge in river:
			var lake = _subregion_manager.sub_region_for_edge(edge)
			if lake != null and not lake in lakes:
				lakes.append(lake)
		return lakes
		
	func draw_rivers(image: Image, color: Color) -> void:
		image.lock()
		for river in _rivers:
			for edge in river:
				edge.draw_line_on_image(image, color)
			var lakes := identify_lakes_on_course(river)
			for lake in lakes:
				lake.draw_triangles(image, color)
		image.unlock()


func _ready() -> void:
	status_label.text = "Starting..."
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	randomize()
	
	base_grid = BaseGrid.new(CELL_EDGE, rect_size)
	mouse_tracker = MouseTracker.new(base_grid, status_label)
	
	var island_cells_target : int = (base_grid.get_cell_count() / 2)
	
	land_blob = TriBlob.new(base_grid, island_cells_target)
	
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
		image.fill(SEA_COLOR)
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
		region_manager = RegionManager.new(land_blob, REGION_COLORS)
	
	elif not regions_done:
		status_label.text = "Perimeter defined..."
		image.fill(SEA_COLOR)
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_triangles(image, LAND_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		regions_done = region_manager.expand_tick()
		region_manager.draw_triangles(image)
		imageTexture.create_from_image(image)
		texture = imageTexture
	
	elif not borders_done:
		status_label.text = "Regions defined..."
		borders_done = true
		region_manager.find_borders()
		sub_regions_manager = SubRegionManager.new(region_manager, SUB_REGION_COLORS)
	
	elif not sub_regions_done:
		status_label.text = "Region borders defined..."
		base_grid.draw_grid(image, GRID_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		sub_regions_done = sub_regions_manager.expand_tick()
		sub_regions_manager.draw_triangles(image)
		imageTexture.create_from_image(image)
		texture = imageTexture
	
	elif not sub_borders_done:
		status_label.text = "Sub regions defined..."
		sub_borders_done = true
		sub_regions_manager.find_borders()
	
	elif not rivers_done:
		status_label.text = "Sub region borders defined..."
		rivers_done = true
		river_manager = RiverManager.new(base_grid, sub_regions_manager, RIVER_COUNT)
	
	else:
		status_label.text = ""
		image.fill(SEA_COLOR)
		base_grid.draw_grid(image, GRID_COLOR)
#		region_manager.draw_triangles(image)
#		sub_regions_manager.draw_triangles(image)
		land_blob.draw_triangles(image, LAND_COLOR)
		river_manager.draw_rivers(image, RIVER_COLOR)
		land_blob.draw_perimeter_lines(image, COAST_COLOR)
		mouse_tracker.update_mouse_coords(get_viewport().get_mouse_position())
		mouse_tracker.draw_triangle_closest_to_mouse(image, CURSOR_COLOR)
		imageTexture.create_from_image(image)
		texture = imageTexture
