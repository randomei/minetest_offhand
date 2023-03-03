local minetest, math, controls = minetest, math, controls
offhand = {}

local max_offhand_px = 128
-- only supports up to 128px textures

-- register offhand inventory
minetest.register_on_joinplayer(function(player)
    local inv = player:get_inventory()
    inv:set_size("offhand", 1)
end)

-- move items to bones upon death
-- extra check for table because "bones (redo)" doesn't have it
if minetest.get_modpath("bones") and bones.player_inventory_lists ~= nil then
    table.insert(bones.player_inventory_lists, "offhand")
end

-- add support for player emitted light
if minetest.get_modpath("wielded_light") then
    wielded_light.register_player_lightstep(function(player)
        wielded_light.track_user_entity(player, "offhand", offhand.get_offhand(player):get_name())
    end)
end

-- switch itemstacks between main hand and offhand
local function switch_hands(player)
    local inv = player:get_inventory()
    local mainhand_stack = player:get_wielded_item()
    local offhand_stack = inv:get_stack("offhand", 1)
    inv:set_stack("offhand", 1, mainhand_stack)
    player:set_wielded_item(offhand_stack)
end

-- set flag to prevent calling this again on the offhand handler
local is_switched = false
-- temporarily switches items between hands (for compatibility)
-- and then uses offhand item
local function use_offhand(mainhand_stack, player, pointed_thing)
    switch_hands(player)
    is_switched = true
    local offhand_stack = player:get_wielded_item()
    local offhand_def = offhand_stack:get_definition()
    local modified_stack = offhand_def.on_place(offhand_stack, player, pointed_thing)
    player:set_wielded_item(modified_stack)
    switch_hands(player)
    is_switched = false
    return mainhand_stack
end

-- either returns an inventory_image or builds a 3D preview of the node
local function build_inventory_icon(itemdef)
    if itemdef.inventory_image ~= "" then
        return itemdef.inventory_image .. "^[resize:" .. max_offhand_px .. "x" .. max_offhand_px
    elseif not itemdef.tiles then
        return "blank.png"
    end
    local tiles = {
        itemdef.tiles[1],
        itemdef.tiles[3] or itemdef.tiles[1],
        itemdef.tiles[5] or itemdef.tiles[3] or itemdef.tiles[1]
    }
    for i, tile in pairs(tiles) do
        if (type(tile) == "table") then
            tiles[i] = tile.name
        end
    end
    local textures = table.concat(tiles, "{")
    return "[inventorycube{" .. (textures:gsub("%^", "&")) .. "^[resize:" .. max_offhand_px .. "x" ..max_offhand_px
end

-- switch items between hands on configured key press
local function register_switchkey()
    local switch_key = minetest.settings:get("offhand_key") or "aux1"
    if switch_key == "none" then
        return
    end
    controls.register_on_press(function(player, control_name)
        if control_name ~= switch_key then
            return
        elseif switch_key == "zoom" and player:get_wielded_item():get_name() == "binoculars:binoculars" then
            return
        end
        switch_hands(player)
    end)
end
register_switchkey()

-- overwrite item placement to utilize offhand functionality instead
-- special tools will usually not invoke this when they set a custom handler
local item_place = minetest.item_place
minetest.item_place = function(mainhand_stack, player, pointed_thing)
    local inv = player:get_inventory()
    if not is_switched
            and minetest.registered_tools[mainhand_stack:get_name()] ~= nil
            and not inv:get_stack("offhand", 1):is_empty() then
        return use_offhand(mainhand_stack, player, pointed_thing)
    end
    return item_place(mainhand_stack, player, pointed_thing)
end


function offhand.get_offhand(player)
    return player:get_inventory():get_stack("offhand", 1)
end

local function offhand_get_wear(player)
    return offhand.get_offhand(player):get_wear()
end

local function offhand_get_count(player)
    return offhand.get_offhand(player):get_count()
end

minetest.register_on_joinplayer(function(player, last_login)
    offhand[player] = {
        hud = {},
        last_wear = offhand_get_wear(player),
        last_count = offhand_get_count(player)
    }
end)

local function remove_hud(player, hud)
    local offhand_hud = offhand[player].hud[hud]
    if offhand_hud then
        player:hud_remove(offhand_hud)
        offhand[player].hud[hud] = nil
    end
end

function rgb_to_hex(r, g, b)
    return string.format("%02x%02x%02x", r, g, b)
end

local function update_wear_bar(player, itemstack)
    local wear_bar_percent = (65535 - offhand_get_wear(player)) / 65535

    local color = {255, 255, 255}
    local wear = itemstack:get_wear() / 65535;
    local wear_i = math.min(math.floor(wear * 600), 511);
    wear_i = math.min(wear_i + 10, 511);
    if wear_i <= 255 then
        color = {wear_i, 255, 0}
    else
        color = {255, 511 - wear_i, 0}
    end
    local wear_bar = offhand[player].hud.wear_bar
    player:hud_change(wear_bar, "text", "offhand_wear_bar.png^[colorize:#" .. rgb_to_hex(color[1], color[2], color[3]))
    player:hud_change(wear_bar, "scale", {
        x = 40 * wear_bar_percent,
        y = 3
    })
    player:hud_change(wear_bar, "offset", {
        x = -320 - (20 - player:hud_get(wear_bar).scale.x / 2),
        y = -13
    })
end

minetest.register_globalstep(function(dtime)
    for _, player in pairs(minetest.get_connected_players()) do
        local itemstack = offhand.get_offhand(player)
        local offhand_item = itemstack:get_name()
        local offhand_hud = offhand[player].hud
        local item = minetest.registered_items[offhand_item]
        if offhand_item ~= "" and item then
            local item_texture = build_inventory_icon(item)
            local position = {
                x = 0.5,
                y = 1
            }
            local offset = {
                x = -320,
                y = -32
            }

            if not offhand_hud.slot then
                offhand_hud.slot = player:hud_add({
                    hud_elem_type = "image",
                    position = position,
                    offset = offset,
                    scale = {
                        x = 2.75,
                        y = 2.75
                    },
                    text = "offhand_slot.png",
                    z_index = 0
                })
            end
            if not offhand_hud.item then
                offhand_hud.item = player:hud_add({
                    hud_elem_type = "image",
                    position = position,
                    offset = offset,
                    scale = {
                        x = 0.4,
                        y = 0.4
                    },
                    text = item_texture,
                    z_index = 1
                })
            else
                player:hud_change(offhand_hud.item, "text", item_texture)
            end
            if not offhand_hud.wear_bar_bg and minetest.registered_tools[offhand_item] then
                if offhand_get_wear(player) > 0 then
                    local texture = "offhand_wear_bar.png^[colorize:#000000"
                    offhand_hud.wear_bar_bg = player:hud_add({
                        hud_elem_type = "image",
                        position = {
                            x = 0.5,
                            y = 1
                        },
                        offset = {
                            x = -320,
                            y = -13
                        },
                        scale = {
                            x = 40,
                            y = 3
                        },
                        text = texture,
                        z_index = 2
                    })
                    offhand_hud.wear_bar = player:hud_add({
                        hud_elem_type = "image",
                        position = {
                            x = 0.5,
                            y = 1
                        },
                        offset = {
                            x = -320,
                            y = -13
                        },
                        scale = {
                            x = 10,
                            y = 3
                        },
                        text = texture,
                        z_index = 3
                    })
                    update_wear_bar(player, itemstack)
                end
            end

            if not offhand_hud.item_count and offhand_get_count(player) > 1 then
                offhand_hud.item_count = player:hud_add({
                    hud_elem_type = "text",
                    position = {
                        x = 0.5,
                        y = 1
                    },
                    offset = {
                        x = -298,
                        y = -18
                    },
                    scale = {
                        x = 1,
                        y = 1
                    },
                    alignment = {
                        x = -1,
                        y = 0
                    },
                    text = offhand_get_count(player),
                    z_index = 4,
                    number = 0xFFFFFF
                })
            end

            if offhand_hud.wear_bar then
                if offhand_hud.last_wear ~= offhand_get_wear(player) then
                    update_wear_bar(player, itemstack)
                    offhand_hud.last_wear = offhand_get_wear(player)
                end
                if offhand_get_wear(player) <= 0 or not minetest.registered_tools[offhand_item] then
                    remove_hud(player, "wear_bar_bg")
                    remove_hud(player, "wear_bar")
                end
            end

            if offhand_hud.item_count then
                if offhand_hud.last_count ~= offhand_get_count(player) then
                    player:hud_change(offhand_hud.item_count, "text", offhand_get_count(player))
                    offhand_hud.last_count = offhand_get_count(player)
                end
                if offhand_get_count(player) <= 1 then
                    remove_hud(player, "item_count")
                end
            end

        elseif offhand_hud.slot then
            for index, _ in pairs(offhand[player].hud) do
                remove_hud(player, index)
            end
        end
    end
end)

minetest.register_allow_player_inventory_action(function(player, action, inventory, inventory_info)
    if action == "move" and inventory_info.to_list == "offhand" then
        local itemstack = inventory:get_stack(inventory_info.from_list, inventory_info.from_index)
        --[[if not (minetest.get_item_group(itemstack:get_name(), "offhand_item") > 0)  then
			return 0
		else]]
        return itemstack:get_stack_max()
        -- end
    end
end)

--[[minetest.register_on_player_inventory_action(function(player, action, inventory, inventory_info)
    local from_offhand = inventory_info.from_list == "offhand"
    local to_offhand = inventory_info.to_list == "offhand"
    if action == "move" and from_offhand or to_offhand then
        --mcl_inventory.update_inventory_formspec(player)
    end
end)]]

if minetest.settings:get_bool("offhand_wieldview", true) then
    dofile(minetest.get_modpath(minetest.get_current_modname()).."/wield3d_offhand/wield3d.lua")
end