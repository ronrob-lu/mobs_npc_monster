local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

local has_mobs_redo = minetest.get_modpath("mobs") ~= nil
local has_mcl_mobs = minetest.get_modpath("mcl_mobs") ~= nil

-- -----------------------------------------------------------------------------
-- Settings
-- -----------------------------------------------------------------------------

local health_var = tonumber(minetest.settings:get("randomized_humanoids_health_var")) or 30
local damage_var = tonumber(minetest.settings:get("randomized_humanoids_damage_var")) or 25
local velocity_var = tonumber(minetest.settings:get("randomized_humanoids_velocity_var")) or 15
local knockback_var = tonumber(minetest.settings:get("randomized_humanoids_knockback_var")) or 20

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

local function get_random_variance(base_val, variance_percent, min_val)
    if not base_val then return nil end
    local variance = base_val * (variance_percent / 100)
    local min_bound = base_val - variance
    local max_bound = base_val + variance
    local result = min_bound + (math.random() * (max_bound - min_bound))
    return math.max(min_val or 0.5, result) -- Use provided minimum, defaulting to 0.5
end

local function apply_randomization(self)
    -- Normalize field naming between mobs_redo and mcl_mobs

    -- Health: mcl_mobs uses hp_max heavily. mobs_redo uses health_max and health, but sometimes supports hp_max.
    if self.hp_max or self.health_max then
        local hp_val = self.hp_max or self.health_max
        local new_hp = math.floor(get_random_variance(hp_val, health_var, 1))

        if self.hp_max then self.hp_max = new_hp end
        if self.health_max then self.health_max = new_hp end

        -- Synchronize immediate health
        if self.health then self.health = new_hp end
        if self.hp then self.hp = new_hp end
    end

    -- Damage
    if self.damage then
        self.damage = math.floor(get_random_variance(self.damage, damage_var, 1))
    end

    -- Velocity
    if self.walk_velocity then
        self.walk_velocity = get_random_variance(self.walk_velocity, velocity_var, 0.5)
    end
    if self.run_velocity then
        self.run_velocity = get_random_variance(self.run_velocity, velocity_var, 0.5)
    end

    -- Knockback
    if self.knockback then
        self.knockback = get_random_variance(self.knockback, knockback_var, 0.1)
    end
end

-- -----------------------------------------------------------------------------
-- Asset Discovery (Engine-Agnostic)
-- -----------------------------------------------------------------------------

local function get_files_recursive(dir_path)
    local files = {}
    local dirs = {dir_path}

    while #dirs > 0 do
        local cur_dir = table.remove(dirs, 1)
        local list = minetest.get_dir_list(cur_dir, false)
        for _, file in ipairs(list) do
            local full_path = cur_dir .. "/" .. file
            local rel_path = full_path:sub(#dir_path + 2)
            table.insert(files, rel_path)
        end

        local subdirs = minetest.get_dir_list(cur_dir, true)
        for _, subdir in ipairs(subdirs) do
            table.insert(dirs, cur_dir .. "/" .. subdir)
        end
    end

    return files
end

-- We recommend B3D. GLB is parsed to determine validity, but we'll use string-based animations or skip frames to conform to API.
local function parse_glb_animations(filepath)
    local file = io.open(filepath, "rb")
    if not file then return nil end

    local magic = file:read(4)
    if magic ~= "glTF" then
        file:close()
        return nil
    end

    local version_str = file:read(4)
    local length_str = file:read(4)
    local chunkLength_str = file:read(4)

    if not chunkLength_str then file:close(); return nil end

    local chunkLength = 0
    for i=1,4 do
        chunkLength = chunkLength + (chunkLength_str:byte(i) * (256^(i-1)))
    end

    local chunkType = file:read(4)

    if chunkType == "JSON" then
        local json_data = file:read(chunkLength)
        local data = minetest.parse_json(json_data)
        file:close()

        if data and data.animations then
            local anims = {}
            for i, anim in ipairs(data.animations) do
                local name = anim.name or ("anim_" .. tostring(i-1))

                -- Find the min and max times across all samplers for this animation
                local min_t = 999999
                local max_t = -999999

                if anim.samplers then
                    for _, sampler in ipairs(anim.samplers) do
                        if sampler.input then
                            local accessor = data.accessors and data.accessors[sampler.input + 1]
                            if accessor then
                                if accessor.min and accessor.min[1] then
                                    min_t = math.min(min_t, accessor.min[1])
                                end
                                if accessor.max and accessor.max[1] then
                                    max_t = math.max(max_t, accessor.max[1])
                                end
                            end
                        end
                    end
                end

                if min_t ~= 999999 and max_t ~= -999999 then
                    anims[name] = { start_time = min_t, end_time = max_t }
                else
                    anims[name] = true
                end
            end
            return anims
        end
    end

    file:close()
    return nil
end

local discovered_characters = {}
local textures = get_files_recursive(modpath .. "/textures")

local texture_set = {}
local inv_icons = {}

for _, tex in ipairs(textures) do
    local fn = tex:match("([^/]+)$")
    if fn then
        if fn:match("^inv_") then
            inv_icons[fn] = tex
        else
            texture_set[tex] = fn
        end
    end
end

local total_textures = 0
local total_inv_icons = 0

for _ in pairs(texture_set) do total_textures = total_textures + 1 end
for _ in pairs(inv_icons) do total_inv_icons = total_inv_icons + 1 end

for tex_rel, tex_name in pairs(texture_set) do
    local char_name = tex_name:match("^(.*)%.[^%.]+$")
    if char_name then
        local inv_icon_name = "inv_" .. char_name .. ".png"
        local inv_icon_filename = inv_icon_name
        local inv_icon_path = inv_icons[inv_icon_name]

        if not inv_icon_path then
            inv_icon_filename = tex_name
            minetest.log("warning", "[randomized_humanoids] Missing spawn egg icon for " .. char_name .. ", falling back to " .. inv_icon_filename)
        end

        discovered_characters[char_name] = {
            model = "character.glb",
            textures = {tex_name},
            inv_icon = inv_icon_filename,
            is_glb = true
        }
    end
end

local valid_chars = 0
for k,v in pairs(discovered_characters) do valid_chars = valid_chars + 1 end

minetest.log("action", "[randomized_humanoids] Discovered " .. total_textures .. " textures, " .. total_inv_icons .. " spawn egg icons, " .. valid_chars .. " valid character sets")

-- -----------------------------------------------------------------------------
-- Registration Wrapper
-- -----------------------------------------------------------------------------

local function register_mob(char_name, data)
    -- the user requested to prefix them with npc_monster
    local mob_name = "npc_monster:" .. char_name
    local def = {}

    def.type = "monster"
    def.hp_max = 20
    def.health_max = 20
    def.collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3}
    def.visual = "mesh"
    def.visual_size = {x = 6.5, y = 6.5, z = 6.5}
    def.mesh = data.model
    def.textures = {data.textures[1]}

    def.makes_footstep_sound = true
    def.view_range = 15
    def.walk_velocity = 1.5
    def.run_velocity = 3.0
    def.damage = 3
    def.reach = 2
    def.attack_type = "dogfight"
    def.armor = 100

    def.attack_players = true
    def.attack_npcs = true
    def.attack_animals = true
    def.passive = false

    -- Animation Mapping
    -- Standard framework requires these table layouts to not crash.
    -- B3D will use frames from the model implicitly if bounds fit, or use these default standard fallbacks.
    -- If using GLB, string animations mapped intelligently over 25 action bounds natively supported by Luanti are applied.
    def.animation = {
        speed_normal = 15, speed_run = 15,
        stand_start = 0, stand_end = 40, stand_speed = 15,
        walk_start = 41, walk_end = 81, walk_speed = 15,
        run_start = 82, run_end = 122, run_speed = 15,
        punch_start = 123, punch_end = 163, punch_speed = 15,
        die_start = 164, die_end = 204, die_speed = 15,
        attack_start = 123, attack_end = 163, attack_speed = 15,
        shoot_start = 123, shoot_end = 163, shoot_speed = 15,
    }

    if data.is_glb then
        def.rotate = 180
    end

    if data.is_glb then
        -- Baked continous timeline extracted from the node script processing the master glb
        local stand_s, stand_e = 0 + 0.05, 1.33 - 0.05
        local walk_s, walk_e = 1.33 + 0.05, 2.0 - 0.05
        local run_s, run_e = 2.0 + 0.05, 2.5 - 0.05
        local die_s, die_e = 2.5 + 0.05, 2.83 - 0.05
        local attack_s, attack_e = 2.83 + 0.05, 3.25 - 0.05

        def.animation = {
            speed_normal = 1, speed_run = 1,
            stand_start = stand_s, stand_end = stand_e, stand_speed = 1,
            walk_start = walk_s, walk_end = walk_e, walk_speed = 1,
            run_start = run_s, run_end = run_e, run_speed = 1,
            punch_start = attack_s, punch_end = attack_e, punch_speed = 1,
            die_start = die_s, die_end = die_e, die_speed = 1,
            attack_start = attack_s, attack_end = attack_e, attack_speed = 1,
            shoot_start = attack_s, shoot_end = attack_e, shoot_speed = 1,
        }
    end

    -- Setup auto detection flag for 180 deg fix
    local auto_detect_tested = false
    local auto_detect_fix = false

    if has_mcl_mobs then
        -- MINECLONIA (MCL MOBS) REGISTRATION
        local mcl_def = table.copy(def)
        mcl_def.spawn_class = "hostile"

        local old_on_spawn = mcl_def.on_spawn
        local old_on_step = mcl_def.on_step

        mcl_def.on_spawn = function(self)
            apply_randomization(self)

            if self.animation then
                self.animation = table.copy(self.animation)
            end

            -- Texture randomization (MCL)
            if #data.textures > 1 then
                self.base_texture = {data.textures[math.random(#data.textures)]}
                self.object:set_properties({textures = self.base_texture})
            end

            if old_on_spawn then old_on_spawn(self) end
        end

        mcl_mobs.register_mob(mob_name, mcl_def)

        if data.inv_icon then
            mcl_mobs.register_egg(mob_name, char_name .. " Spawn Egg", data.inv_icon, 0)
        end
        mcl_mobs.register_spawn(mob_name, {"group:stone", "group:dirt", "group:soil", "group:sand", "group:crumbly", "group:cracky"}, 7, 0, 7000, 1, 31000)
    end

    if has_mobs_redo then
        -- MOBS REDO (MTG) REGISTRATION
        local redo_def = table.copy(def)

        local old_on_spawn = redo_def.on_spawn
        redo_def.on_spawn = function(self)
            apply_randomization(self)

            if self.animation then
                self.animation = table.copy(self.animation)
            end

            -- Randomize texture if multiple
            if #data.textures > 1 then
                self.base_texture = {data.textures[math.random(#data.textures)]}
                self.object:set_properties({textures = self.base_texture})
            end

            if old_on_spawn then old_on_spawn(self) end
        end

        mobs:register_mob(mob_name, redo_def)

        if data.inv_icon then
            mobs:register_egg(mob_name, char_name .. " Spawn Egg", data.inv_icon, 0)
        end
        mobs:register_spawn(mob_name, {"group:stone", "group:dirt", "group:soil", "group:sand", "group:crumbly", "group:cracky"}, 7, 0, 7000, 1, 31000)
    end
end

-- Register all discovered
for char_name, data in pairs(discovered_characters) do
    register_mob(char_name, data)
end
