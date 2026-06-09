local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]
mod.storage = storage
local ui = require("lib.ui")

mod.trident_summoned = false
mod.shark_call_auto = false
mod.dryness_counter = mod.dryness_counter or 0

-- Helper: remove all items of a given type from a character (destroys them)
local function remove_all_of_type(who, type_id)
    local items = who:all_items(false)
    for _, it in ipairs(items) do
        if it:get_type():str() == type_id then
            who:remove_item(it)
        end
    end
end

-- SUMMON_TRIDENT -- toggle that creates/wields the trident on, destroys it on off
game.mutation_functions["SUMMON_TRIDENT"] = {
    on_activate = function(params)
        gdebug.log_info("GawrGura: SUMMON_TRIDENT on_activate")
        local who = params.user
        if not who:as_avatar() then return end

        if mod.trident_summoned then
            gapi.add_msg("Your trident is already at your side.")
            return
        end

        -- Clean up stale tridents (e.g. from old saves before destruction-on-deactivate)
        remove_all_of_type(who, "trident_gura")

        local trident = who:create_item(ItypeId.new("trident_gura"), 0)
        if not trident then
            gapi.add_msg(MsgType.bad, "The trident fails to answer your call...")
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
        remove_all_of_type(who, "trident_gura")
        mod.trident_summoned = false
        gapi.add_msg("The trident disappears from your grip.")
    end
}

game.mutation_functions["SHARK_CALL"] = {
    on_activate = function(params)
        gdebug.log_info("GawrGura: SHARK_CALL on_activate")
        local who = params.user
        if not who:as_avatar() then return end

        local current_stamina = who:get_stamina()
        if current_stamina < 5000 then
            gapi.add_msg(MsgType.bad, "You are too winded to call upon the shark spirit!")
            return
        end

        local stored_kcal = who:get_stored_kcal()
        if stored_kcal < 200 then
            gapi.add_msg(MsgType.bad, "You are too starved to call upon the shark spirit!")
            return
        end

        -- Consume flat resources
        who:mod_stamina(-4000)
        who:mod_stored_kcal(-150)

        who:add_effect(EffectTypeId.new("shark_call_buff"),
            TimeDuration.from_seconds(90), 3)

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
        gapi.add_msg("The shark spirit recedes, leaving you winded.")
    end
}

-- Active Mutation: "A" (Vocal daze/shout)
game.mutation_functions["A"] = {
    on_activate = function(params)
        gdebug.log_info("GawrGura: A on_activate")
        local who = params.user
        if not who:as_avatar() then return end

        local pos = who:get_pos_ms()
        local map = gapi.get_map()
        
        -- Safe sound generation via the noise spell
        local spell = SpellSimple.new(SpellTypeId.new("gura_vocal_noise"), false)
        spell:cast(who, pos)
        
        -- Confuse/daze any adjacent hostiles
        local adjacent_points = map:points_in_radius(pos, 1)
        local hit_any = false
        for _, pt in ipairs(adjacent_points) do
            if pt ~= pos then
                local mon = gapi.get_monster_at(pt)
                if mon then
                    mon:add_effect(EffectTypeId.new("dazed"), TimeDuration.from_seconds(6))
                    gapi.add_msg(string.format("The %s stops, utterly bewildered by your vocalization.", mon:disp_name(false, true)))
                    hit_any = true
                end
            end
        end
        
        if not hit_any then
            gapi.add_msg("The empty air does not answer.  You feel slightly cute.")
        end

        -- Immediately deactivate so it functions as a one-shot shout
        who:deactivate_mutation_id(MutationBranchId.new("A"))
    end,

    on_deactivate = function(params)
        -- Handled instantly on activation
    end
}

-- Awakened trident cone: cast spell on melee attack while buffed
game.add_hook("on_creature_melee_attacked", function(params)
    local char = params.char
    if not char then return end
    if not char:as_avatar() then return end
    if not mod.trident_summoned then return end
    local is_wielding_trident = false
    for _, it in ipairs(char:all_items(false)) do
        if it:get_type():str() == "trident_gura" and char:is_wielding(it) then
            is_wielding_trident = true
            break
        end
    end
    if not is_wielding_trident then return end
    if not char:has_effect(EffectTypeId.new("shark_call_buff")) then return end
    if math.random(100) > 35 then return end

    local spell = SpellSimple.new(SpellTypeId.new("gura_trident_cone"), false)
    spell:cast(char, params.target:get_pos_ms())
end)

-- Shark Bite: chance to heal 1 HP on melee kill
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

    if math.random(100) > 80 then return end

    if char:get_hp() < char:get_hp_max() then
        -- Selects a single wounded part to heal
        local wounded_parts = {}
        for _, bp in ipairs({ "head", "torso", "arm_l", "arm_r", "leg_l", "leg_r" }) do
            if char:get_part_hp(bp) < char:get_part_hp_max(bp) then
                table.insert(wounded_parts, bp)
            end
        end
        if #wounded_parts > 0 then
            local target_bp = wounded_parts[math.random(#wounded_parts)]
            char:heal(target_bp, 2)
            gapi.add_msg(MsgType.good, "You tear into your fallen prey and feel your wounds knit!")
        end
    end
end)

-- COSMETIC MOOD SYSTEM (Tail + Expressions)
-- Swaps cosmetic-only mutation overlays based on avatar morale level.
-- The existing TAIL_SHARK mutation handles gameplay; mood variants
-- handle the visual overlay that changes with happiness/sadness.

local TAIL_MAP = {
    happy   = "TAIL_SHARK_HAPPY",
    neutral = "TAIL_SHARK_NEUTRAL",
    sad     = "TAIL_SHARK_SAD",
}
local EXPRESSION_MAP = {
    happy   = "EXPRESSION_GURA_HAPPY",
    neutral = "EXPRESSION_GURA_NEUTRAL",
    sad     = "EXPRESSION_GURA_SAD",
}

local function mood_tier_from_morale(morale)
    if morale > 50 then return "happy" end
    if morale < -50 then return "sad" end
    return "neutral"
end

-- Safely swaps mutations using strings stored in persistent storage
local function swap_cosmetic_mutation(avatar, storage_key, new_id_str)
    local old_id_str = storage[storage_key]
    if old_id_str == new_id_str then return end

    if old_id_str then
        avatar:unset_mutation(MutationBranchId.new(old_id_str))
    end
    avatar:set_mutation(MutationBranchId.new(new_id_str))
    storage[storage_key] = new_id_str
end

gapi.add_on_every_x_hook(TimeDuration.from_seconds(30), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end

    -- Cleanup block: Runs if the player doesn't have the base shark tail,
    -- but still has active tracked cosmetic states (e.g., after purification).
    if not avatar:has_trait(MutationBranchId.new("TAIL_SHARK")) then
        if storage.cosmetic_tail or storage.cosmetic_expression then
            for _, tail_id_str in pairs(TAIL_MAP) do
                avatar:unset_mutation(MutationBranchId.new(tail_id_str))
            end
            for _, expr_id_str in pairs(EXPRESSION_MAP) do
                avatar:unset_mutation(MutationBranchId.new(expr_id_str))
            end
            storage.cosmetic_tail = nil
            storage.cosmetic_expression = nil
        end
        return
    end

    -- Init if first run or newly mutated: safely handles new/cleared saves
    if not storage.cosmetic_tail then
        -- Clear any lingering states first
        for _, tail_id_str in pairs(TAIL_MAP) do
            avatar:unset_mutation(MutationBranchId.new(tail_id_str))
        end
        for _, expr_id_str in pairs(EXPRESSION_MAP) do
            avatar:unset_mutation(MutationBranchId.new(expr_id_str))
        end

        avatar:set_mutation(MutationBranchId.new(TAIL_MAP.neutral))
        avatar:set_mutation(MutationBranchId.new(EXPRESSION_MAP.neutral))
        storage.cosmetic_tail       = TAIL_MAP.neutral
        storage.cosmetic_expression = EXPRESSION_MAP.neutral
        return
    end

    local morale = avatar:get_morale_level()
    local tier = mood_tier_from_morale(morale)

    swap_cosmetic_mutation(avatar, "cosmetic_tail", TAIL_MAP[tier])
    swap_cosmetic_mutation(avatar, "cosmetic_expression", EXPRESSION_MAP[tier])
end)

-- TRIDENT RIPTIDE & TURN-BASED WINDUP ACTIVITY
mod.dash = {
    state = "idle",
    charge_remaining = 0,
    target_tile = nil,
}

local DASH_MAX_RANGE = 12

local function bresenham_line(x0, y0, z, x1, y1)
    local points = {}
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    while true do
        table.insert(points, TripointBubMs.new(x0, y0, z))
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
    local ter = map:get_ter_at(pos):obj()
    if ter:has_flag("IMPASSABLE") or ter:get_movecost() <= 0 then
        return true
    end
    local furn = map:get_furn_at(pos):obj()
    if furn:has_flag("IMPASSABLE") then
        return true
    end
    return false
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
    local hit_monster = nil
    local final_tile = src

    for _, tile in ipairs(line) do
        local mon = gapi.get_monster_at(tile)
        if mon then
            hit_monster = mon
            break
        elseif tile_is_solid(map, tile) then
            hit_wall = true
            break
        else
            final_tile = tile
            tiles_traveled = tiles_traveled + 1
        end
    end

    avatar:set_pos_ms(final_tile)

    if tiles_traveled == 0 and not hit_monster then
        gapi.add_msg(MsgType.bad, "You can't dash through that!")
        return
    end

    gapi.add_msg(MsgType.good, "You surge forward with your trident!")

    local stamina_cost = 300 + (tiles_traveled * 100)
    avatar:mod_stamina(-stamina_cost)

    if hit_monster then
        local base_dmg = 22
        local weapon = nil
        for _, it in ipairs(avatar:all_items(false)) do
            if avatar:is_wielding(it) then
                weapon = it
                break
            end
        end

        if weapon then
            local type_str = weapon:get_type():str()
            if type_str == "trident_gura" then
                base_dmg = 25
            else
                pcall(function()
                    if weapon.damage_melee then
                        local d = weapon:damage_melee("cut")
                        if d and d > 0 then base_dmg = d end
                    end
                end)
            end
        end

        local multiplier = 1.0 + (tiles_traveled * 0.25) + (math.random() * 0.1 - 0.05)
        local final_damage = math.floor(base_dmg * multiplier)

        local success, err = pcall(function() hit_monster:deal_damage(avatar, BodyPartTypeIntId.new(BodyPartTypeId.new("torso")), DamageInstance.new(6, final_damage, 0.0, 1.0, 1.0)) end)
        if not success then
            gapi.add_msg("An error occurred while dealing damage. %s", tostring(err))
        end
        gapi.add_msg(string.format("Your trident strikes the %s for %d cut damage!", hit_monster:disp_name(false, true), final_damage))

        local dx = hit_monster:get_pos_ms().x - final_tile.x
        local dy = hit_monster:get_pos_ms().y - final_tile.y
        local step_x = dx == 0 and 0 or (dx > 0 and 1 or -1)
        local step_y = dy == 0 and 0 or (dy > 0 and 1 or -1)

        local kb_dist = math.floor((avatar:get_str() / 4) + (tiles_traveled / 3))

        local p_size = 2
        pcall(function() p_size = avatar:get_size() end)
        local m_size = 2
        pcall(function() m_size = hit_monster:get_size() end)

        if m_size > p_size then
            kb_dist = kb_dist - (m_size - p_size) * 2
        end

        if kb_dist > 0 then
            local current_mon_pos = hit_monster:get_pos_ms()
            for i = 1, kb_dist do
                local next_pos = TripointBubMs.new(current_mon_pos.x + step_x, current_mon_pos.y + step_y, current_mon_pos.z)
                
                -- Check for solid obstacles behind the monster
                if tile_is_solid(map, next_pos) then
                    local wall_damage = math.floor(final_damage * 0.40)
                    pcall(function() hit_monster:deal_damage(avatar, BodyPartTypeIntId.new(BodyPartTypeId.new("torso")), DamageInstance.new(3, wall_damage, 0.0, 1.0, 1.0)) end)
                    gapi.add_msg(string.format("The %s slams into an obstacle, taking %d additional damage!", hit_monster:disp_name(false, true), wall_damage))
                    break
                end

                -- Check for secondary monsters behind the target
                local other_mon = gapi.get_monster_at(next_pos)
                if other_mon then
                    local secondary_damage = math.floor(final_damage * 0.30)
                    pcall(function() other_mon:deal_damage(avatar, BodyPartTypeIntId.new(BodyPartTypeId.new("torso")), DamageInstance.new(3, secondary_damage, 0.0, 1.0, 1.0)) end)
                    gapi.add_msg(string.format("The %s collides with %s, dealing %d secondary damage!", hit_monster:disp_name(false, true), other_mon:disp_name(false, true), secondary_damage))
                    break
                end

                -- Move the monster one step backward along the vector
                hit_monster:set_pos_ms(next_pos)
                current_mon_pos = next_pos
            end
        end
    end

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
game.add_hook("on_character_try_move", function(params)
    if mod.dash.state ~= "charging" then return end
    local char = params.char
    if not char or not char:as_avatar() then return end
    return false
end)

-- Hook: interrupt windup if avatar is hit during charge
game.add_hook("on_creature_melee_attacked", function(params)
    local char = params.char
    if not char or not char:as_avatar() then return end
    if mod.dash.state ~= "charging" then return end
    char:cancel_activity()
    pcall(cancel_dash, "You get hit! The riptide is canceled!")
end)

-- Process turn-by-turn activity checks (once per turn)
gapi.add_on_every_x_hook(TimeDuration.from_turns(1), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end

    local dash = mod.dash
    if dash.state == "idle" then return end

    if dash.state == "charging" then
        if not can_dash(avatar) then
            avatar:cancel_activity()
            pcall(cancel_dash, "You're no longer in water -- the riptide fizzles!")
            return
        end

        -- Check if windup activity is no longer active on the avatar
        local act_id = avatar.activity and (avatar.activity.id or avatar.activity.type)
        local current_act = act_id and act_id:str() or ""
        if current_act ~= "ACT_RIPTIDE_WINDUP" then
            dash.state = "executing"
            gapi.add_msg(MsgType.good, "NOW!")
            local success, err = pcall(execute_dash, avatar)
            if not success then
                gapi.add_msg(MsgType.bad, "Riptide error: " .. tostring(err))
            end
            dash.state = "idle"
            dash.target_tile = nil
        end
    end
end)

-- iuse: trident_riptide
game.iuse_functions["trident_riptide"] = function(params)
    local who = params.user
    if not who:as_avatar() then return 0 end

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
        land_tile = TripointBubMs.new(
            src.x + math.floor((land_tile.x - src.x) * scale + 0.5),
            src.y + math.floor((land_tile.y - src.y) * scale + 0.5),
            src.z)
        dist = math.max(math.abs(land_tile.x - src.x), math.abs(land_tile.y - src.y))
    end

    local charge_turns = math.max(1, math.ceil(dist / 3))

    local stamina_cost = 300 + (dist * 100)
    if who:get_stamina() < stamina_cost then
        gapi.add_msg(MsgType.bad, "You're too exhausted!")
        return 0
    end

    mod.dash.target_tile = land_tile
    mod.dash.state = "charging"
    mod.dash.charge_remaining = charge_turns

    -- Assign the turn-based player activity to lock actions
    who:assign_activity(ActivityTypeId.new("ACT_RIPTIDE_WINDUP"), charge_turns * 100, -1, -1, "")

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

gapi.add_on_every_x_hook(TimeDuration.from_seconds(60), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end

    if not avatar:has_trait(MutationBranchId.new("HYDROPHILIC")) then
        avatar:remove_effect(EffectTypeId.new("gura_dry_skin_1"))
        avatar:remove_effect(EffectTypeId.new("gura_dry_skin_2"))
        avatar:remove_effect(EffectTypeId.new("gura_dry_skin_3"))
        mod.dryness_counter = 0
        return
    end

    local map = gapi.get_map()
    local pos = avatar:get_pos_ms()
    
    local is_wet = avatar:has_morale(MoraleTypeDataId.new("morale_wet")) 
        or map:get_ter_at(pos):obj():has_flag("SWIMMABLE")
    
    if is_wet then
        if mod.dryness_counter > 0 then
            avatar:remove_effect(EffectTypeId.new("gura_dry_skin_1"))
            avatar:remove_effect(EffectTypeId.new("gura_dry_skin_2"))
            avatar:remove_effect(EffectTypeId.new("gura_dry_skin_3"))
            gapi.add_msg(MsgType.good, "You splash yourself with water.  Your skin rehydrates!")
            mod.dryness_counter = 0
        end
    else
        mod.dryness_counter = mod.dryness_counter + 1
        
        if mod.dryness_counter == 10 then
            avatar:add_effect(EffectTypeId.new("gura_dry_skin_1"), TimeDuration.from_turns(99999))
            gapi.add_msg(MsgType.bad, "Your skin is starting to feel dry.")
        elseif mod.dryness_counter == 30 then
            avatar:remove_effect(EffectTypeId.new("gura_dry_skin_1"))
            avatar:add_effect(EffectTypeId.new("gura_dry_skin_2"), TimeDuration.from_turns(99999))
            gapi.add_msg(MsgType.bad, "Your skin is uncomfortably dry and itchy.")
        elseif mod.dryness_counter == 60 then
            avatar:remove_effect(EffectTypeId.new("gura_dry_skin_2"))
            avatar:add_effect(EffectTypeId.new("gura_dry_skin_3"), TimeDuration.from_turns(99999))
            gapi.add_msg(MsgType.bad, "Painful cracks form along your dry skin!")
        end
    end
end)