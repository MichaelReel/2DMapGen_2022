extends TextureRect

onready var image := Image.new()
onready var imageTexture := ImageTexture.new()
onready var ready := false

const CELL_EDGE := 100.0
const SEA_COLOR := Color8(32, 32, 128, 255)
const COAST_COLOR := Color8(128, 128, 32, 255)
const RIVER_COLOR := Color8(128, 32, 32, 255)
const LAND_COLOR := Color8(32, 128, 32, 255)

var base_grid : BaseGrid

class BaseGrid:
	
	var grid_points : Array = []
	var grid_lines : Array = []
	
	func _init(edge_size: float, rect_size: Vector2) -> void:
		var tri_side = edge_size
		var tri_height = sqrt(0.75 * (tri_side * tri_side))
#		 |\       h^2 + (s/2)^2 = s^2
#		 | \s     h^2 = s^2 - (s/2)^2
#		h|  \     h^2 = s^2 - (s^2 / 4)
#		 |___\    h^2 = (1 - 1/4) * s^2
#		  s/2     h^2 = ( 3/4 * s^2 )
		
		var row_ind : int = 0
		for y in range (0.0, rect_size.y, tri_height):
			var points_row : Array = []
			var ind_offset : int = (row_ind % 2) * 2 - 1
			var offset : float = (row_ind % 2) * (tri_side / 2.0)
			var col_ind : int = 0
			for x in range(offset, rect_size.x, tri_side):
				var new_point = Vector2(x, y)
				points_row.append(new_point)
				# Connect from the left
				if col_ind > 0:
					grid_lines.append([points_row[col_ind - 1], new_point])
				# Connect from above (the simpler way)
				if row_ind > 0 and col_ind < grid_points[row_ind - 1].size():
					grid_lines.append([grid_points[row_ind - 1][col_ind], new_point])
				# Connect from above (the other way)
				if row_ind > 0 and col_ind + ind_offset >= 0 and col_ind + ind_offset < grid_points[row_ind - 1].size():
					grid_lines.append([grid_points[row_ind - 1][col_ind + ind_offset], new_point])
		
				col_ind += 1
			grid_points.append(points_row)
			row_ind += 1
	
	static func draw_line_on_image(image: Image, a: Vector2, b: Vector2, col: Color) -> void:
		var longest_side = int(max(abs(a.x - b.x), abs(a.y - b.y))) + 1
		for p in range(longest_side):
			var t = (1.0 / longest_side) * p
			image.set_pixelv(lerp(a, b, t), col)
	
	func draw_grid(image: Image, color: Color) -> void:
		image.lock()
		for line in grid_lines:
			draw_line_on_image(image, line[0], line[1], color)
		image.unlock()



func _ready() -> void:
	image.create(int(rect_size.x), int(rect_size.y), false, Image.FORMAT_RGBA8)
	image.fill(SEA_COLOR)
	
	base_grid = BaseGrid.new(CELL_EDGE, rect_size)
	
	ready = true

func _process(_delta) -> void:
	
	if not ready:
		return
	
	base_grid.draw_grid(image, COAST_COLOR)
	imageTexture.create_from_image(image)
	texture = imageTexture
	
	
