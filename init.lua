-- Duane's realms floaters init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


floaters = {}
local mod = floaters
mod.mod_name = 'floaters'
local mod_name = mod.mod_name

mod.version = '20190802'
mod.path = minetest.get_modpath(minetest.get_current_modname())


dofile(mod.path .. '/tg_floaters.lua')
