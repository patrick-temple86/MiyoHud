_addon.name = 'MiyoHUD'
_addon.author = 'k0de_0x16'
_addon.version = '0.2.0'
_addon.command = 'mh'

require('luau')
local texts = require('texts')
local config = require('config')
local packets = require('packets')
local res = require('resources')
require('sqlite3')

-- ============================================================================
-- Settings
-- ============================================================================

local defaults = {
    display = {
        pos = {x = 0, y = 0},
    },
}

local settings = config.load(defaults)

local hud_settings = {
    pos = {
        x = tonumber(settings.display.pos.x) or 0,
        y = tonumber(settings.display.pos.y) or 0,
    },
    bg = {
        red = 0,
        green = 0,
        blue = 0,
        alpha = 102,
        visible = true,
    },
    text = {
        font = 'Consolas',
        red = 255,
        green = 255,
        blue = 255,
        alpha = 255,
        size = 12,
        stroke = {
            width = 0,
            red = 0,
            green = 0,
            blue = 0,
            alpha = 255,
        },
    },
    padding = 0,
    flags = {
        draggable = true,
        right = false,
        bottom = false,
        bold = false,
        italic = false,
    },
}

local box = texts.new('${hud}', hud_settings)
box.hud = ''
box:show()

local last_hud = nil

-- ============================================================================
-- PointWatch-style state
-- ============================================================================

local xp = {
    current = 0,
    tnl = 56000,
    job_level = 0,
}

local lp = {
    current = 0,
    tnm = 10000,
    number_of_merits = 0,
    maximum_merits = 0,
}

local cp = {
    current = 0,
    tnjp = 30000,
    number_of_job_points = 0,
    maximum_job_points = 2100,
}

local zoning = false

-- ============================================================================
-- Monster database
-- ============================================================================

local monster_db = nil
local monster_db_path = windower.addon_path .. '/database.db'
local db_open_attempted = false
local db_warning_shown = false
local mob_cache_key = nil
local mob_cache_value = nil

local function file_exists(path)
    local f = io.open(path, 'rb')
    if f then
        f:close()
        return true
    end
    return false
end

local function open_monster_db()
    if monster_db and monster_db:isopen() then
        return true
    end

    -- Avoid repeating file-system and SQLite work every refresh after a
    -- failed attempt. The //mh dbreload command explicitly permits a retry.
    if db_open_attempted then
        return false
    end

    db_open_attempted = true

    if not file_exists(monster_db_path) then
        if not db_warning_shown then
            windower.add_to_chat(207, 'MiyoHUD: database.db not found; monster details disabled.')
            db_warning_shown = true
        end
        return false
    end

    monster_db = sqlite3.open(monster_db_path)

    if not monster_db or not monster_db:isopen() then
        if not db_warning_shown then
            windower.add_to_chat(207, 'MiyoHUD: could not open database.db; monster details disabled.')
            db_warning_shown = true
        end
        monster_db = nil
        return false
    end

    db_warning_shown = false
    return true
end

local function sql_escape(value)
    return tostring(value or ''):gsub("'", "''")
end

local job_abbr = {
    ['Warrior'] = 'WAR',
    ['Monk'] = 'MNK',
    ['White Mage'] = 'WHM',
    ['Black Mage'] = 'BLM',
    ['Red Mage'] = 'RDM',
    ['Thief'] = 'THF',
    ['Paladin'] = 'PLD',
    ['Dark Knight'] = 'DRK',
    ['Beastmaster'] = 'BST',
    ['Bard'] = 'BRD',
    ['Ranger'] = 'RNG',
    ['Samurai'] = 'SAM',
    ['Ninja'] = 'NIN',
    ['Dragoon'] = 'DRG',
    ['Summoner'] = 'SMN',
    ['Blue Mage'] = 'BLU',
    ['Corsair'] = 'COR',
    ['Puppetmaster'] = 'PUP',
    ['Dancer'] = 'DNC',
    ['Scholar'] = 'SCH',
    ['Geomancer'] = 'GEO',
    ['Rune Fencer'] = 'RUN',
}

local function abbreviate_jobs(value)
    if not value or value == '' then
        return nil
    end

    local parts = {}
    for part in tostring(value):gmatch('[^/]+') do
        part = part:gsub('^%s+', ''):gsub('%s+$', '')
        parts[#parts + 1] = job_abbr[part] or part
    end
    return table.concat(parts, '/')
end

local function build_detection_text(row)
    local detects = {}

    if row.truesight == 1 then
        detects[#detects + 1] = 'True Sight'
    elseif row.sight == 1 then
        detects[#detects + 1] = 'Sight'
    end

    if row.truesound == 1 then
        detects[#detects + 1] = 'True Sound'
    elseif row.sound == 1 then
        detects[#detects + 1] = 'Sound'
    end

    if row.magic == 1 then
        detects[#detects + 1] = 'Magic'
    end

    if row.lowhp == 1 then
        detects[#detects + 1] = 'Low HP'
    end

    if row.healing == 1 then
        detects[#detects + 1] = 'Healing'
    end

    return table.concat(detects, '/')
end

local function get_monster_details(name, zone)
    if not name or not zone then
        return nil
    end

    local cache_key = zone .. '\0' .. name
    if mob_cache_key == cache_key then
        return mob_cache_value
    end

    mob_cache_key = cache_key
    mob_cache_value = nil

    if not open_monster_db() then
        return nil
    end

    local query = ([[
        SELECT COALESCE(family, ''), COALESCE(job, ''),
               is_aggressive, is_linking,
               level_min, level_max,
               detects_sight, detects_sound, detects_magic,
               detects_lowhp, detects_healing,
               detects_truesight, detects_truesound
        FROM monster
        WHERE name = '%s' AND zone = '%s'
        LIMIT 1
    ]]):format(sql_escape(name), sql_escape(zone))

    for family, job, aggressive, linking,
        level_min, level_max,
        sight, sound, magic, lowhp, healing,
        truesight, truesound in monster_db:urows(query) do

        local row = {
            family = family,
            job = job,
            aggressive = tonumber(aggressive) or 0,
            linking = tonumber(linking) or 0,
            level_min = level_min,
            level_max = level_max,
            sight = tonumber(sight) or 0,
            sound = tonumber(sound) or 0,
            magic = tonumber(magic) or 0,
            lowhp = tonumber(lowhp) or 0,
            healing = tonumber(healing) or 0,
            truesight = tonumber(truesight) or 0,
            truesound = tonumber(truesound) or 0,
        }

        local parts = {}

        if row.family and row.family ~= '' then
            parts[#parts + 1] = row.family
        end

        local job = abbreviate_jobs(row.job)
        if job and job ~= '' then
            parts[#parts + 1] = job
        end

        if row.level_min ~= nil and row.level_max ~= nil then
            if tostring(row.level_min) == tostring(row.level_max) then
                parts[#parts + 1] = 'Lv.' .. tostring(row.level_min)
            else
                parts[#parts + 1] = 'Lv.' .. tostring(row.level_min) .. '-' .. tostring(row.level_max)
            end
        end

        if row.aggressive == 1 then
            local detection = build_detection_text(row)
            if detection ~= '' then
                parts[#parts + 1] = 'Aggro: ' .. detection
            else
                parts[#parts + 1] = 'Aggro'
            end
        else
            parts[#parts + 1] = 'Passive'
        end

        if row.linking == 1 then
            parts[#parts + 1] = 'Links'
        end

        if #parts > 0 then
            mob_cache_value = table.concat(parts, ' | ')
        end

        break
    end

    return mob_cache_value
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function color_text(text, r, g, b)
    return ('\\cs(%d,%d,%d)%s\\cr'):format(r, g, b, text)
end

local function get_selected_target()
    return windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t')
end

local function get_infobar_line(target)
    if not target or not target.id or target.id <= 0 then
        return ''
    end

    -- Preserve InfoBar's basic target coloring:
    -- PC = white/cyan, NPC = green, MOB = yellow.
    if target.spawn_type == 2 or target.spawn_type == 34 then
        return color_text(target.name, 128, 255, 128)
    elseif target.spawn_type == 16 then
        return color_text(target.name, 255, 255, 128)
    elseif target.spawn_type == 13 or target.spawn_type == 14 or
           target.spawn_type == 9 or target.spawn_type == 1 then
        if target.spawn_type == 1 then
            return color_text(target.name, 255, 255, 255)
        else
            return color_text(target.name, 128, 255, 255)
        end
    end

    return target.name or ''
end

local function build_hud()
    local info = windower.ffxi.get_info()
    local player = windower.ffxi.get_player()

    if not info.logged_in or not player or zoning then
        box:hide()
        return
    end

    local target = get_selected_target()
    local lines = {}
    local has_target = (target ~= nil and target.id ~= nil and target.id > 0)
    local zone = res.zones[info.zone]

    -- Keep these rows present so target changes never resize the overlay.
    if has_target then
        local distance = target.distance and math.sqrt(target.distance) or nil

        lines[#lines + 1] = ('Hex ID:     %03X'):format(target.index or 0)
        lines[#lines + 1] = ('Distance:   %s'):format(
            distance and ('%.1f yalms'):format(distance) or '-'
        )
    else
        lines[#lines + 1] = 'Hex ID:     -'
        lines[#lines + 1] = 'Distance:   -'
    end

    -- InfoBar section. With a target, show the target name. With no target,
    -- show only the current area/zone name.
    if has_target then
        local target_line = get_infobar_line(target)

        -- InfoBar classified spawn_type 16 as a monster. For monsters, append
        -- the SQLite details to the SAME line so the fixed row count does not
        -- change.
        if target.spawn_type == 16 then
            local hp_percent = tonumber(target.hpp)
            if hp_percent then
                hp_percent = math.max(0, math.min(100, math.floor(hp_percent + 0.5)))
                target_line = target_line .. (' [%d%%]'):format(hp_percent)
            else
                target_line = target_line .. ' [--%]'
            end

            local zone_name = zone and zone.name or nil
            local details = get_monster_details(target.name, zone_name)

            if details and details ~= '' then
                target_line = target_line .. ' | ' .. details
            end
        end

        lines[#lines + 1] = target_line
    else
        lines[#lines + 1] = zone and zone.name or 'Unknown Area'
    end

    -- PointWatch section
    lines[#lines + 1] = (
        'EXP: %d/%d [%d/99] | Merits: %d/%d [%d] | CP/JP: %d/%d [%d]'
    ):format(
        xp.current or 0,
        xp.tnl or 0,
        xp.job_level or player.main_job_level or 0,
        lp.current or 0,
        lp.tnm,
        lp.number_of_merits or 0,
        cp.current or 0,
        cp.tnjp,
        cp.number_of_job_points or 0
    )

    local hud = table.concat(lines, '\n')

    if hud ~= last_hud then
        box.hud = hud
        last_hud = hud
    end

    box:show()
end

-- ============================================================================
-- Incoming packets
-- ============================================================================

windower.register_event('incoming chunk', function(id, org, modified, is_injected, is_blocked)
    if is_injected or is_blocked then
        return
    end

    -- Zone start/end handling
    if id == 0x00B then
        zoning = true
        box:hide()
        return
    elseif id == 0x00A then
        zoning = false
        return
    end

    -- Character stats: EXP / job level
    if id == 0x061 then
        local p = packets.parse('incoming', org)

        xp.current = p['Current EXP'] or xp.current
        xp.tnl = p['Required EXP'] or xp.tnl
        xp.job_level = p['Main Job Level'] or xp.job_level

    -- Merit / Capacity Point update
    elseif id == 0x063 then
        local p = packets.parse('incoming', org)

        if p['Order'] == 2 then
            lp.current = p['Limit Points'] or lp.current
            lp.number_of_merits = p['Merit Points'] or lp.number_of_merits
            lp.maximum_merits = p['Max Merit Points'] or lp.maximum_merits

        elseif p['Order'] == 5 then
            local player = windower.ffxi.get_player()
            if player and player.main_job_full then
                cp.current = p[player.main_job_full .. ' Capacity Points'] or cp.current
                cp.number_of_job_points = p[player.main_job_full .. ' Job Points'] or cp.number_of_job_points
            end
        end

    -- Action messages: keep XP / LP / CP current between full stat packets.
    elseif id == 0x029 or id == 0x02D then
        local p = packets.parse('incoming', org)
        local val = p['Param 1'] or 0
        local msg = p['Message']

        -- Capacity Points
        if msg == 718 or msg == 735 then
            cp.current = (cp.current or 0) + val

            if cp.current >= cp.tnjp and cp.number_of_job_points < cp.maximum_job_points then
                local gained = math.floor(cp.current / cp.tnjp)
                cp.number_of_job_points = math.min(
                    cp.number_of_job_points + gained,
                    cp.maximum_job_points
                )
                cp.current = cp.current % cp.tnjp
            end

        -- Experience Points
        elseif msg == 8 or msg == 105 then
            xp.current = math.min((xp.current or 0) + val, 55999)

            if xp.tnl and xp.tnl > 0 and xp.current >= xp.tnl then
                xp.current = xp.current - xp.tnl
            end

        -- Limit Points
        elseif msg == 371 or msg == 372 then
            lp.current = (lp.current or 0) + val

            if lp.current >= lp.tnm then
                local gained = math.floor(lp.current / lp.tnm)

                if lp.maximum_merits > 0 then
                    lp.number_of_merits = math.min(
                        lp.number_of_merits + gained,
                        lp.maximum_merits
                    )
                else
                    lp.number_of_merits = lp.number_of_merits + gained
                end

                lp.current = lp.current % lp.tnm
            end
        end
    end
end)

windower.register_event('unload', function()
    if monster_db and monster_db:isopen() then
        monster_db:close()
    end
end)

-- ============================================================================
-- Rendering
-- ============================================================================

local frame = 0

windower.register_event('prerender', function()
    frame = frame + 1

    -- About twice per second at 60 FPS, once per second at 30 FPS.
    if frame == 30 then
        frame = 0
        build_hud()
    end
end)

windower.register_event('target change', function()
    build_hud()
end)

windower.register_event('job change', function()
    -- Full values will refresh with the normal incoming stat packets.
    build_hud()
end)

-- ============================================================================
-- Commands
-- ============================================================================

windower.register_event('addon command', function(...)
    local args = {...}
    local cmd = args[1] and args[1]:lower() or ''

    if cmd == 'reload' then
        windower.send_command('lua r miyohud')

    elseif cmd == 'unload' then
        windower.send_command('lua u miyohud')

    elseif cmd == 'show' then
        box:show()

    elseif cmd == 'hide' then
        box:hide()

    elseif cmd == 'db' then
        if open_monster_db() then
            windower.add_to_chat(207, 'MiyoHUD: monster database loaded.')
        else
            windower.add_to_chat(207, 'MiyoHUD: monster database unavailable.')
        end

    elseif cmd == 'dbreload' then
        if monster_db and monster_db:isopen() then
            monster_db:close()
        end
        monster_db = nil
        db_open_attempted = false
        mob_cache_key = nil
        mob_cache_value = nil

        if open_monster_db() then
            windower.add_to_chat(207, 'MiyoHUD: monster database reloaded.')
        end

    elseif cmd == 'pos' then
        local x = tonumber(args[2])
        local y = tonumber(args[3])

        if x and y then
            box:pos(x, y)
            settings.display.pos.x = x
            settings.display.pos.y = y
            config.save(settings)
            windower.add_to_chat(207, ('MiyoHUD position: %d, %d'):format(x, y))
        else
            windower.add_to_chat(207, 'Usage: //mh pos <x> <y>')
        end

    else
        windower.add_to_chat(207, 'MiyoHUD commands: //mh pos <x> <y> | show | hide | db | dbreload | reload | unload')
    end
end)

build_hud()
