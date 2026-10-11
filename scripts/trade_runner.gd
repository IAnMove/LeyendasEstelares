class_name TradeRunner
extends RefCounted
## Comercio en datos científicos; existencias persistentes y transacciones validadas.

var state
var species_id: String


func _init(state_, species_id_: String) -> void:
	state = state_
	species_id = species_id_
	if Content.markets.has(species_id) and not state.market_stock.has(species_id):
		state.market_stock[species_id] = Content.markets[species_id].duplicate(true)


func is_open() -> bool:
	return state.relations.get(species_id, "") in ["alliance", "deal"] and Content.markets.has(species_id)


func offers() -> Array:
	return Content.markets.get(species_id, {}).keys()


func stock(id: String) -> int:
	return int(state.market_stock.get(species_id, {}).get(id, 0))


func price(id: String, selling := false) -> int:
	var base := int(Content.item_by_id(id).get("price", 0))
	if selling:
		return maxi(1, base / 2)
	return maxi(1, base - (1 if state.relations.get(species_id, "") == "alliance" else 0))


func reason(id: String, selling := false) -> String:
	if not is_open() or not offers().has(id):
		return "ui.trade.closed"
	if selling:
		return "ui.cargo.empty" if state.item_count(id) <= 0 else ""
	if stock(id) <= 0:
		return "ui.trade.sold_out"
	if state.item_count(id) >= int(Content.item_by_id(id)["capacity"]):
		return "ui.trade.capacity"
	if state.data < price(id):
		return "ui.trade.no_data"
	return ""


func transact(id: String, selling := false) -> bool:
	if reason(id, selling) != "":
		return false
	var direction := -1 if selling else 1
	state.data -= price(id, selling) * direction
	state.inventory[id] = state.item_count(id) + direction
	state.market_stock[species_id][id] = stock(id) - direction
	state.changed.emit()
	return true
