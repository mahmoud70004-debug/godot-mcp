class_name Inventory
extends RefCounted
## Slot-based inventory. Stackable items merge into existing slots.

signal changed

const MAX_SLOTS := 24


class Slot:
	var item: ItemData
	var quantity: int

	func _init(p_item: ItemData, p_quantity: int) -> void:
		item = p_item
		quantity = p_quantity


var _slots: Array[Slot] = []


func get_slots() -> Array[Slot]:
	return _slots


## Adds items and returns how many could NOT be added.
func add_item(item: ItemData, quantity: int = 1) -> int:
	if item == null or quantity <= 0:
		return quantity
	var remaining := quantity
	if item.stackable:
		for slot in _slots:
			if slot.item == item and slot.quantity < item.get_max_stack():
				var add := mini(remaining, item.get_max_stack() - slot.quantity)
				slot.quantity += add
				remaining -= add
				if remaining == 0:
					break
	while remaining > 0 and _slots.size() < MAX_SLOTS:
		var add := mini(remaining, item.get_max_stack())
		_slots.append(Slot.new(item, add))
		remaining -= add
	if remaining != quantity:
		changed.emit()
	return remaining


func remove_item(item: ItemData, quantity: int = 1) -> bool:
	if count_of(item) < quantity:
		return false
	var remaining := quantity
	for i in range(_slots.size() - 1, -1, -1):
		var slot := _slots[i]
		if slot.item != item:
			continue
		var take := mini(remaining, slot.quantity)
		slot.quantity -= take
		remaining -= take
		if slot.quantity <= 0:
			_slots.remove_at(i)
		if remaining == 0:
			break
	changed.emit()
	return true


func count_of(item: ItemData) -> int:
	var total := 0
	for slot in _slots:
		if slot.item == item:
			total += slot.quantity
	return total


func has_item(item: ItemData) -> bool:
	return count_of(item) > 0


func is_full() -> bool:
	return _slots.size() >= MAX_SLOTS


func to_save_data() -> Array:
	var out := []
	for slot in _slots:
		out.append({"path": slot.item.resource_path, "quantity": slot.quantity})
	return out


func load_save_data(data: Array) -> void:
	_slots.clear()
	for entry in data:
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			push_warning("Inventory: missing item resource %s" % path)
			continue
		var item := load(path) as ItemData
		if item:
			_slots.append(Slot.new(item, int(entry.get("quantity", 1))))
	changed.emit()
