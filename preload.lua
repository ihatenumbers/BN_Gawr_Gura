local mod = game.mod_runtime[game.current_mod]
local ui = require("lib.ui")

mod.trident_summoned = false
mod.shark_call_auto = false

-- SUMMON_TRIDENT — bionic-claws-style toggle
game.mutation_functions["SUMMON_TRIDENT"] = {
    on_activate = function(params)
        gdebug.log_info("GawrGura: SUMMON_TRIDENT on_activate")
        local who = params.user
        if not who:as_avatar() then return end

        if mod.trident_summoned then
            gapi.add_msg("Your trident is already at your side.")
            return
        end

        -- Don't duplicate if one already exists in inventory
        if who:has_item_with_id(ItypeId.new("trident_gura"), false) then
            mod.trident_summoned = true
            gapi.add_msg("Your trident awaits in your inventory — wield it to summon it forth.")
            return
        end

        local trident = who:create_item(ItypeId.new("trident_gura"), 1)
        if not trident then
            gapi.add_msg(MsgType.bad, "The ocean fails to answer your call...")
            return
        end

        local wielded = who:wield(trident)
        mod.trident_summoned = true
        if wielded then
            gapi.add_msg("Gawr Gura's Trident surges from the depths into your grip!")
        else
            gapi.add_msg("The trident appears in your inventory, awaiting your grasp.")
        end
    end,

    on_deactivate = function(params)
        gdebug.log_info("GawrGura: SUMMON_TRIDENT on_deactivate")
        local who = params.user
        if not who:as_avatar() then return end

        who:unwield()
        mod.trident_summoned = false
        gapi.add_msg("Your trident fades into your inventory.")
    end
}

-- SHARK_CALL — one-shot timed buff (auto-deactivates after use)
game.mutation_functions["SHARK_CALL"] = {
    on_activate = function(params)
        gdebug.log_info("GawrGura: SHARK_CALL on_activate")
        local who = params.user
        if not who:as_avatar() then return end

        local stored_kcal = who:get_stored_kcal()
        if stored_kcal < 500 then
            gapi.add_msg(MsgType.bad, "You don't have enough energy reserves to call the shark spirit!")
            return
        end

        local intensity = math.min(5, math.max(1, math.floor(stored_kcal / 4000)))
        local kcal_burn = math.min(stored_kcal, intensity * 800)

        if stored_kcal - kcal_burn < 1000 then
            local warning = "Calling the shark spirit will burn " .. tostring(kcal_burn)
                .. " calories, leaving you dangerously starved. Are you sure?"
            if not ui.query_yn(warning) then return end
        end

        who:mod_stored_kcal(-kcal_burn)

        local duration_seconds = 30 + (intensity * 30)
        who:add_effect(EffectTypeId.new("shark_call_buff"),
            TimeDuration.from_seconds(duration_seconds), intensity)

        gapi.add_msg(MsgType.good,
            "You call upon the spirit of the shark! A surge of power courses through your body!")

        mod.shark_call_auto = true
        who:deactivate_mutation_id(MutationBranchId.new("SHARK_CALL"))
    end,

    on_deactivate = function(params)
        gdebug.log_info("GawrGura: SHARK_CALL on_deactivate")
        local who = params.user
        if not who:as_avatar() then return end

        if mod.shark_call_auto then
            mod.shark_call_auto = false
            return
        end

        who:remove_effect(EffectTypeId.new("shark_call_buff"))
        gapi.add_msg("The shark spirit recedes, leaving you winded but satisfied.")
    end
}

-- Awakened trident cone: cast spell on melee attack while buffed
game.add_hook("on_creature_melee_attacked", function(params)
    local char = params.char
    if not char then return end
    if not char:as_avatar() then return end
    if not mod.trident_summoned then return end
    if not char:has_effect(EffectTypeId.new("shark_call_buff")) then return end
    if math.random(100) > 35 then return end

    local spell = SpellSimple.new(SpellTypeId.new("gura_trident_cone"), false)
    spell:cast(char, params.target:get_pos_ms())
end)

-- Electroreception — passive periodic detection pulse through walls
mod.electroreception_seen = {}
gapi.add_on_every_x_hook(TimeDuration.from_seconds(3), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end
    if not avatar:has_trait(MutationBranchId.new("ELECTRORECEPTION_SAME")) then return end

    local avatar_pos = avatar:get_pos_ms()

    local monsters = gapi.get_all_monsters()
    local current_keys = {}
    local new_detections = {}

    for i, mon in ipairs(monsters) do
        if not avatar:sees(mon) then
            local mon_pos = mon:get_pos_ms()
            if coords.rl_dist(avatar_pos, mon_pos) <= 5 then
                local key = mon_pos.x .. "," .. mon_pos.y .. "," .. mon_pos.z
                current_keys[key] = true
                if not mod.electroreception_seen[key] then
                    local delta = Tripoint.new(mon_pos.x - avatar_pos.x,
                        mon_pos.y - avatar_pos.y, mon_pos.z - avatar_pos.z)
                    table.insert(new_detections, {
                        name = mon:name(1),
                        dir = gapi.direction_name(gapi.direction_from(delta))
                    })
                end
            end
        end
    end

    for _, d in ipairs(new_detections) do
        gapi.add_msg("Your electroreceptors tingle: " .. d.name .. " to the " .. d.dir .. ".")
    end

    mod.electroreception_seen = current_keys
end)

-- Shark Bite: 20% chance to heal 1 HP on melee kill
game.add_hook("on_mon_death", function(params)
    local killer = params.killer
    if not killer then return end

    local char = killer:as_character()
    if not char then return end
    if not char:has_trait(MutationBranchId.new("SHARK_BITE")) then return end

    -- Skip if killed with any ranged weapon (gun, crossbow, bow, etc.)
    local weapon = nil
    for _, it in ipairs(char:all_items(false)) do
        if char:is_wielding(it) then
            weapon = it
            break
        end
    end
    if weapon then
        if weapon:is_gun() then
            return
        end
        if weapon:has_flag(JsonFlagId.new("PRIMITIVE_RANGED_WEAPON")) then
            return
        end
    end

    if math.random(100) > 120 then return end

    -- Heal 1 HP per wounded body part (only if actually wounded)
    if char:get_hp() < char:get_hp_max() then
        char:healall(1)
        gapi.add_msg(MsgType.good, "You tear into your fallen prey and feel your wounds knit!")
    end
end)

-- COSMETIC MOOD SYSTEM (Tail + Expressions)
-- Swaps cosmetic-only mutation overlays based on avatar morale level.
-- The existing TAIL_SHARK mutation handles gameplay; mood variants
-- handle the visual overlay that changes with happiness/sadness.
-- cosmetic_tail / cosmetic_expression start as nil, hook owns init

local TAIL_MAP = {
    happy   = MutationBranchId.new("TAIL_SHARK_HAPPY"),
    neutral = MutationBranchId.new("TAIL_SHARK_NEUTRAL"),
    sad     = MutationBranchId.new("TAIL_SHARK_SAD"),
}
local EXPRESSION_MAP = {
    happy   = MutationBranchId.new("EXPRESSION_GURA_HAPPY"),
    neutral = MutationBranchId.new("EXPRESSION_GURA_NEUTRAL"),
    sad     = MutationBranchId.new("EXPRESSION_GURA_SAD"),
}

local function mood_tier_from_morale(morale)
    if morale > 50 then return "happy" end
    if morale < -50 then return "sad" end
    return "neutral"
end

local function swap_cosmetic_mutation(avatar, current_id, new_id)
    if current_id == new_id then return current_id end
    avatar:unset_mutation(current_id)
    avatar:set_mutation(new_id)
    return new_id
end

gapi.add_on_every_x_hook(TimeDuration.from_seconds(30), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end
    if not avatar:has_trait(MutationBranchId.new("TAIL_SHARK")) then return end

    -- Init if first run: nil check handles old saves cleanly
    if mod.cosmetic_tail == nil then
        avatar:unset_mutation(TAIL_MAP.happy)
        avatar:unset_mutation(TAIL_MAP.sad)
        avatar:unset_mutation(EXPRESSION_MAP.happy)
        avatar:unset_mutation(EXPRESSION_MAP.sad)
        avatar:unset_mutation(TAIL_MAP.neutral)
        avatar:unset_mutation(EXPRESSION_MAP.neutral)
        avatar:set_mutation(TAIL_MAP.neutral)
        avatar:set_mutation(EXPRESSION_MAP.neutral)
        mod.cosmetic_tail       = TAIL_MAP.neutral
        mod.cosmetic_expression = EXPRESSION_MAP.neutral
        return
    end

    local morale = avatar:get_morale_level()
    local tier = mood_tier_from_morale(morale)

    mod.cosmetic_tail       = swap_cosmetic_mutation(avatar, mod.cosmetic_tail,       TAIL_MAP[tier])
    mod.cosmetic_expression = swap_cosmetic_mutation(avatar, mod.cosmetic_expression, EXPRESSION_MAP[tier])
end)

-- TRIDENT RIPTIDE
-- Mouse-aimed multi-turn dash:
-- charge (ceil(dist/3) turns) → execute → reposition
-- Stops at solid terrain or creatures.
-- Getting hit during windup cancels it.

mod.dash = {
    state = "idle",
    charge_remaining = 0,
    target_tile = nil,
}

local DASH_MAX_RANGE = 12

-- Bresenham 2D line (preserves z)
local function bresenham_line(x0, y0, z, x1, y1)
    local points = {}
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    while true do
        table.insert(points, Tripoint.new(x0, y0, z))
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            if x0 == x1 then break end
            err = err - dy; x0 = x0 + sx
        end
        if e2 < dx then
            if y0 == y1 then break end
            err = err + dx; y0 = y0 + sy
        end
    end
    return points
end

local function tile_is_solid(map, pos)
    local ter = map:get_ter_at(pos)
    return ter:obj():has_flag("WALL")
        or ter:obj():has_flag("IMPASSABLE")
        or ter:obj():has_flag("BASHABLE")
end

local function can_dash(avatar)
    local ter = gapi.get_map():get_ter_at(avatar:get_pos_ms())
    return ter:obj():has_flag("SWIMMABLE")
        or avatar:has_morale(MoraleTypeDataId.new("morale_wet"))
end

local function execute_dash(avatar)
    local dash = mod.dash
    local target = dash.target_tile
    local map = gapi.get_map()
    local src = avatar:get_pos_ms()

    local line = bresenham_line(src.x, src.y, src.z, target.x, target.y)
    table.remove(line, 1)  -- drop starting tile

    local tiles_traveled = 0
    local hit_wall = false

    for _, tile in ipairs(line) do
        tiles_traveled = tiles_traveled + 1
        local mon = gapi.get_monster_at(tile)

        if mon then
            avatar:set_pos_ms(tile)
        elseif tile_is_solid(map, tile) then
            hit_wall = true
            break
        else
            avatar:set_pos_ms(tile)
        end
    end

    if tiles_traveled == 0 and not hit_wall then
        gapi.add_msg(MsgType.bad, "You can't dash through that!")
        return
    end

    gapi.add_msg(MsgType.good, "You surge forward with your trident!")

    local stamina_cost = 300 + (tiles_traveled * 100)
    avatar:mod_stamina(-stamina_cost)

    if hit_wall then
        local athletics = avatar:get_skill_level(SkillId.new("swimming"))
        if athletics < 5 then
            local confuse_dur = 10 - (athletics * 2)
            if confuse_dur > 0 then
                avatar:add_effect(EffectTypeId.new("stunned"), TimeDuration.from_seconds(confuse_dur))
            end
        end
    end
end

-- Cancel any active windup
local function cancel_dash(reason)
    mod.dash.state = "idle"
    mod.dash.target_tile = nil
    mod.dash.charge_remaining = 0
    gapi.add_msg(MsgType.bad, reason)
end

-- Hook: block voluntary movement during windup via on_character_try_move
-- (fires in game.cpp try_move before the move is committed)
game.add_hook("on_character_try_move", function(params)
    if mod.dash.state ~= "charging" then return end
    local char = params.char
    if not char or not char:as_avatar() then return end
    return false  -- disallow the move
end)

-- Hook: interrupt windup if avatar is hit during charge
game.add_hook("on_creature_melee_attacked", function(params)
    local char = params.char
    if not char or not char:as_avatar() then return end
    if mod.dash.state ~= "charging" then return end
    pcall(cancel_dash, "You get hit! The riptide is thrown off!")
end)

-- Per-second windup tick + dash execution (fires every real second,
-- independent of whose turn it is)
gapi.add_on_every_x_hook(TimeDuration.from_seconds(1), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end

    local dash = mod.dash
    if dash.state == "idle" then return end

    if dash.state == "charging" then
        if not can_dash(avatar) then
            pcall(cancel_dash, "You're no longer in water — the riptide fizzles!")
            return
        end

        dash.charge_remaining = dash.charge_remaining - 1
        if dash.charge_remaining > 0 then
            gapi.add_msg("Charging riptide... " .. dash.charge_remaining)
        else
            dash.state = "executing"
            gapi.add_msg(MsgType.good, "NOW!")
            pcall(execute_dash, avatar)
            dash.state = "idle"
            dash.target_tile = nil
        end
        return
    end
end)

-- iuse: trident_riptide
game.iuse_functions["trident_riptide"] = function(params)
    local who = params.user
    if not who:as_avatar() then return 0 end

    -- all_items visits wielded, worn, and inventory (visitable<Character> specialization)
    -- get_item_with_id only searches inv, missing the wielded weapon
    local wielded_trident = false
    for _, it in ipairs(who:all_items(false)) do
        if it:get_type():str() == "trident_gura" and who:is_wielding(it) then
            wielded_trident = true
            break
        end
    end
    if not wielded_trident then
        gapi.add_msg(MsgType.bad, "You must be wielding the trident to perform the riptide!")
        return 0
    end

    if mod.dash.state ~= "idle" then
        gapi.add_msg(MsgType.bad, "You're already charging a riptide!")
        return 0
    end

    if not can_dash(who) then
        gapi.add_msg(MsgType.bad, "You need to be in water or rain to dash!")
        return 0
    end

    local target = gapi.look_around()
    if not target then
        gapi.add_msg("You brace yourself, then reconsider.")
        return 0
    end

    local src = who:get_pos_ms()
    local raw_dist = math.max(math.abs(target.x - src.x), math.abs(target.y - src.y))

    if raw_dist == 0 then
        gapi.add_msg(MsgType.bad, "You're already there!")
        return 0
    end

    local land_tile = target
    local dist = math.max(math.abs(land_tile.x - src.x), math.abs(land_tile.y - src.y))

    if dist > DASH_MAX_RANGE then
        local scale = DASH_MAX_RANGE / dist
        land_tile = Tripoint.new(
            src.x + math.floor((land_tile.x - src.x) * scale + 0.5),
            src.y + math.floor((land_tile.y - src.y) * scale + 0.5),
            src.z)
        dist = math.max(math.abs(land_tile.x - src.x), math.abs(land_tile.y - src.y))
    end

    -- Windup: ceiling of dist/3, minimum 1
    local charge_turns = math.max(1, math.ceil(dist / 3))

    -- Stamina check using landing distance
    local stamina_cost = 300 + (dist * 100)
    if who:get_stamina() < stamina_cost then
        gapi.add_msg(MsgType.bad, "You're too exhausted!")
        return 0
    end

    mod.dash.target_tile = land_tile
    mod.dash.state = "charging"
    mod.dash.charge_remaining = charge_turns

    gapi.add_msg("You crouch low, gripping your trident...")
    gapi.add_msg("Winding up for " .. charge_turns .. " turns!")

    return 1
end

-- Salt Water Affinity: heal when wet
gapi.add_on_every_x_hook(TimeDuration.from_seconds(300), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end
    if not avatar:has_trait(MutationBranchId.new("SALT_WATER_AFFINITY")) then return end
    if not avatar:has_morale(MoraleTypeDataId.new("morale_wet")) then return end
    if avatar:get_hp() >= avatar:get_hp_max() then return end
    avatar:healall(1)
end)