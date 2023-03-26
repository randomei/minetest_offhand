if minetest.get_modpath("mcl_offhand") ~= nil then
    minetest.log("error", "Deactivating offhand mod because it is incompatible with Mineclone")
    return
end

offhand = {}

local max_offhand_px = 128
local hotbar_size = tonumber(minetest.settings:get("offhand_hotbar_size") or 64)

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

-- event handler when item changes
-- call signature: func(player, item_before, item_after)
local change_handlers = {}
function offhand.register_on_item_change(func)
    table.insert(change_handlers, func)
end

local function update_offhand(player, item_before, item_after)
    for _, func in pairs(change_handlers) do
        func(player, item_before, item_after)
    end
end

-- switch itemstacks between main hand and offhand
local function switch_hands(player)
    local inv = player:get_inventory()
    local mainhand_stack = player:get_wielded_item()
    local offhand_stack = inv:get_stack("offhand", 1)
    inv:set_stack("offhand", 1, mainhand_stack)
    player:set_wielded_item(offhand_stack)
end

local function do_nothing(itemstack) return itemstack end

-- set flag to prevent calling this again on the offhand handler
local is_switched = false
-- temporarily switches items between hands (for compatibility)
-- and then uses offhand item
local function use_offhand(secondary, mainhand_stack, player, pointed_thing, ...)
    switch_hands(player)
    is_switched = true
    local offhand_stack = player:get_wielded_item()
    local offhand_def = offhand_stack:get_definition()
    local use = offhand_def.on_place
    if secondary then use = offhand_def.on_secondary_use or do_nothing end
    local modified_stack = use(offhand_stack, player, pointed_thing, ...)
    -- don't change itemstack when handler returns nil
    if modified_stack == nil then modified_stack = offhand_stack end
    player:set_wielded_item(modified_stack)
    switch_hands(player)
    is_switched = false
    update_offhand(player, offhand_stack, modified_stack)
    return mainhand_stack
end

local function get_tile_name(tiledef)
    if type(tiledef) == "table" then return tiledef.name end
    return tiledef
end

-- either returns an inventory_image or builds a 3D preview of the node
local function build_inventory_icon(itemdef)
    if itemdef.inventory_image and itemdef.inventory_image ~= "" then
        return itemdef.inventory_image .. "^[resize:" .. max_offhand_px .. "x" .. max_offhand_px
    elseif not itemdef.tiles or not itemdef.tiles[1] then
        return "blank.png^[resize:" .. max_offhand_px .. "x" ..max_offhand_px
    end
    local tiles = {
        get_tile_name(itemdef.tiles[1]) .. "^[resize:" .. max_offhand_px .. "x" .. max_offhand_px,
        get_tile_name(itemdef.tiles[3] or itemdef.tiles[1]) .. "^[resize:" .. max_offhand_px .. "x" .. max_offhand_px,
        get_tile_name(itemdef.tiles[5] or itemdef.tiles[3] or itemdef.tiles[1]) .. "^[resize:" .. max_offhand_px .. "x" .. max_offhand_px
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
        local item_before = player:get_wielded_item()
        local item_after = offhand.get_offhand(player)
        update_offhand(player, item_before, item_after)
    end)
end
register_switchkey()

-- overwrite item placement to utilize offhand functionality instead
-- special tools will usually not invoke this when they set a custom handler
local item_place = minetest.item_place
minetest.item_place = function(mainhand_stack, player, pointed_thing, ...)
    if not player or not player:is_player() then
        return item_place(mainhand_stack, player, pointed_thing, ...)
    end
    local inv = player:get_inventory()
    local stackname = mainhand_stack:get_name()
    if not is_switched
            and (stackname == "" or minetest.registered_tools[stackname] ~= nil)
            and not inv:get_stack("offhand", 1):is_empty() then
        return use_offhand(false, mainhand_stack, player, pointed_thing, ...)
    end
    return item_place(mainhand_stack, player, pointed_thing, ...)
end

local function get_pointed_thing(player, itemstack)
    --- determine pointing range
    local itemdef = itemstack:get_definition()
    local range = itemdef.range
    if not itemdef.range then
        -- use empty hand's range
        local hand = minetest.registered_items[""]
        range = hand.range or 5
    end
    -- adjust player position
    local pos1 = player:get_pos()
    pos1 = pos1 + player:get_eye_offset()
    pos1.y = pos1.y + (player:get_properties()).eye_height
    -- cast ray from player's eyes
    local pos2 = vector.add(pos1, vector.multiply(player:get_look_dir(), range))
    local ray = Raycast(pos1, pos2, false, false)
    -- iterate through passed nodes and determine if pointable
    local result = nil
    for pointed_thing in ray do
        if pointed_thing.type == "node" then
            local node = minetest.get_node(pointed_thing.under)
            local nodedef = minetest.registered_nodes[node.name]
            if nodedef and nodedef.pointable ~= false then
                result = pointed_thing
                break
            end
        else
            result = nil
            break
        end
    end
    return result
end

-- detect right-click in the air when tool has no on_secondary_use handler
controls.register_on_press(function(player, control_name)
    if control_name ~= "place" then return end
    local mainhand = player:get_wielded_item()
    local stackname = mainhand:get_name() or ""
    -- tool already implements own handler, skip
    if mainhand and mainhand.on_secondary_use then return end
    -- not actually a tool, skip
    if stackname ~= "" and minetest.registered_tools[stackname] == nil then return end
    -- looking at ground -> normal on_use will be called, skip
    if get_pointed_thing(player, mainhand) ~= nil then return end
    return use_offhand(true, mainhand, player, { type = "nothing" })
end)

function offhand.get_offhand(player)
    if is_switched then
        return player:get_wielded_item()
    end
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

local function rgb_to_hex(r, g, b)
    return string.format("%02x%02x%02x", r, g, b)
end

local function update_wear_bar(player, itemstack)
    local wear_bar_percent = (65535 - offhand_get_wear(player)) / 65535

    local color
    local wear = itemstack:get_wear() / 65535;
    local wear_i = math.min(math.floor(wear * 600), 511);
    wear_i = math.min(wear_i + 10, 511);
    if wear_i <= 255 then
        color = {wear_i, 255, 0}
    else
        color = {255, 511 - wear_i, 0}
    end
    local wear_bar = offhand[player].hud.wear_bar
    local hotbar_offset = - hotbar_size * (offhand[player].hotbar_count + 1) / 2
    player:hud_change(wear_bar, "text", "offhand_wear_bar.png^[colorize:#" .. rgb_to_hex(color[1], color[2], color[3]))
    player:hud_change(wear_bar, "scale", {
        x = 40 * wear_bar_percent,
        y = 3
    })
    player:hud_change(wear_bar, "offset", {
        x = hotbar_offset - (20 - player:hud_get(wear_bar).scale.x / 2),
        y = -13
    })
end

minetest.register_globalstep(function(dtime)
    for _, player in pairs(minetest.get_connected_players()) do
        local itemstack = offhand.get_offhand(player)
        local offhand_item = itemstack:get_name()
        local offhand_hud = offhand[player].hud
        local item = minetest.registered_items[offhand_item]

        -- reset hud overlay if hotbar size changed
        local hotbar_count = player:hud_get_hotbar_itemcount()
        if hotbar_count ~= offhand[player].hotbar_count then
            for index, _ in pairs(offhand[player].hud) do
                remove_hud(player, index)
            end
        end
        offhand[player].hotbar_count = hotbar_count

        if offhand_item ~= "" and item then
            local item_texture = build_inventory_icon(item)
            local position = {
                x = 0.5,
                y = 1
            }
            local offset = {
                x = - hotbar_size * (hotbar_count + 1) / 2,
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
                            x = offset.x,
                            y = offset.y + 19
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
                            x = offset.x,
                            y = offset.y + 19
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
                        x = offset.x + 22,
                        y = offset.y + 14
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
        return itemstack:get_stack_max()
    end
end)

if minetest.settings:get_bool("offhand_wieldview", true) then
    --dofile(minetest.get_modpath(minetest.get_current_modname()).."/wield3d_offhand/wield3d.lua")
    dofile(minetest.get_modpath(minetest.get_current_modname()) .. DIR_DELIM .. "wielditem.lua")
end