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

-- Shark Bite: 20% chance to heal 1% HP on kill
game.add_hook("on_mon_death", function(params)
    local killer = params.killer
    if not killer then return end

    local char = killer:as_character()
    if not char then return end
    if not char:has_trait(MutationBranchId.new("SHARK_BITE")) then return end

    if math.random(100) > 20 then return end

    -- Heal 1 HP per wounded body part (only if actually wounded)
    if char:get_hp() < char:get_hp_max() then
        char:healall(1)
        gapi.add_msg(MsgType.good, "You tear into your fallen prey and feel your wounds knit!")
    end
end)

-- Salt Water Affinity: heal faster when wet
gapi.add_on_every_x_hook(TimeDuration.from_seconds(300), function()
    local avatar = gapi.get_avatar()
    if not avatar then return end
    if not avatar:has_trait(MutationBranchId.new("SALT_WATER_AFFINITY")) then return end
    if not avatar:has_morale(MoraleTypeDataId.new("morale_wet")) then return end
    if avatar:get_hp() >= avatar:get_hp_max() then return end

    avatar:healall(1)
end)