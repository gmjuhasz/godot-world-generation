class_name IslandShape
extends Node2D

var type: String
var noise: OpenSimplexNoise
var image
var MAP
var SEED

func _init(island_type: String, island_seed: int, map):
	MAP = map
	SEED = island_seed
	type = island_type
	match type:
		"PERLIN":
			init_perlin(island_seed)

func init_perlin(noise_seed: int):
	noise = OpenSimplexNoise.new()
	# Configure
	noise.seed = noise_seed
	noise.octaves = 4
	noise.period = 20.0
	noise.persistence = 0.8
	image = noise.get_image(256,256)
	image.lock()
	
func is_land(point: Vector2):
	match type:
		"PERLIN":
			return _is_perlin_land(point)
		"SQUARE":
			return _is_square_land(point)

func _is_perlin_land(point: Vector2):
	var value = (image.get_pixel(int((point.x+1)*128), int((point.y+1)*128)).blend(Color(0xff))) / 255.0
	return value.to_rgba64() > (0.3 + 0.3 * point.length() * point.length())	
#	image.save_png("noise.png")

func _is_square_land(point: Vector2):
	var rng = RandomNumberGenerator.new()
	rng.seed = SEED
	var island_rect = Rect2(MAP.top_left / 1.5, MAP.size / 1.5)
	var lake = Rect2(MAP.top_left / 8, MAP.size / 8)
	if island_rect.has_point(point):
		if lake.has_point(point):
			return false
		return true
	return false
