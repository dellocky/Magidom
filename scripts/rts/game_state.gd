extends Node
## Player-wide session state shared across levels: the selected faction, global
## mana (0..1000) and money, plus the dev-mode infinite toggles.

signal faction_changed(faction: Resource)
signal mana_changed(value: float)
signal money_changed(value: int)
signal infinite_mana_changed(enabled: bool)
signal infinite_money_changed(enabled: bool)
signal global_cast_began()

const FACTION_IDS := [
	"warlocks", "elementalists", "fairy_fembois", "spiritualists",
]
const FACTION_DIR := "res://data/factions/"
const DEFAULT_FACTION := "elementalists"
const MONEY_INFINITE := 999999999

var faction: Resource = null
var factions: Array[Resource] = []
var mana: float = 0.0
var max_mana: float = 1000.0
var money: int = 0
var infinite_mana: bool = false
var infinite_money: bool = false
var global_cooldown_remaining: float = 0.0


func _ready() -> void:
	_load_factions()
	set_faction(&"elementalists")


func _process(delta: float) -> void:
	if global_cooldown_remaining > 0.0:
		global_cooldown_remaining = maxf(0.0, global_cooldown_remaining - delta)


# --------------------------------------------------------------------- factions

func _load_factions() -> void:
	factions.clear()
	for id: String in FACTION_IDS:
		var path := FACTION_DIR + id + ".tres"
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res != null:
				factions.append(res)


func faction_ids() -> PackedStringArray:
	return PackedStringArray(FACTION_IDS)


func faction_index() -> int:
	var f: Resource = faction
	for i in factions.size():
		if factions[i] == f:
			return i
	return -1


func set_faction(id: StringName) -> void:
	for f: Resource in factions:
		if f.get("id") == id:
			faction = f
			faction_changed.emit(faction)
			return
	# Fall back to whichever faction resource was loaded first if the id is unknown.
	if faction == null and not factions.is_empty():
		faction = factions[0]
		faction_changed.emit(faction)


# ------------------------------------------------------------------------ mana

func is_mana_full() -> bool:
	return infinite_mana or mana >= max_mana


func has_mana(cost: float) -> bool:
	return infinite_mana or mana >= cost


func spend_mana(cost: float) -> bool:
	if not has_mana(cost):
		return false
	if not infinite_mana:
		mana = maxf(0.0, mana - cost)
		mana_changed.emit(mana)
	return true


func add_mana(amount: float) -> void:
	mana = clampf(mana + amount, 0.0, max_mana)
	mana_changed.emit(mana)


func set_infinite_mana(enabled: bool) -> void:
	infinite_mana = enabled
	if enabled:
		mana = max_mana
	mana_changed.emit(mana)
	infinite_mana_changed.emit(enabled)


func set_infinite_money(enabled: bool) -> void:
	infinite_money = enabled
	money = MONEY_INFINITE if enabled else 0
	money_changed.emit(money)
	infinite_money_changed.emit(enabled)


# ------------------------------------------------------------------ global spell

func current_global_spell() -> Resource:
	if faction == null:
		return null
	return faction.get("global_spell")


func can_cast_global() -> bool:
	var spell: Resource = current_global_spell()
	if spell == null:
		return false
	if global_cooldown_remaining > 0.0:
		return false
	return has_mana(float(spell.get("mana_cost")))


func cast_global() -> bool:
	var spell: Resource = current_global_spell()
	if spell == null or not can_cast_global():
		return false
	spend_mana(float(spell.get("mana_cost")))
	global_cooldown_remaining = float(spell.get("cooldown"))
	global_cast_began.emit()
	return true