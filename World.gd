tool
extends Node2D
export(int) var global_seed = 100
var rg = RandomNumberGenerator.new()

const LAKE_THRESHOLD = 0.3
var POSITION = Vector2(-512, -300)
var SIZE = Vector2(1000, 500)
var MAP = {
	"top_left": POSITION,
	"bottom_right": Vector2(POSITION.x + SIZE.x, POSITION.y + SIZE.y),
	"size": SIZE
}

var DRAW = false

var islandShape: IslandShape
var diagram: VoronoiDiagram
var graph: Graph
var font

func _ready():
	rg.seed = (global_seed)
	seed(global_seed)
	var points = generate_random_points(300, MAP.top_left, MAP.bottom_right)
	diagram = generate_voronoi_polygons(points)
	islandShape = IslandShape.new("SQUARE", global_seed, MAP)
	
	graph = Graph.new(diagram.sites(), MAP)
	
	_assign_elevations()
	_assign_waters()
	_map_decoration()
	
	DRAW = true

func _assign_elevations():
	_assign_corner_elevation()
	_assign_ocean_coast_land()
	# Rescale elevation to 1.0
	_redistribute_elevation(_get_land_corners())
	# Assign elevations to non-land corners
	for corner in graph.corners:
		if corner.ocean or corner.coast:
			corner.elevation = 0.0
	_assign_center_elevation()

func _assign_waters():
	_calculate_downslopes()
#	_calculate_watershed() TODO
	_create_rivers()
	_assign_moisture()
	_redistribute_moisture(_get_land_corners())
	_assign_polygon_moisture()
	
func _map_decoration():
	_assign_biomes()
	
func _draw():
#	draw_rect(Rect2(POSITION.x, POSITION.y, SIZE.x, SIZE.y), Color.aliceblue)
	if graph and DRAW:
		var label = Label.new()
		font = label.get_font("")
		label.queue_free()
#		for corner in graph.corners:
#			if corner.border:
#				draw_circle(corner.point, 5, Color.red)
#			else:
#				draw_circle(corner.point, 3, Color.yellow)
##			draw_string(font, corner.point, str(corner.moisture))
#			if corner.water:
#				draw_circle(corner.point, 5, Color.blue)
		for center in graph.centers:
#			draw_string(font, center.point, str(center.moisture))
			var points = []
			for corner in center.corners:
				points.append(corner.point)
			draw_colored_polygon(PoolVector2Array(points), _get_biome_color(center.biome))
#			if center.ocean:
#				draw_colored_polygon(PoolVector2Array(points), Color.darkblue)
#			elif center.water:
#				draw_colored_polygon(PoolVector2Array(points), Color.blue)
#			elif center.coast:
#				draw_colored_polygon(PoolVector2Array(points), Color.yellow)
#			elif not center.water:
#				draw_colored_polygon(PoolVector2Array(points), Color.green)
				
#			draw_string(font, center.point, str(center.index))
#			draw_circle(center.point, 3, Color.cyan)
		for edge in graph.edges:
			if edge.river > 0:
				draw_line(edge.v0.point, edge.v1.point, Color.blue, 5)
#			else:
#				draw_line(edge.v0.point, edge.v1.point, Color.rebeccapurple)
#			if edge.d0 and edge.d1:
#				draw_line(edge.d0.point, edge.d1.point, Color.orange)
	if diagram and false:
		draw_diagram()

func generate_voronoi_polygons(points):
	# Create voronoi generator
	var generator = Voronoi.new()
	generator.set_points(points)
	generator.set_boundaries(Rect2(POSITION.x, POSITION.y, SIZE.x, SIZE.y))
	generator.relax_points(2)
	#	# Generate diagram
	return generator.generate_diagram()

func generate_random_points(quantity: int, startPoint: Vector2, endPoint: Vector2):
	var points = []
	for num in quantity:
		points.append(Vector2(rg.randi_range(startPoint.x, endPoint.x),
					  rg.randi_range(startPoint.y, endPoint.y)))
	return points

func draw_diagram():
	# Iterate over sites
	for site in diagram.sites():
		draw_circle(site.center(), 1, Color.royalblue)
	# Iterate over edges
	for edge in diagram.edges():
#		for site in edge.sites():
#			draw_circle(site.center(), 10, Color.royalblue)s
		draw_line(edge.start(), edge.end(), Color.red)

func _assign_corner_elevation():
	var queue = []
	for corner in graph.corners:
		# Set each corner to water if it is inside the IslandShape objects shape
		corner.water = not _inside(corner.point)
	for corner in graph.corners:
		# Elevation on border is 0, grows when going inside
		if corner.border:
			corner.elevation = 0.0
			queue.append(corner)
		else:
			corner.elevation = INF
			
	while len(queue) > 0:
		var corner = queue.pop_front()
		# Flooding algorithm, elevation increases while going inside
		# Elevation is sum of adjacent corners elevation
		for adj_corner in corner.adjacents:
			var new_elevation = 0.01 + corner.elevation
			if !corner.water and !adj_corner.water:
				new_elevation += 1
			if new_elevation < adj_corner.elevation:
				adj_corner.elevation = new_elevation
				queue.append(adj_corner)

func _inside(p: Vector2):
	return islandShape.is_land(p)

func _assign_ocean_coast_land():
	var queue = []
	for center in graph.centers:
		var numWater = 0
		for corner in center.corners:
			# Set border centers to water and ocean
			if corner.border:
				center.border = true
				center.ocean = true
				corner.water = true
				queue.push_back(center)
			# Keep counting number of waters
			if corner.water:
				numWater += 1
		# Center will be water if ocean, or given fraction of corners are water
		center.water = (center.ocean or (numWater >= len(center.corners) * LAKE_THRESHOLD))
	
	while len(queue) > 0:
		var center = queue.pop_front()
		# Flooding algorithm, set ocean on ocean centers
		for neighbor in center.neighbors:
			if neighbor.water and not neighbor.ocean:
				neighbor.ocean = true
				queue.push_back(neighbor)
	# Set centers to coast if has ocean and land corner as well.
	for center in graph.centers:
		var num_ocean:int = 0
		var num_land:int = 0
		for neighbor in center.neighbors:
			num_ocean += int(neighbor.ocean)
			num_land += int(not neighbor.water)
		center.coast = (num_ocean > 0) and (num_land > 0)
	# Set corner attribute based on center attributes
	for corner in graph.corners:
		var num_ocean:int = 0
		var num_land:int = 0
		for center in corner.touches:
			num_ocean += int(center.ocean)
			num_land += int(not center.water)
		corner.ocean = (num_ocean == len(corner.touches))
		corner.coast = (num_ocean > 0) and (num_land > 0)
		corner.water = corner.border or ((num_land != len(corner.touches)) \
						and not corner.coast)
		
func _get_land_corners():
	var land_corners = []
	for corner in graph.corners:
		if not corner.ocean and not corner.coast:
			land_corners.append(corner)
	return land_corners

func _redistribute_elevation(locations: Array):
	# Higher scale_factor => more mountains
	var SCALE_FACTOR = 1.1
	locations.sort_custom(self, "_sort_elevation")
	for idx in len(locations):
		var y:float = float(idx) / (len(locations) - 1)
		var x:float = sqrt(SCALE_FACTOR) - sqrt(SCALE_FACTOR * (1 - y))
		if x > 1.0:
			x = 1.0
		locations[idx].elevation = x
	
func _sort_elevation(a,b):
	return a.elevation < b.elevation

func _assign_center_elevation():
	for center in graph.centers:
		var sum_elevation = 0.0
		for corner in center.corners:
			sum_elevation += corner.elevation
		center.elevation = sum_elevation / len(center.corners)

func _calculate_downslopes():
	var r:Graph.Corner
	for q in graph.corners:
		r = q
		for s in q.adjacents:
			if s.elevation <= r.elevation:
				r = s
		q.downslope = r

func _create_rivers():
	for idx in MAP.size.y / 5:
		var corner = graph.corners[rg.randi_range(0, len(graph.corners)-1)]
		if corner.ocean or corner.elevation < 0.3 or corner.elevation > 0.9:
			continue
		while not corner.coast:
			if corner == corner.downslope:
				break
			var edge = _look_up_edge_from_corner(corner, corner.downslope)
			edge.river = edge.river + 1
			corner.river = corner.river + 1
			corner.downslope.river = corner.downslope.river + 1
			corner = corner.downslope
		
func _look_up_edge_from_corner(c1: Graph.Corner, c2: Graph.Corner):
	for edge in c1.protrudes:
		if (edge.v0 == c2 or edge.v1 == c2):
			return edge
	return null

func _assign_moisture():
	var queue = []
	for corner in graph.corners:
		if ((corner.water or corner.river > 0) and not corner.ocean):
			if corner.river > 0:
				corner.moisture = min(3.0, 0.2 * corner.river)
			else:
				corner.moisture = 0.0
			queue.append(corner)
		else:
			corner.moisture = 0.0
	while len(queue) > 0:
		var corner = queue.pop_front()
		for r in corner.adjacents:
			var new_moisture = corner.moisture * 0.9
			if new_moisture > r.moisture:
				r.moisture = new_moisture
				queue.push_back(r)
	for corner in graph.corners:
		if corner.ocean or corner.coast:
			corner.moisture = 1

func _redistribute_moisture(locations: Array):
	locations.sort_custom(self, "_sort_moisture")
	for idx in len(locations):
		locations[idx].moisture = float(idx) / (len(locations) - 1)

func _sort_moisture(a,b):
	return a.moisture < b.moisture

func _assign_polygon_moisture():
	for center in graph.centers:
		var sum_moisture:float = 0.0
		for corner in center.corners:
			if corner.moisture > 1.0:
				corner.moisture = 1.0
			sum_moisture += corner.moisture
		center.moisture = sum_moisture / len(center.corners)

func _assign_biomes():
	for center in graph.centers:
		center.biome = get_biome(center)
				
static func get_biome(center: Graph.Center):
	if (center.ocean):
		return 'OCEAN'
	elif (center.water):
		if (center.elevation < 0.1):
			return 'MARSH'
		if (center.elevation > 0.8):
			return 'ICE'
		return 'LAKE'
	elif (center.coast):
		return 'BEACH'
	elif (center.elevation > 0.8):
		if (center.moisture > 0.50):
			return 'SNOW'
		elif (center.moisture > 0.16):
			return 'TUNDRA'
		else:
			return 'SCORCHED'
	elif (center.elevation > 0.6):
		if (center.moisture > 0.33):
			return 'TAIGA'
		else:
			return 'DESERT'
	elif (center.elevation > 0.3):
		if (center.moisture > 0.83):
			return 'RAIN_FOREST'
		elif (center.moisture > 0.50): 
			return 'FOREST'
		elif (center.moisture > 0.16):
			return 'GRASSLAND'
		else:
			return 'DESERT'
	else:
		if (center.moisture > 0.66):
			return 'RAIN_FOREST'
		elif (center.moisture > 0.33):
			return 'FOREST'
		elif (center.moisture > 0.16):
			return 'GRASSLAND'
		else:
			return 'DESERT'

func _get_biome_color(biome: String):
	var colors = {
		"OCEAN": Color8(0, 39, 102),
		"MARSH": Color8(0, 145, 114),
		"ICE": Color8(164, 201, 235),
		"LAKE": Color8(0, 145, 171),
		"BEACH": Color8(255, 253, 201),
		"SNOW": Color8(227, 227, 227),
		"TUNDRA": Color8(230, 255, 232),
		"SCORCHED": Color8(110, 33, 8),
		"TAIGA": Color8(84, 115, 87),
		"DESERT": Color8(235, 219, 82),
		"RAIN_FOREST": Color8(45, 179, 129),
		"FOREST": Color8(42, 130, 38),
		"GRASSLAND": Color8(69, 230, 62)
	}
	return colors.get(biome)
