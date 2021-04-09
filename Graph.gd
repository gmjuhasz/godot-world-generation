class_name Graph
	
class Center:
	var index:int;
	
	var point:Vector2  # location
	var water:bool  # lake or ocean
	var ocean:bool  # ocean
	var coast:bool  # land polygon touching an ocean
	var border:bool  # at the edge of the map
	var biome:String  # biome type (see article)
	var elevation:float  # 0.0-1.0
	var moisture:float  # 0.0-1.0

	var neighbors:Array = [] # Centers
	var borders:Array = [] # Edges
	var corners:Array = [] # Corners
	
	func _init(init_point: Vector2):
		point = init_point
class Corner:
	var index:int

	var point:Vector2  # location
	var ocean:bool  # ocean
	var water:bool = false  # lake or ocean
	var coast:bool  # touches ocean and land polygons
	var border:bool  # at the edge of the map
	var elevation:float  # 0.0-1.0
	var moisture:float  # 0.0-1.0

	var touches:Array = [] # Centers
	var protrudes:Array = []  # Edges
	var adjacents:Array = [] # Corners

	var river:int = 0  # 0 if no river, or volume of water in river
	var downslope:Corner  # pointer to adjacent corner most downhill
	var watershed:Corner  # pointer to coastal corner, or null
	var watershed_size:int
	
	func _init(init_point: Vector2):
		point = init_point
class Edge:
	var index:int
	var d0:Center; var d1:Center  # Delaunay edge
	var v0:Corner; var v1:Corner  # Voronoi edge
	var midpoint:Vector2  # halfway between v0,v1
	var river:int = 0 # volume of water, or 0

var MAP

var centers:Array
var corners:Array
var edges:Array

func _init(voronoiSites:Array, map):
	MAP = map
	_parse_voronoi_sites(voronoiSites)
#	_improve_corners()

# Creates the Center, Corner and Edge objects from voronoi graph
func _parse_voronoi_sites(voronoiSites: Array):
	for site_idx in len(voronoiSites):
		# Iterates through each site, get its edges end neighbors
		var voronoi_site = voronoiSites[site_idx]
		var voronoi_edges = voronoi_site.edges()
		var voronoi_neighbor_sites = voronoi_site.neighbors()
		# Create Center
		var center = _get_center(voronoi_site)
		# Create Edge
		var sorted_edges = _sort_edges(voronoi_edges)
		for edge_idx in len(sorted_edges):
			var sorted_edge = sorted_edges[edge_idx]
			var edge = _get_edge(sorted_edge, voronoi_site)
			# Set the constructed edges as borders of the current center object
			center.borders.append(edge)
			# Sets the edges endpoint as a corner
			if not edge.v0 in center.corners:
				center.corners.append(edge.v0)
		# Create Neighbors
		for neighbor_site in voronoi_neighbor_sites:
			var neighbor_center = _get_center(neighbor_site)
			center.neighbors.append(neighbor_center)

func _sort_edges(v_edges: Array):
	var edges = []
	for idx in len(v_edges):
		var v_edge = v_edges[idx]
		if idx == 0 and not ((v_edge.end().distance_to(v_edges[idx+1].end()) < 0.1) or (v_edge.end().distance_to(v_edges[idx+1].start()) < 0.1)):
			edges.append({"v0": v_edge.end(), "v1": v_edge.start()})
		elif idx == 0 or (v_edge.start().distance_to(edges[idx-1].v1) < 0.1):
			edges.append({"v0": v_edge.start(), "v1": v_edge.end()})
		else:
			edges.append({"v0": v_edge.end(), "v1": v_edge.start()})
	return edges

# Gets a center from centers, if not present yet creates one
func _get_center(voronoi_site: VoronoiSite):
	# GDScript does not have lambda based filtering, so its more complicated
	#   than it should be..
	for center in centers:
		if center.index == voronoi_site.index():
			return center
	# The used voronoi module already indexes the sites, that can be used here
	var center = Center.new(voronoi_site.center())
	center.index = voronoi_site.index()
	centers.append(center)
	return center

# Gets an edge from edges, if not present yet creates one
# Parameters:
#  voronoi_edge: VoronoiEdge - the edge object from the voronoi module, which
#    is used to calculate the endpoints
#  voronoi_site: VoronoiSite - the site object from the voronoi module, which
#    is used to set the Delangulay triangulation points for the edge
func _get_edge(sorted_edge: Dictionary, voronoi_site: VoronoiSite):
	# Edge finding is based on the the same start- end endpoints.
	for edge in edges:
		if (edge.v0.point.distance_to(sorted_edge.v0) < 0.1) and \
		   (edge.v1.point.distance_to(sorted_edge.v1) < 0.1):
			edge.d1 = _get_center(voronoi_site)
			return edge
	var edge = Edge.new()
	edge.d0 = _get_center(voronoi_site)
	edge.v0 = _get_corner(sorted_edge.v0, edge, _get_corner(sorted_edge.v1, edge))
	edge.v1 = _get_corner(sorted_edge.v1, edge, edge.v0)
	edge.index = len(edges)
	edges.append(edge)
	return edge
	
# Gets a corner from corners, if not present yet creates one
# Parameters:
#  point: Vector2 - the point where the corner is located
#  edge: Edge - the Voronoi edge object which is set as the protrudes of corner
#  adj_corner: Corner - if set, it is set as adjacent corner for traversing
func _get_corner(point: Vector2, edge: Edge, adj_corner: Corner = null):
	for corner in corners:
		if corner.point.distance_to(point) < 0.1:
			if !corner.protrudes.has(edge):
				corner.protrudes.append(edge)
			if adj_corner:
				corner.adjacents.append(adj_corner)
			if !corner.touches.has(edge.d0):
				corner.touches.append(edge.d0)
			return corner
	var corner = Corner.new(point)
	corner.index = len(corners)
	corner.protrudes.append(edge)
	corner.touches.append(edge.d0)
	if adj_corner:
		corner.adjacents.append(adj_corner)
	corners.append(corner)
	# Logic to calculate if the corner is a border point on the map
	if (corner.point.x == MAP.top_left.x) or (corner.point.y == MAP.top_left.y) or \
	   (corner.point.x == MAP.bottom_right.x) or (corner.point.y == MAP.bottom_right.x):
		corner.border = true
	return corner

# An algorighm which improves the corners position in some cases
func _improve_corners():
	var new_corners = []
	for corner in corners:
		if corner.border:
			new_corners.append(corner)
		else:
			var point = Vector2(0, 0)
			for center in corner.touches:
				point.x += center.point.x
				point.y += center.point.y
			point.x /= len(corner.touches)
			point.y /= len(corner.touches)
			corner.point = point
			new_corners.append(corner)
	corners = new_corners
