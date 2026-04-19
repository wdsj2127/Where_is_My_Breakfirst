extends Sprite2D

func _ready():
	var size = 16
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center = size/2
	var radius = size/2 - 2
	for x in range(size):
		for y in range(size):
			var dx = x - center
			var dy = y - center
			if dx*dx + dy*dy <= radius*radius:
				img.set_pixel(x, y, Color.WHITE)
	texture = ImageTexture.create_from_image(img)
