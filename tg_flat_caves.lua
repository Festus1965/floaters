-- Duane's mapgen flat_caves.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


local mod, layers_mod
if minetest.get_modpath('realms') then
	layers_mod = realms
	mod = floaters
else
	layers_mod = mapgen
	mod = mapgen
end

local mod_name = mod.mod_name
local nodes_name = 'mapgen'

local max_height = 31000
local VN = vector.new


local node
if layers_mod.mod_name == 'mapgen' then
	node = layers_mod.node
	clone_node = layers_mod.clone_node
else
	dofile(mod.path .. '/functions.lua')
	node = mod.node
	clone_node = mod.clone_node
end


local floor_dirty_nodes = {
	'default:stone',
	'default:sandstone',
	nodes_name .. ':stone_with_lichen',
	nodes_name .. ':stone_with_algae',
	nodes_name .. ':stone_with_moss',
	nodes_name .. ':basalt',
	nodes_name .. ':granite',
}


function mod.generate_flat_caves(params)
	if not mod.floor_dirty then
		mod.floor_dirty = {}
		for _, v in pairs(floor_dirty_nodes) do
			local n = node[v]
			mod.floor_dirty[n] = true
		end
	end

	local minp, maxp = params.isect_minp, params.isect_maxp
	local area, data, p2data = params.area, params.data, params.vmparam2

	local csize = vector.add(vector.subtract(maxp, minp), 1)
	local ystride = area.ystride
	params.csize = csize

	local n_stone = node['default:stone']
	local n_air = node['air']
	local n_water = node['default:water_source']
	local n_lava = node['default:lava_source']
	local n_ice = node['default:ice']
	local n_ignore = node['ignore']
	local n_wall = 9999

	local ps = PcgRandom(params.chunk_seed + 7712)

	params.share.no_dust = true

	local bottom_fill
	local cave_layers = {}
	do
		local layer_min = params.realm_maxp.y
		local layer_max = layer_min
		local psh = PcgRandom(params.realm_seed + 6284)
		while layer_min > math.max(minp.y, params.realm_minp.y) do
			local h = psh:next(10, 50) + psh:next(10, 50)
			local dt = psh:next(1, 3)
			local d, wet
			if dt == 1 then
				d = psh:next(1, h)
				wet = true
			elseif dt == 2 then
				d = psh:next(8, 16)
			elseif dt == 3 then
				d = 1
			end

			layer_max = layer_min
			layer_min = layer_min - h
			if (layer_max >= minp.y and layer_max <= maxp.y)
			or (layer_min >= minp.y and layer_min <= maxp.y) then
				if layer_min > params.realm_minp.y then
					table.insert(cave_layers, {
						minp = VN(minp.x, layer_min + 1, minp.z),
						maxp = VN(maxp.x, layer_max, maxp.z),
						height = h,
						--lava = has_lava,
						water_level = layer_min + d - 1,
						wet = wet,
					})
				end
			end
		end

		if #cave_layers < 1 then
			bottom_fill = true
		else
			if layer_min < params.realm_minp.y then
				bottom_fill = true
			end
		end
	end

	for _, cl in pairs(cave_layers) do
		local water_level = cl.water_level
		local center = vector.divide(vector.add(cl.minp, cl.maxp), 2)
		params.share.wet_cave = cl.wet
		params.biome_height_offset = water_level

		-- just a few 2d noises
		local seedb = cl.minp.y % 1137
		local ground_noise_map = layers_mod.get_noise2d('flat_caves_terrain', nil, seedb, nil, {x=csize.x, y=csize.z}, { x = minp.x, y = minp.z })

		local surface = {}

		local index = 1
		local min_y = math.max(minp.y, cl.minp.y)
		local max_y = math.min(maxp.y, cl.maxp.y)
		for z = minp.z, maxp.z do
			surface[z] = {}
			for x = minp.x, maxp.x do
				-- These calculations are very touchy.
				local ground = ground_noise_map[index]

				if ground < -10 then
					ground = ground + 10
					--ground = - (ground * ground) - 10
					ground = (ground * ground) + 10
				elseif ground > 0 then
					---------------------------
					-- cpu drain
					---------------------------
					ground = math.sqrt(ground)
					---------------------------
				end

				local diff = math.abs(ground) * cl.height / 40
				local floor = math.floor(cl.minp.y + diff + 5.5)

				surface[z][x] = {
					top = floor,
					cave_floor = floor,
					cave_ceiling = math.ceil(center.y + (center.y - floor)),
				}

				index = index + 1
			end
		end

		-- Let realms do the biomes.
		params.share.surface = surface
		params.share.cave_layer = cl
		if params.biomefunc then
			layers_mod.rmf[params.biomefunc](params)
		end


		local csize = params.csize

		-- Loop through every horizontal space.
		local index = 1
		for z = minp.z, maxp.z do
			for x = minp.x, maxp.x do
				local surface = surface[z][x]
				local ground = center.y - surface.top

				local biome = surface.biome or {}
				local n_b_stone = biome.node_stone or n_stone
				local n_ceiling = biome.node_ceiling or biome.node_lining
				local n_floor = biome.node_floor or biome.node_lining
				local n_fluid = biome.node_cave_liquid or n_water
				local surface_depth = biome.surface_depth or 1
				local n_gas = biome.node_air or n_air

				if (not n_floor or mod.floor_dirty[n_floor])
				and ps:next(1, 8) == 1 then
					n_floor = node['default:dirt']
				end

				local ivm = area:index(x, min_y, z)
				for y = min_y, max_y do
					local diff = math.abs(center.y - y)
					if diff >= ground and diff < ground + surface_depth then
						if y < center.y then
							data[ivm] = n_floor or n_b_stone
							p2data[ivm] = 0
							--p2data[ivm] = stone_color
						else
							data[ivm] = n_ceiling or n_b_stone
							p2data[ivm] = 0
							--p2data[ivm] = stone_color
						end
					elseif diff < ground then
						if n_fluid and y <= water_level then
							data[ivm] = n_fluid
							p2data[ivm] = 0
						else
							data[ivm] = n_gas
							p2data[ivm] = 0
						end
					elseif data[ivm] == n_air then
						if diff < 10 then
							data[ivm] = n_floor or n_b_stone
						else
							data[ivm] = n_b_stone
						end
						p2data[ivm] = 0
					end

					ivm = ivm + ystride
				end

				index = index + 1
			end
		end

		if layers_mod.place_all_decorations then
			layers_mod.place_all_decorations(params, true)

			if not params.share.no_dust and layers_mod.dust then
				layers_mod.dust(params)
			end
		end
	end

	if bottom_fill then
		local max_y
		if #cave_layers < 1 then
			max_y = maxp.y
		else
			max_y = cave_layers[#cave_layers].minp.y - 1
		end

		for z = minp.z, maxp.z do
			for x = minp.x, maxp.x do
				local ivm = area:index(x, minp.y, z)
				for y = minp.y, max_y do
					data[ivm] = n_stone
					p2data[ivm] = 0

					ivm = ivm + ystride
				end
			end
		end
	end
end


-- Define the noises.
layers_mod.register_noise( 'flat_caves_terrain', {offset = 0, scale = 10, seed = 6386, spread = {x = 23, y = 23, z = 23}, octaves = 3, persist = 0.7, lacunarity = 1.8} )

layers_mod.register_mapgen('tg_flat_caves', mod.generate_flat_caves)

--[[
if layers_mod.register_spawn then
	layers_mod.register_spawn('tg_dflat', mod.get_spawn_level)
end
--]]
