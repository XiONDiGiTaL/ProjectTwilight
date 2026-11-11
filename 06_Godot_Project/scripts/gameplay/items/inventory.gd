class_name Inventory
extends RefCounted
## A character's carried items. Pure data + rules (stacking, weight).
## Entries: {"id": int, "amount": int}. Etc and usable items stack; equipment
## occupies one entry per piece.

const MAX_ENTRIES := 100   # classic inventory limit (Medium confidence)
const MAX_STACK := 30000
## Per-bag slot limit; Kafra storage raises it (see SimUnit.STORAGE_SLOTS).
var max_entries := MAX_ENTRIES

var entries: Array = []


static func is_stackable(def: Dictionary) -> bool:
	return String(def.get("type", "etc")) in ["etc", "usable"]


## Total weight in the client's units (tenths are not used in Pre-Renewal data here).
func weight(db: Dictionary) -> int:
	var w := 0
	for e in entries:
		w += int(db.get(str(e.id), {}).get("weight", 0)) * int(e.amount)
	return w


func count(item_id: int) -> int:
	var n := 0
	for e in entries:
		if int(e.id) == item_id:
			n += int(e.amount)
	return n


## Adds items if weight and slot limits allow. Returns true on success.
func add(item_id: int, amount: int, db: Dictionary, max_weight: int) -> bool:
	var def: Dictionary = db.get(str(item_id), {})
	if def.is_empty() or amount <= 0:
		return false
	if weight(db) + int(def.get("weight", 0)) * amount > max_weight:
		return false
	if is_stackable(def):
		for e in entries:
			if int(e.id) == item_id and int(e.amount) + amount <= MAX_STACK:
				e.amount = int(e.amount) + amount
				return true
		if entries.size() >= max_entries:
			return false
		entries.append({"id": item_id, "amount": amount})
		return true
	if entries.size() + amount > max_entries:
		return false
	for i in amount:
		entries.append({"id": item_id, "amount": 1})
	return true


## Removes `amount` from entry `index`. Returns the removed item id or -1.
func remove_at(index: int, amount := 1) -> int:
	if index < 0 or index >= entries.size() or amount <= 0:
		return -1
	var e: Dictionary = entries[index]
	if int(e.amount) < amount:
		return -1
	e.amount = int(e.amount) - amount
	var id := int(e.id)
	if e.amount <= 0:
		entries.remove_at(index)
	return id


func to_array() -> Array:
	return entries.duplicate(true)


static func from_array(arr: Array, db: Dictionary) -> Inventory:
	var inv := Inventory.new()
	for e in arr:
		if e is Dictionary and db.has(str(int(e.get("id", -1)))) and int(e.get("amount", 0)) > 0:
			inv.entries.append({"id": int(e.id), "amount": mini(int(e.amount), MAX_STACK)})
	return inv
