-- Duane's realms floaters functions.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


local mod = floaters
local mod_name = 'floaters'


-- This tables looks up nodes that aren't already stored.
mod.node = setmetatable({}, {
	__index = function(t, k)
		if not (t and k and type(t) == 'table') then
			return
		end

		t[k] = minetest.get_content_id(k)
		return t[k]
	end
})


function mod.clone_node(name)
	if not (name and type(name) == 'string') then
		return
	end
	if not minetest.registered_nodes[name] then
		return
	end

	local nod = minetest.registered_nodes[name]
	local node2 = table.copy(nod)
	return node2
end
