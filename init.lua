-- Duane's realms floaters.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


local floaters = {}
local mod = floaters
local mod_name = 'floaters'

local falling = {}
local max_height = 31000
local shell_thick = 30


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
local node = mod.node


-- Make a duplicate of a node definition.
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


-- floater-specific nodes
do
	local newnode = mod.clone_node('air')
	newnode.description = 'Airy Barrier'
	newnode.walkable = true
	newnode.floodable = false
	minetest.register_node(mod_name..':airy_barrier', newnode)
end


function mod.generate(_parms_)
	local minp, maxp = _parms_.isect_minp, _parms_.isect_maxp
	local water_level = _parms_.sealevel
	local area, data, p2data = _parms_.area, _parms_.data, _parms_.vmparam2

	--local chunksize = tonumber(minetest.settings:get('chunksize') or 5)
	--local chunk_offset = math.floor(chunksize / 2) * 16;

	local csize = vector.add(vector.subtract(maxp, minp), 1)

	local ps = PcgRandom(_parms_.chunk_seed + 7712)

	-- Find all falling nodes.
	if not falling[node['default:sand'] ] then
		for k, v in pairs(minetest.registered_nodes) do
			if v.groups and v.groups.falling_node then
				falling[node[v.name] ] = true
			end
		end
	end

	-- just a few 2d noises
	local ground_noise_map = realms.get_noise2d('floaters_over', nil, nil, nil, {x=csize.x, y=csize.z}, { x = minp.x, y = minp.z })
	local under_noise_map = realms.get_noise2d('floaters_under', nil, nil, nil, {x=csize.x, y=csize.z}, { x = minp.x, y = minp.z })
	local base_noise_map = realms.get_noise2d('floaters_base', nil, nil, nil, {x=csize.x, y=csize.z}, { x = minp.x, y = minp.z })

	local heightmap = {}
	local reverse_heightmap = {}
	local base_base_level = water_level + 63

	local height_min = max_height
	local height_max = max_height
	local surface = {}

	-- terrain height calculations
	local index = 1
	for z = minp.z, maxp.z do
		surface[z] = {}
		for x = minp.x, maxp.x do
			local base_level = base_base_level + math.abs(base_noise_map[index])
			local ground_1 = ground_noise_map[index]
			local height = ground_1 + base_level
			local depth = base_level - under_noise_map[index]

			height = math.floor(height + 0.5)
			depth = math.floor(depth + 0.5)
			reverse_heightmap[index] = depth
			if depth >= base_level then
				height = -max_height
			end
			heightmap[index] = height
			surface[z][x] = { top = height }
			if height > _parms_.sealevel then
				surface[z][x].biome = realms.undefined_biome
			else
				surface[z][x].biome = realms.undefined_underwater_biome
			end

			height_max = math.max(ground_1, height_max)
			height_min = math.min(ground_1, height_min)

			index = index + 1
		end
	end

	local grassmap = {}
	local biomemap = {}
	local ystride = area.ystride

	local n_stone = node['default:stone']
	local n_air = node['air']
	local n_water = node['default:water_source']
	local n_glass = node[mod_name..':airy_barrier']

	-- Let realms do the biomes.
	_parms_.share.surface=surface
	if _parms_.biomefunc~=nil then
		realms.rmf[_parms_.biomefunc](_parms_)
	end

	-- Loop through every horizontal space.
	local index = 1
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local height = heightmap[index]
			local sfc=_parms_.share.surface[z][x]
			local biome=sfc.biome

			-- depths
			local depth_filler = sfc.filler_depth or 0  -- 1?
			local depth_top = sfc.top_depth or 0  -- 6?!
			local wtd = biome.node_water_top_depth or 0
			local grass_p2 = grassmap[index] or 0

			local fill_1 = height - depth_top
			local fill_2 = fill_1 - math.max(0, depth_filler)

			-- biome-determined nodes
			local stone = biome.node_stone or n_stone
			local filler = biome.node_filler or n_air
			local top = biome.node_top or n_air
			local riverbed = biome.node_riverbed
			local ww = biome.water or node['default:water_source']
			local wt = node[biome.node_water_top]

			-- Figure out the tops and bottoms.
			local pheight = math.abs(math.floor((height - minp.y + math.abs(reverse_heightmap[index] - minp.y)) / 10) - 10)
			local min_y = reverse_heightmap[index]
			local min_y_chunk = math.max(minp.y, min_y)
			local cave_high = math.min(height - shell_thick, maxp.y - pheight)
			local cave_low = math.max(min_y + shell_thick, minp.y + pheight)

			-- Start at the bottom and fill up.
			local ivm = area:index(x, min_y_chunk, z)
			for y = min_y_chunk, maxp.y do
				if y < min_y then
					-- below the terrain
				elseif y > height and y <= water_level then
					-- rivers or lakes (There are none.)
					if y > water_level - wtd then
						data[ivm] = wt
					else
						data[ivm] = ww
					end
					p2data[ivm] = 0
				elseif y == height and y <= water_level then
					-- river/lakebeds (none)
					data[ivm] = riverbed
					p2data[ivm] = 0
				elseif y <= height and y > fill_1 then
					-- topping up

					-- Check for sand where it might fall
					--  (and crash the server).
					if y == min_y and falling[top] then
						data[ivm] = n_stone
					else
						data[ivm] = top
					end

					-- decorate
					if biome.decorate and y == height then
						biome.decorate(x,y+1,z, biome, _parms_)
					end

					p2data[ivm] = grass_p2 --  + 0
				elseif filler and y <= height and y > fill_2 then
					-- filling

					-- Again, no falling sand.
					if y == min_y and falling[filler] then
						data[ivm] = n_stone
					else
						data[ivm] = filler
					end
					p2data[ivm] = 0
				elseif y <= cave_high and y >= cave_low then
					-- This is a cave.
				elseif y <= height then
					-- Otherwise, it's stoned.
					data[ivm] = stone
					p2data[ivm] = 0
				end

				ivm = ivm + ystride
			end

			-- Place water down to the bottom of the chunk.
			--  Don't raise sea level above the lowest chunk or
			--  hijinks will result.
			if minp.y < water_level then
				local ivm = area:index(x, minp.y, z)
				for y = minp.y, water_level do
					if data[ivm] == n_air then
						if y == minp.y then
							data[ivm] = n_glass
						else
							data[ivm] = n_water
						end
						p2data[ivm] = 0
					end

					ivm = ivm + ystride
				end
			end

			index = index +	1
		end
	end
end

-- Define the noises.
realms.register_noise( 'floaters_base', {offset = 0, scale = 50, seed = 2567, spread = {x = 250, y = 250, z = 250}, octaves = 3, persist = 0.5, lacunarity = 2} )
realms.register_noise( 'floaters_over', {offset = -20, scale = 25, seed = 4877, spread = {x = 200, y = 200, z = 200}, octaves = 4, persist = 0.8, lacunarity = 2} )
realms.register_noise( 'floaters_under', {offset = 0, scale = 75, seed = 4877, spread = {x = 200, y = 200, z = 200}, octaves = 7, persist = 0.6, lacunarity = 2} )

realms.register_mapgen('tg_floaters', mod.generate)