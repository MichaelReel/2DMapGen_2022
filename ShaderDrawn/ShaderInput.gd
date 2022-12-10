extends TextureRect

const COOL_DOWN : float = 1.000
const ZOOM_SPEED : float = 0.05
const ZOOM_MAX : float = 1.3
const ZOOM_MIN : float = ZOOM_SPEED

var zoom := 0.4
var mat : ShaderMaterial = material

#onready var captured_image = $CapturedImage

func _process(_delta):
	# Get shader properties
	var mouse = get_global_mouse_position() / get_rect().size;
	
	# Set shader properties
	mat.set_shader_param("Mouse", mouse)
	mat.set_shader_param("Zoom", zoom)

func capture_viewport_image() -> void:
	get_viewport().set_clear_mode(Viewport.CLEAR_MODE_ONLY_NEXT_FRAME)
	# Wait until the frame has finished before getting the texture.
	yield(VisualServer, "frame_post_draw")

	# Retrieve the captured image.
	var img = get_viewport().get_texture().get_data()

	# Flip it on the y-axis (because it's flipped).
	img.flip_y()

	var err = img.save_png("res://shader_input.png")
	if err != OK:
		push_error("Failed to save output image: " + str(err))

	# Create a texture for it.
#	var tex = ImageTexture.new()
#	tex.create_from_image(img)

	# Set the texture to the captured image node.
#	captured_image.set_texture(tex)

func _gui_input(event : InputEvent):
	if event is InputEventMouseButton:
		var emb := event as InputEventMouseButton
		if emb.is_pressed():
			if emb.get_button_index() == BUTTON_WHEEL_UP:
				zoom = min(ZOOM_MAX, zoom + ZOOM_SPEED)
			if emb.get_button_index() == BUTTON_WHEEL_DOWN:
				zoom = max(ZOOM_MIN, zoom - ZOOM_SPEED)
			if emb.get_button_index() == BUTTON_LEFT:
				capture_viewport_image()
		
