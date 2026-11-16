class_name DistrictLayout
extends RefCounted

## Fixed campus arrival graph. Raid seeds vary contents, never the architecture.
const POIS := ["research", "outpatient", "logistics", "facilities"]
# Outdoor arrival points, rather than inaccessible building centers.
const CENTERS := [Vector2(47,43),Vector2(0,77),Vector2(82,-5),Vector2(-87,5)]
var seed_value := 0
var version := 1
var positions: Array[Vector2] = []
var edges: Array[Vector2i] = []
var route_kinds: Array[String] = []

static func generate(seed_number: int, config: DistrictGenerationConfig = null) -> DistrictLayout:
	var result := DistrictLayout.new()
	result.seed_value=seed_number
	if config==null: config=DistrictGenerationConfig.new()
	result.version=config.generator_version
	var scale:=config.size_meters/350.0
	for at: Vector2 in CENTERS: result.positions.append(at*scale)
	for a in POIS.size():
		for other in range(a+1,POIS.size()): result.connect_pois(a,other,"campus")
	return result

static func stream(seed_number: int, domain: String, generation_version := 1) -> int:
	# Stable hash, independent of engine hash() implementation and process order.
	var digest := (str(generation_version)+":"+str(seed_number)+":"+domain).sha256_text()
	return digest.substr(0,15).hex_to_int()

func connect_pois(a: int, b: int, kind: String) -> void:
	var edge:=Vector2i(mini(a,b),maxi(a,b))
	if not edges.has(edge):
		edges.append(edge)
		route_kinds.append(kind)

func neighbors(index: int, removed := -1) -> Array[int]:
	var found: Array[int]=[]
	for edge in edges:
		if edge.x==removed or edge.y==removed: continue
		if edge.x==index: found.append(edge.y)
		elif edge.y==index: found.append(edge.x)
	return found

func reachable(removed := -1) -> Array[int]:
	var seen: Array[int]=[]
	var pending: Array[int]=[1 if removed==0 else 0]
	while not pending.is_empty():
		var current: int=pending.pop_back()
		if seen.has(current): continue
		seen.append(current)
		for next in neighbors(current,removed):
			if not seen.has(next): pending.append(next)
	return seen

func validate(config: DistrictGenerationConfig = null) -> Array[String]:
	if config==null: config=DistrictGenerationConfig.new()
	var errors: Array[String]=[]
	if reachable().size()!=POIS.size(): errors.append("disconnected POIs")
	if edges.size()-positions.size()+1<config.minimum_loops: errors.append("insufficient traversal loops")
	for i in positions.size():
		if neighbors(i).size()<config.minimum_poi_degree: errors.append(POIS[i]+": insufficient approaches")
		if reachable(i).size()!=positions.size()-1: errors.append(POIS[i]+": unavoidable bottleneck")
		if absf(positions[i].x)>config.size_meters*.5-35 or absf(positions[i].y)>config.size_meters*.5-35: errors.append(POIS[i]+": outside district")
	return errors

func report() -> Dictionary:
	var nodes: Array[Dictionary]=[]
	var routes: Array[Dictionary]=[]
	for i in positions.size(): nodes.append({"id":POIS[i],"x":positions[i].x,"z":positions[i].y,"degree":neighbors(i).size()})
	for i in edges.size(): routes.append({"a":POIS[edges[i].x],"b":POIS[edges[i].y],"kind":route_kinds[i]})
	return {"seed":seed_value,"generator_version":version,"pois":nodes,"routes":routes,"loops":edges.size()-positions.size()+1,"errors":validate()}
