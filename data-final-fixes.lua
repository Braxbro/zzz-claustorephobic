-- TODO: clean up some of the synthetic expressions here to use local_expressions better

-- not used for anything but worthwhile to keep for debugging or whatever later.
local compat_output = {}
for mod, version in pairs(mods) do
    compat_output[mod .. "_" .. version] = pcall(require, "compat-patches." .. mod)
end

local util_functions = require("utils.parse-autoplace")
local maskutil = require("collision-mask-util")
local drills = data.raw["mining-drill"]
local resources = data.raw["resource"]
local water_mask = data.raw["tile"].water.collision_mask

function string.insert(str1, str2, pos)
    return string.sub(str1, 1,pos) .. str2 .. string.sub(str1, pos+1)
end

-- AoE-capable resource categories: drills that mine beyond a single tile
local aoe_categories = {}
for _, drill in pairs(drills or {}) do
    if drill.collision_box and drill.resource_searching_radius and drill.resource_categories then
        local raw_half = math.max(
            drill.collision_box[2][1] - drill.collision_box[1][1],
            drill.collision_box[2][2] - drill.collision_box[1][2]
        ) / 2
        local norm_half = math.ceil(raw_half / 0.5) * 0.5
        if drill.resource_searching_radius >= norm_half - 0.01 then
            for _, cat in ipairs(drill.resource_categories) do
                aoe_categories[cat] = true
            end
        end
    end
end

-- Build slot_data: collect all ores with valid autoplaces, apply physical eligibility filters,
-- and group by (seed1, regular_patch_set_index). Track ineligible ores as poisoned.
-- Key format: "SSSS:PPPP" (seed1, regular PSI).  Starter ores are NOT given a
-- separate slot; both their regular and starting caps live in the same slot so
-- the two patch types share an rp x-value and therefore the same band position.
-- Compound slot poisoning: if any ore in a slot fails physical checks or has unfound
-- base_density, that ore's expressions are captured for clearing.
-- slot_data[key].ore_params is a dict {name → call_params} for all ELIGIBLE members.
local slot_data = {}  -- key → { ore_params={name→params}, ore_exprs={name→expr}, seed1, regular_psi, regular_psc }
local slot_order = {} -- sorted array of eligible keys
local poisoned  = {}  -- key → true (at least one ineligible ore maps here)
local waterproof = {} -- ore_name → boolean

for name, resource in pairs(resources) do
    local ap = resource.autoplace
    if ap and type(ap.probability_expression) == "string"
           and type(ap.richness_expression) == "string" then
        local all_calls, all_exprs = util_functions.find_all_autoplace_arguments(ap, "claustorephobic_ignore", "claustorephobic_force")
        if #all_calls > 0 then

            -- Determine if this ore is physically eligible.
            local eligible = false
            if resource.collision_box then
                local longest = math.max(
                    resource.collision_box[2][1] - resource.collision_box[1][1],
                    resource.collision_box[2][2] - resource.collision_box[1][2]
                )
                local cat = resource.category or "basic-solid"
                local tile_restricted = ap.tile_restriction and #ap.tile_restriction > 0
                local ctrl = all_calls[1].control_name
                eligible = longest <= 1 and aoe_categories[cat] and not tile_restricted
                    and ctrl and ctrl ~= "unfound" and data.raw["autoplace-control"][ctrl]
            end
            waterproof[name] = not (maskutil.masks_collide(water_mask, maskutil.get_mask(resource)))

            -- Process each autoplace call for this ore.
            for i, call_params in ipairs(all_calls) do
                local s1  = call_params.seed1
                local key = string.format("%04d:%04d", s1, call_params.regular_patch_set_index)
                if not slot_data[key] then
                    slot_data[key] = {
                        ore_params  = {},
                        ore_exprs   = {},
                        seed1       = s1,
                        regular_psi = call_params.regular_patch_set_index,
                        regular_psc = call_params.regular_patch_set_count,
                    }
                    slot_order[#slot_order + 1] = key
                end
                slot_data[key].ore_exprs[name] = all_exprs[i]
                slot_data[key].ore_params[name] = call_params
                -- Mark slot as poisoned if ore is ineligible, unfound, or explicitly ignored.
                -- Exception: forced ores bypass eligibility checks.
                if call_params.forced then
                    -- forced ore: always include, clear ignore flag
                    call_params.ignored = false
                elseif not eligible or call_params.base_density == "unfound" or call_params.ignored then
                    poisoned[key] = true
                end
            end
        end
    end
end

-- Bake poisoned slots to clearing expressions, remove the poisoned slots, and compact slot_order.
local water_prob = data.raw["tile"].water.autoplace.probability_expression
local poison_exprs = {
      water_inf = "clamp(1 - " .. water_prob .. ", 0, 1)"
    -- , spot_scale = "400"
    , size_scale = "8 * var('control:claustorephobic-clearings:size')"
    , density_scale = "8"
    , rq_scale = "1.8"
    , blob_scale = "6"
    -- slot_key:ore → NoiseExpression
}
local poison_count = 0
local main_expr

-- TODO: Redo clearings logic - haven't found a satisfactory solution yet
for key in pairs(poisoned) do
    --[[
    local to_log = "\nProcessing poisoned slot " .. key .. ":"
    for ore, expr in pairs(slot_data[key].ore_exprs) do
        local orekey = "ex" .. key .. ":" .. string.gsub(ore, "-", "_")
        to_log = to_log .. "\n" .. ore .. " params:\n" .. serpent.line(slot_data[key].ore_params[ore])
        to_log = to_log .. "\n" .. ore .. " expression:\n" .. expr

        local blobamp = "_blob_amplitude_multiplier"
        local newexpr = expr
        newexpr = string.gsub(newexpr, "(var%('control%b::size'%))", "(%1 * size_scale)")
        newexpr = string.gsub(newexpr, "(base_density%s*=%s*)([^,}]+)", "%1(%2 * density_scale)")
        newexpr = string.gsub(newexpr, "(regular_rq_factor%s*=%s*)([^,}]+)", "%1(%2 * rq_scale)")
        newexpr = string.gsub(newexpr, "(starting_rq_factor%s*=%s*)([^,}]+)", "%1(%2 * rq_scale)")
        -- newexpr = string.gsub(newexpr, "(random_spot_size_minimum%s*=%s*)([^,}]+)", "%1(%2 * spot_scale)")
        -- newexpr = string.gsub(newexpr, "(random_spot_size_maximum%s*=%s*)([^,}]+)", "%1(%2 * spot_scale)")
        newexpr = string.gsub(newexpr, "(starting" .. blobamp .."%s*=%s*)([^,}]+)", "%1(%2 * blob_scale)")
        newexpr = string.gsub(newexpr, "(regular" .. blobamp .."%s*=%s*)([^,}]+)", "%1(%2 * blob_scale)")
        if not waterproof[ore] then
            newexpr = newexpr .. " * water_inf"
        end

        poison_exprs[orekey] = newexpr
        poison_count = poison_count + 1

        to_log = to_log .. "\nComputed poisoned resource clearing:\n" .. poison_exprs[orekey]
        main_expr = main_expr and (main_expr .. ", " .. orekey) or orekey
    end
    ]]
    -- log(to_log)
    slot_data[key] = nil
end
--[[
if poison_count > 1 then
    main_expr = "max(" .. main_expr .. ")"
end
data.extend{
    { type = "noise-expression"
    , name = "claustorephobic-excluded-ore-areas"
    , expression = main_expr
    , local_expressions = poison_exprs
    }
}
]]
-- log(main_expr)

local clean_order = {}
for _, key in ipairs(slot_order) do
    if slot_data[key] then clean_order[#clean_order + 1] = key end
end
table.sort(clean_order)
slot_order = clean_order

for i, key in ipairs(slot_order) do
    slot_data[key].slot_index = i
end

-- ── Task 3: Slot weights (pack-average normalization) ─────────────────────────
--
-- Coverage proxy:   cov  = rq² × bd^(2/3) × spots^(1/3)
-- Endurance proxy:  end  = (peak/3 + add_rich) × mining_time
--   where peak = qty^(1/3) / (π/3 × rq²),  qty = (1e6/spots) × bd × mean_sz
-- Normalization:    pack-average (geometric mean across all eligible ores)
-- β blend:          x = |log(end_n/cov_n)|,  β = x/(x+1)
--   adjusted_cov = cov_n^(1-β) × end_n^β,   K_claust = end_n^(1-β)
-- Slot representative: last-placing ore per compound slot (by resource.order),
--   which defines the visual outer extent of the compound patch cluster.

local CLAUST_PI = math.pi

local function ore_cov_end(params, resource)
    local rq      = params.regular_rq_factor_multiplier / 10
    local bd      = params.base_density
    local spots   = params.base_spots_per_km2
    local mean_sz = (params.random_spot_size_minimum + params.random_spot_size_maximum) / 2
    local add_r   = params.additional_richness
    local mt      = (resource.minable and resource.minable.mining_time) or 1
    local qty   = (1e6 / spots) * bd * mean_sz
    local peak  = qty^(1/3) / (CLAUST_PI / 3 * rq * rq)
    local cov   = math.max(rq * rq * bd^(2/3) * spots^(1/3), 1e-10)
    local endur = math.max((peak / 3 + add_r) * mt,          1e-10)
    return cov, endur
end

-- First pass: compute raw cov/endurance per ore.
local ore_raw_cov = {}
local ore_raw_end = {}

for _, key in ipairs(slot_order) do
    local sd = slot_data[key]
    for name, params in pairs(sd.ore_params) do
        local resource     = resources[name]
        local cov, endur   = ore_cov_end(params, resource)
        ore_raw_cov[name]  = cov
        ore_raw_end[name]  = endur
    end
end

-- Pack-average: geometric mean of cov and endurance across all eligible ores.
local log_sum_cov, log_sum_end, n_ores = 0, 0, 0
for name in pairs(ore_raw_cov) do
    log_sum_cov = log_sum_cov + math.log(ore_raw_cov[name])
    log_sum_end = log_sum_end + math.log(ore_raw_end[name])
    n_ores      = n_ores + 1
end

local cov_ref = n_ores > 0 and math.exp(log_sum_cov / n_ores) or 1
local end_ref = n_ores > 0 and math.exp(log_sum_end / n_ores) or 1

-- Second pass: β blend, K_claust, adjusted_cov per ore.
local ore_weight = {}
for name in pairs(ore_raw_cov) do
    local cov_n = ore_raw_cov[name] / cov_ref
    local end_n = ore_raw_end[name] / end_ref
    local x     = math.abs(math.log(end_n / cov_n))
    local beta  = x / (x + 1)
    ore_weight[name] = {
        beta         = beta
      , K_claust     = end_n^(1 - beta)
      , adjusted_cov = cov_n^(1 - beta) * end_n^beta
    }
end

-- ── Per-ore cap noise-functions ───────────────────────────────────────────────
-- Every ore gets claustorephobic_<name>_regular_cap(patch_set, i), weighted by
-- REGULARW (0 in clearing / starting zone, 1 far out).
-- Starter ores additionally get claustorephobic_<name>_starter_cap(patch_set, i),
-- weighted by STARTW (0 in clearing / outer zone, peaks at 1 near start).
-- Both delegate to claustorephobic_cap with all per-call constants baked in.
-- Hyphens in ore names are replaced with underscores in function names.
-- Dedup guard: an ore may appear in multiple slots; emit each NF only once.

local ore_cap_fns = {}  -- name → { cap_fn_regular, cap_fn_starter }
do
    local SAI      = "var('claustorephobic-starting-area-influence')"
    local STARTW   = "max(" .. SAI .. ", 0)"
    local REGULARW = "if(" .. SAI .. " >= 0, 1 - " .. SAI .. ", 0)"

    for name, resource in pairs(resources) do
        local safe = resource.name:gsub("-", "_")
        ore_cap_fns[name] = {
            cap_fn_regular = "claustorephobic_" .. safe .. "_regular_cap",
            cap_fn_starter = "claustorephobic_" .. safe .. "_starter_cap"
        }
    end

    local cap_nfs = {}
    local emitted = {}
    for _, key in ipairs(slot_order) do
        local sd = slot_data[key]
        for name, params in pairs(sd.ore_params) do
            -- Regular cap
            local fn_reg = ore_cap_fns[name].cap_fn_regular
            if not emitted[fn_reg] then
                emitted[fn_reg] = true
                cap_nfs[#cap_nfs + 1] = {
                    type       = "noise-function"
                  , name       = fn_reg
                  , parameters = {"patch_set", "i"}
                  , expression = string.format(
                        "claustorephobic_cap(patch_set, i, %d, %d, %d, %g, " ..
                        "var('control:%s:size')) * %s",
                        params.seed1, params.regular_patch_set_count,
                        params.regular_patch_set_index,
                        ore_weight[name].adjusted_cov,
                        params.control_name, REGULARW)
                }
            end
            -- Starter cap (only for ores with starting-area placement)
            if params.has_starting_area_placement == true then
                local fn_start = ore_cap_fns[name].cap_fn_starter
                if not emitted[fn_start] then
                    emitted[fn_start] = true
                    cap_nfs[#cap_nfs + 1] = {
                        type       = "noise-function"
                      , name       = fn_start
                      , parameters = {"patch_set", "i"}
                      , expression = string.format(
                            "claustorephobic_cap(patch_set, i, %d, %d, %d, %g, " ..
                            "var('control:%s:size')) * %s",
                            params.seed1, params.starting_patch_set_count,
                            params.starting_patch_set_index,
                            ore_weight[name].adjusted_cov,
                            params.control_name, STARTW)
                    }
                end
            end
        end
    end
    data:extend(cap_nfs)
end

-- ── Per-slot weight NEs ────────────────────────────────────────────────────────
-- slot_weight_j = max over ores in slot of (regular_cap + starter_cap).
-- Starter ores contribute both cap functions so their slot width sums to roughly
-- the base cap value at any distance; non-starters contribute regular_cap only.
-- Live NE: responds to control sliders and distance (sai factor baked into caps).
do
    local weight_nes = {}
    for j, key in ipairs(slot_order) do
        local sd = slot_data[key]
        sd.seq_index = j - 1  -- 0-based; used as x in random_penalty for seed ordering
        sd.ore_caps  = {}     -- per-ore cap expression strings, keyed by ore name

        local caps = {}
        for name, params in pairs(sd.ore_params) do
            local ore_total = string.format(
                "%s(%d, %d)",
                ore_cap_fns[name].cap_fn_regular,
                params.seed1, params.regular_patch_set_index)
            if params.has_starting_area_placement == true then
                ore_total = string.format(
                    "%s + %s(%d, %d)",
                    ore_total, ore_cap_fns[name].cap_fn_starter,
                    params.seed1, params.starting_patch_set_index)
            end
            sd.ore_caps[name] = ore_total
            caps[#caps + 1] = ore_total
        end

        -- max() takes 2 args in NE; nest for compound slots.
        local weight_expr = caps[1] or "0"
        for k = 2, #caps do
            weight_expr = string.format("max(%s, %s)", weight_expr, caps[k])
        end

        local wname = string.format("claustorephobic-slot-weight-%d", sd.seq_index)
        sd.weight_ne = string.format("var('%s')", wname)
        weight_nes[#weight_nes + 1] = {
            type = "noise-expression"
          , name = wname
          , expression = weight_expr
        }
    end
    data:extend(weight_nes)
end

-- ── Total density NE ──────────────────────────────────────────────────────────
-- Sum of all slot weights. The sai distance factor is already baked into each
-- cap NF, so this naturally reflects which slots are active at any given distance.
local total_parts = {}
for _, key in ipairs(slot_order) do
    total_parts[#total_parts + 1] = slot_data[key].weight_ne
end
local total_ne = #total_parts > 0 and table.concat(total_parts, " + ") or "0"

local scaled_pos_expr = string.format(
    "var('claustorephobic-preset') * (%s)", total_ne)

-- scaled-pos NE: band_pos * total_density. Sai weighting is baked into each cap NF,
-- so total_ne already reflects which slots are active at the current distance.
data:extend{
    { type = "noise-expression", name = "claustorephobic-scaled-pos"
    , expression = scaled_pos_expr
    }
}

-- ── lo_j NEs and slot_count NE ────────────────────────────────────────────────
-- lo_j = cumulative slot_weight sum for all slots seeded before slot j.
-- Seed ordering: rp_k = random_penalty{x=k, y=map_seed}.  These are compile-time
-- constants (map_seed is known at NE compile time) so all comparisons fold.
-- Tie-break by sequential index: smaller index wins on equal rp.
-- slot_count = sum_j (lo_j <= scaled_pos): how many lower bounds we've passed.
-- Per-ore band check: centered range [lo_j + (w-cap)/2, lo_j + (w+cap)/2).
do
    local function rp(k0)
        return string.format("random_penalty{x = %d, y = map_seed, source = 1}", k0)
    end

    local lo_nes = {}
    for _, key in ipairs(slot_order) do
        local j0 = slot_data[key].seq_index
        local lo_parts  = {}
        local rank_parts = {}
        for _, kkey in ipairs(slot_order) do
            local k0 = slot_data[kkey].seq_index
            if k0 ~= j0 then
                -- (rp_k <= rp_j): k < j tie-break (smaller index = higher priority)
                -- (rp_k < rp_j):  k > j, strictly lower rp required
                local cmp = k0 < j0
                    and string.format("(%s <= %s)", rp(k0), rp(j0))
                    or  string.format("(%s < %s)",  rp(k0), rp(j0))
                lo_parts[#lo_parts + 1]   = cmp .. " * " .. slot_data[kkey].weight_ne
                rank_parts[#rank_parts + 1] = cmp
            end
        end

        local loname = string.format("claustorephobic-lo-%d", j0)
        local lo_expr = #lo_parts > 0 and table.concat(lo_parts, " + ") or "0"
        lo_nes[#lo_nes + 1] = {
            type = "noise-expression"
          , name = loname
          , expression = lo_expr
        }
        slot_data[key].lo_ne   = string.format("var('%s')", loname)
        -- rank_j = sum of comparison terms (compiles to a constant per map).
        -- Per-ore band check: slot_count == rank_j + 1.
        local rank_expr = #rank_parts > 0 and table.concat(rank_parts, " + ") or "0"
        slot_data[key].rank_ne = rank_expr
    end
    data:extend(lo_nes)

    -- slot_count: number of lo_j values <= scaled_pos.
    local sc_parts = {}
    for _, key in ipairs(slot_order) do
        sc_parts[#sc_parts + 1] = string.format(
            "(var('claustorephobic-scaled-pos') >= %s)", slot_data[key].lo_ne)
    end
    data:extend{{
        type = "noise-expression"
      , name = "claustorephobic-slot-count"
      , expression = #sc_parts > 0 and table.concat(sc_parts, " + ") or "0"
    }}
end

-- ── K calibration ─────────────────────────────────────────────────────────────
-- K_claust is normalized to pack geometric mean; scale by end_ref so K_claust==1
-- corresponds to ~end_ref richness per tile at dist == r_inner.
-- (empirically tuned via the claustorephobic-resource-multiplier map-gen slider)
local K_ref = end_ref

-- ── Patch each eligible ore's autoplace expressions ───────────────────────────
-- Collect all slot-specific band conditions per ore first, then combine.
-- Compound ores may appear in multiple slots (different seed1/psi calls); their
-- probability fires when ANY slot's condition is satisfied (max = OR for 0/1).
-- Richness params are ore-level (identical across all slots of the same ore).
local ore_band_conds  = {}  -- name → {cond_string, ...}
local ore_slot_params = {}  -- name → representative call_params (for richness)
for _, key in ipairs(slot_order) do
    local sd = slot_data[key]
    for name, params in pairs(sd.ore_params) do
        if not ore_band_conds[name] then
            ore_band_conds[name] = {}
            ore_slot_params[name] = params
        end
        -- Centered band condition: ore occupies the middle ore_cap-wide fraction of
        -- the slot (width = weight_ne).  For non-compound slots ore_cap == weight_ne
        -- so the condition degenerates to the full slot.  For compound slots smaller
        -- ores are centered inside the slot, leaving gaps at either edge.
        local ore_cap = sd.ore_caps[name]
        local lo      = sd.lo_ne
        local w       = sd.weight_ne
        ore_band_conds[name][#ore_band_conds[name] + 1] = string.format(
            "(%s + (%s - (%s)) / 2 <= var('claustorephobic-scaled-pos')) * " ..
            "(var('claustorephobic-scaled-pos') < %s + (%s + (%s)) / 2)",
            lo, w, ore_cap, lo, w, ore_cap)
    end
end

local clearing_guard = " * (var('claustorephobic-starting-area-influence') >= 0)"

for name, conds in pairs(ore_band_conds) do
    local resource = resources[name]
    local params   = ore_slot_params[name]
    local K_claust = ore_weight[name].K_claust
    local control  = params.control_name

    -- Combine band conditions: max(c1, c2) acts as OR for 0/1 values.
    local combined_band = conds[1]
    for k = 2, #conds do
        combined_band = string.format("max(%s, %s)", combined_band, conds[k])
    end

    local prob_expr = string.format(
        "(var('control:%s:size') > 0) * %s%s",
        control, combined_band, clearing_guard)

    local probname = "claustorephobic-" .. name .. "-probability"
    data.extend{
        { type = "noise-expression"
        , name = probname
        , expression = prob_expr 
        --[[
        .. " - excluded_ores"
        , local_expressions = {
            excluded_ores = "var('claustorephobic-excluded-ore-areas')"
        }
        ]]
        }
    }

    -- ── Richness expression ──────────────────────────────────────────────
    -- richness_claust = K_claust * K_ref * resource_multiplier * shape_distance / max(inner_radius, 1)
    -- (linear with shape-distance; K_ref anchors to pack-average endurance)

    local k_scale = K_claust * K_ref * params.richness_post_multiplier
    local rich_inner = string.format(
        "%g * var('control:claustorephobic-resource-multiplier:richness') * var('claustorephobic-shape') / max(var('claustorephobic-inner-radius'), 1)",
        k_scale)

    if params.additional_richness > 0 then
        rich_inner = rich_inner .. string.format(" + %g", params.additional_richness)
    end
    if params.minimum_richness > 0 then
        rich_inner = string.format("max(%s, %g)", rich_inner, params.minimum_richness)
    end

    local richness_expr = string.format(
        "(var('control:%s:size') > 0) * var('control:%s:richness') * (%s) * %s%s",
        control, control, rich_inner, combined_band, clearing_guard)

    local richname = "claustorephobic-" .. name .. "-richness"
    data.extend{
        { type = "noise-expression"
        , name = richname
        , expression = richness_expr .. " / 200"
        }
    }

    resource.autoplace.probability_expression = "var('" .. probname .. "')"
    resource.autoplace.richness_expression = "var('" .. richname .. "')"
end

do -- collision mask modifications
local CLAUST_LAYER = "claustorephobic-layer"
-- 1. Per-ore prototype adjustments for eligible ores.
-- Eligible ores are those in ore_band_conds (they made it through filtering and slot assignment).
for name in pairs(ore_band_conds) do
    local proto = resources[name]
    -- Collision layer: buildings can't be placed on ore.
    proto.collision_mask = maskutil.get_mask(proto)
    proto.collision_mask.layers[CLAUST_LAYER] = true
    proto.autoplace.order = "z"          -- place absolute last in generation
    proto.tree_removal_probability = nil -- don't clear trees on ore spawn
    proto.tree_removal_max_distance = nil
    proto.cliff_removal_probability = 0  -- don't clear cliffs on ore spawn
end

-- 3. Re-validate ClaustOrephobic API table after data-updates (other mods may
--    have written to it between data.lua and data-final-fixes.lua).
for index, value in pairs(ClaustOrephobic.allowed_subgroups) do
    if type(value) ~= "string" then ClaustOrephobic.allowed_subgroups[index] = nil end
end
for index, value in pairs(ClaustOrephobic.allowed_types) do
    if type(value) ~= "string" then ClaustOrephobic.allowed_types[index] = nil end
end
for index, value in pairs(ClaustOrephobic.allowed_entity_names) do
    if type(value) ~= "string" then ClaustOrephobic.allowed_entity_names[index] = nil end
end

-- Build ignored sets from ClaustOrephobic API + easy-mode setting.
local ignoredGroups = {resource = true, ["mining-drill"] = true}
local ignoredSubgroups = {}
local ignoredEntities  = {}
for _, v in pairs(ClaustOrephobic.allowed_subgroups)    do ignoredSubgroups[v] = true end
for _, v in pairs(ClaustOrephobic.allowed_types)        do ignoredGroups[v]    = true end
for _, v in pairs(ClaustOrephobic.allowed_entity_names) do ignoredEntities[v]  = true end
if settings.startup["claustorephobic-easy-mode"].value then
    for group in string.gmatch(settings.startup["claustorephobic-allowed-prototypes"].value, "%S+") do
        ignoredGroups[group] = true
    end
end

-- Build set of player-placeable entity names upfront (item.place_result lookup).
local placeableNames = {}
for _, item in pairs(data.raw.item or {}) do
    if item.place_result then placeableNames[item.place_result] = true end
end

-- 4. Add collision layer to buildable entities so they can't be placed on ore.
local ownableEntities = require("utils.data.entities-with-owners")

local function restrict_entity(proto)
    local recurse = restrict_entity
    proto.collision_mask = maskutil.get_mask(proto)
    local mask = proto.collision_mask
    if mask and mask.layers and mask.layers["object"]
    and placeableNames[proto.name]
    and not ignoredSubgroups[proto.subgroup]
    and not ignoredEntities[proto.name]
    and not mask.altered_by_claustorephobic
    then
        mask.layers[CLAUST_LAYER] = true
        mask.altered_by_claustorephobic = true
        if proto.next_upgrade and proto.next_upgrade ~= "" then
            recurse(data.raw[proto.type][proto.next_upgrade])
        end
    elseif not mask.altered_by_claustorephobic then
        log("Allowing entity " .. proto.name)
    end
end

log("ClaustOrephobic starting modification of collision masks.")
for group in pairs(ownableEntities) do
    if not ignoredGroups[group] then
        for _, proto in pairs(data.raw[group] or {}) do
            restrict_entity(proto)
        end
    else
        log("Allowing group " .. group)
    end
end
log("Finished collision mask modifications.")
end -- collision mask modifications
