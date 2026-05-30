extends Reference

# Identifies Brotato shop scenes by walking the script inheritance chain.
# Works regardless of whether other mods (e.g. HordeMode) have extended
# shop.gd or coop_shop.gd, because their extensions still inherit from
# the vanilla shop classes.

const SHOP_SCRIPT_PATHS = [
	"res://ui/menus/shop/base_shop.gd",
	"res://ui/menus/shop/shop.gd",
	"res://ui/menus/shop/coop_shop.gd",
]


static func is_shop(node: Node) -> bool:
	var script = node.get_script()
	while script != null:
		if SHOP_SCRIPT_PATHS.has(script.resource_path):
			return true
		script = script.get_base_script()
	return false


# Fallback for when node_added missed a shop (e.g. it existed before the
# signal was connected). Returns null if no shop is in the current scene.
static func find_shop_in_tree(tree: SceneTree):
	var current_scene = tree.current_scene
	if current_scene == null:
		return null
	if is_shop(current_scene):
		return current_scene
	return _find_recursive(current_scene)


static func _find_recursive(node: Node):
	for child in node.get_children():
		if is_shop(child):
			return child
		var found = _find_recursive(child)
		if found != null:
			return found
	return null
