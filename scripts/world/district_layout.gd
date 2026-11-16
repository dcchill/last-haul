class_name DistrictLayout
extends RefCounted

## The graph is produced before any geometry. Coordinates reserve reusable POI
## footprints; seed changes move districts and choose physically realized routes.
const POIS := ["research", "scrapyard", "residential", "warehouse", "substation", "rail", "checkpoint"]
const CENTERS := [Vector2(-77,-88),Vector2(68,-91),Vector2(-98,9),Vector2(12,-12),Vector2(112,17),Vector2(65,104),Vector2(-75,108)]
const RING := [[0,1],[1,4],[4,5],[5,6],[6,2],[2,0]]
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
	var rng:=RandomNumberGenerator.new()
	rng.seed=stream(seed_number,"layout",result.version)
	var scale:=config.size_meters/350.0
	for at: Vector2 in CENTERS: result.positions.append((at+Vector2(rng.randf_range(-6,6),rng.randf_range(-6,6)))*scale)
	for pair: Array in RING: result.connect_pois(pair[0],pair[1],"street")
	for outer in [0,1,2,4,5,6]: result.connect_pois(3,outer,"service" if outer%2==0 else "alley")
	# A cross-district optional detour changes the graph while preserving its core.
	result.connect_pois(2,5,"drainage" if rng.randf()<.5 else "covered_walk")
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
