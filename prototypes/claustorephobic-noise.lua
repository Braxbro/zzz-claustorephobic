local nfunc = "noise-function"
local nexp = "noise-expression"
local modname = "claustorephobic"

-- fetch values from resource_autoplace_all_patches for futureproofing
local raap = data.raw["noise-function"].resource_autoplace_all_patches
local raap_consts = {}
raap_consts.r_start = raap.local_expressions.starting_resource_placement_radius
raap_consts.fade_in = raap.local_expressions.regular_patch_fade_in_distance
raap_consts.dist_2x = raap.local_expressions.double_density_distance

-- NOISE EXPRESSIONS --
data:extend{
    {
        type = nexp
      , name = "theta"
      , expression = "(atan2(y_from_start, x_from_start) / (2 * pi)) % 1"
      , comment = "'theta' from the nearest starting point as an angular value normalized to [0,1) rotations. \z
        This allows simple multiplication to convert 'theta' to radians, degrees, or any other unit you prefer."
    }
  , {
        type = nexp
      , name = "distance_c"
      , expression = "distance_from_nearest_point{x = x_adj, y = y_adj, points = starting_positions}"
      , local_expressions = {
            x_adj = "x + .5"
          , y_adj = "y + .5"
        }
      , comment = "As distance, except calculated based on tile center."
    }
  , {
        type = nexp
      , name = "theta_c"
      , expression = "(atan2(y_adj, x_adj) / (2 * pi)) % 1"
      , local_expressions = {
            x_adj = "x_from_start + .5"
          , y_adj = "y_from_start + .5"
        }
      , comment = "As theta, except calculated based on tile center."
    }
  , {
        type = nexp
      , name = modname .. "-inner-radius"
      , expression = "if(var('control:" .. modname .. "-clearings:size') > 0, \z
        var('control:" .. modname .. "-clearings:size'), starting_area_radius / base_res_start_radius) * \z
        sqrt(150^2 - base_res_start_radius^2)"
      , local_expressions = {
            base_res_start_radius = raap_consts.r_start
          , starting_area_radius = raap_consts.r_start
        }
      , comment = "Inner radius of the starting area clearing, accounting for the clearings control slider. \z
        Scales linearly with control; falls back to starting_area_radius / 150 when disabled."
    }
  , {
        type = nexp
      , name = modname .. "-starting-area-influence"
      , expression = modname .. "_starting_area_influence(var('claustorephobic-shape'))"
      , comment = "Starting area influence at tile center. -1 inside the clearing, \z
        [0,1] tapering from the inner to outer edge of the starting zone, 0 beyond."
    }
  , {
        type = nexp
      , name = modname .. "-starter-weight"
      , expression = "max(var('" .. modname .. "-starting-area-influence'), 0)"
      , comment = "Distance weight for starter (starting-area) placement. 0 in clearing \z
        and beyond the starting zone, peaks at 1 at the starting zone inner edge."
    }
  , {
        type = nexp
      , name = modname .. "-regular-weight"
      , expression = "if(var('" .. modname .. "-starting-area-influence') >= 0, \z
        1 - var('" .. modname .. "-starting-area-influence'), 0)"
      , comment = "Distance weight for regular (outside-starting-area) placement. 0 in \z
        clearing and at starting zone inner edge, tapering up to 1 at outer edge and beyond."
    }
}

--- IGNORE FUNCTION ---
data:extend{
    {
        type = nfunc
      , name = modname .. "_ignore"
      , parameters = {"value"}
      , expression = "value"
      , comment = "Does nothing by itself. ClaustOrephobic will not search for \z
        resource_autoplace_all_patches calls inside of the passed value."
    }
}

--- NOISE FUNCTIONS ---
data:extend{
    {
        type = nfunc
      , name = modname .. "_cap"
      , parameters = {
            "patch_set"
          , "i"
          , "patch_set_id"
          , "patch_set_count"
          , "patch_set_index"
          , "coverage"
          , "control_size"
        }
      , expression = "(patch_set == patch_set_id) * (phase == patch_set_index) \z
        * coverage * control_size"
      , local_expressions = {
            phase = "floor(i % patch_set_count)"
        }
      , comment = "Short for coverage at point. \z
        Returns coverage * control_size when patch_set matches patch_set_id \z
        and floor(i % patch_set_count) matches patch_set_index, else 0. \z
        Per-ore wrapper noise-functions with baked constants are emitted by data-final-fixes.lua. \z
        Wander correction (phase blending) is applied to the i argument by the caller."
    }
  , {
        type = nfunc
      , name = modname .. "_endurance"
      , parameters = {
            "base_qty"
          , "base_density"
          , "rq_factor"
          , "base_spots_per_km2"
          , "additional_richness"
          , "mining_time"
        }
      , expression = modname .. "_avg_richness(base_qty, base_density, rq_factor, \z
        base_spots_per_km2, additional_richness) * mining_time"
      , comment = "A rough estimate of how long a given tile of a patch will last. \z
        Most useful for relative comparisons in conjunction with coverage."
    }
  , {
        type = nfunc
      , name = modname .. "_coverage"
      , parameters = {
            "rq_factor"
          , "base_density"
          , "base_spots_per_km2"
        }
      , expression = "rq_squared * base_density ^ (2/3) * base_spots_per_km2 ^ (1/3)"
      , local_expressions = {
            rq_squared = "rq_factor ^ 2"
        }
      , comment = "A rough estimate of how much of the world is covered by a given resource. \z
        Most useful for relative comparisons in conjunction with endurance."
    }
  , {
        type = nfunc
      , name = modname .. "_avg_richness"
      , parameters = {
            "base_qty"
          , "base_density"
          , "rq_factor"
          , "base_spots_per_km2"
          , "additional_richness"
        }
      , expression = "(peak / 3) + additional_richness"
      , local_expressions = {
            adj_qty = "base_qty * base_density / base_spots_per_km2"
          , peak    = "3 * (adj_qty ^ (1/3)) / (pi * rq_factor ^ 2)"
        }
      , comment = "A rough estimate of a patch's average richness per tile. \z
        For an estimate factoring mining time, see endurance."
    }
  , {
        type = nfunc
      , name = modname .. "_polygon_outer_factor"
      , parameters = {"angle", "sides"}
      , expression = "cos(((angle + half_side_arc) % side_arc) - half_side_arc)"
      , local_expressions = {
            half_side_arc = "pi / sides"
          , side_arc      = "2 * half_side_arc"
        }
      , comment = "Calculates the ratio that, when multiplied by distance, \z
        converts a circular distance to a circumscribed polygon with a given number of sides."
    }
  , {
        type = nfunc
      , name = modname .. "_polygon_inner_factor"
      , parameters = {"angle", "sides"}
      , expression = modname .. "_polygon_outer_factor(angle, sides) / cos(half_side_arc)"
      , local_expressions = {
            half_side_arc = "pi / sides"
        }
      , comment = "Calculates the ratio that, when multiplied by distance, \z
        converts a circular distance to an inscribed polygon with a given number of sides."
    }
  , {
        type = nfunc
      , name = modname .. "_starting_area_influence"
      , parameters = {"dist"}
      , expression = "if(dist < sqrt(inner_radius_squared), -1, falloff_weight)"
      , local_expressions = {
            base_res_start_radius = raap_consts.r_start
          , inner_radius          = "var('" .. modname .. "-inner-radius')"
          , inner_radius_squared  = "inner_radius^2"
          , falloff_start_squared = "(inner_radius^2 + (base_res_start_radius^2 / 2))"
          , falloff_end_squared   = "(inner_radius^2 + (base_res_start_radius^2 * 3 / 2))"
          , falloff_start         = "sqrt(falloff_start_squared)"
          , falloff_end           = "sqrt(falloff_end_squared)"
          , falloff_weight        = "1 - clamp((dist - falloff_start) / (falloff_end - falloff_start), 0, 1)"
        }
      , comment = "The weight, ranging from [0,1], applied to ClaustOrephobic starting area resource placement. \z
        Inside the starting clearing, will be -1. Scales area linearly based on clearing size if they are not \z
        disabled; otherwise, scales with starting_area_radius."
    }
}

-- INTERNAL NOISE EXPRESSIONS --

-- These won't have the comment property. They aren't meant for external reference.

-- Shape-distance noise expressions: renormalized distance accounting for starting area shape.
-- Circle is the default (highest order).  Common polygons are named options.
-- The startup-setting polygon bakes in whatever sides count the user chose.
local poly_sides = settings.startup["claustorephobic-polygon-sides"].value

local function poly_expr(sides)
    return string.format(
        "distance_c * claustorephobic_polygon_outer_factor(theta_c * 2 * pi, %d)", sides)
end
data:extend{
    { type = "noise-expression", name = "claustorephobic-shape"
      -- also claustorephobic-shape-circle
    , intended_property = "claustorephobic-shape"
    , order = "2000"
    , expression = "distance_c"
    }
  , { type = "noise-expression", name = "claustorephobic-shape-triangle"
    , intended_property = "claustorephobic-shape"
    , expression = poly_expr(3)
    }
  , { type = "noise-expression", name = "claustorephobic-shape-square"
    , intended_property = "claustorephobic-shape"
    , expression = poly_expr(4)
    }
  , { type = "noise-expression", name = "claustorephobic-shape-hexagon"
    , intended_property = "claustorephobic-shape"
    , expression = poly_expr(6)
    }
  , { type = "noise-expression", name = "claustorephobic-shape-octagon"
    , intended_property = "claustorephobic-shape"
    , expression = poly_expr(8)
    }
  , { type = "noise-expression", name = "claustorephobic-shape-polygon"
    , intended_property = "claustorephobic-shape"
    , expression = poly_expr(poly_sides)
    }
}

-- Band-position NE: maps world pos → [0, 1), mode-dependent.
-- All four modes are registered with intended_property so the player can select
-- in the map generator GUI.  Scrambled is the hardcoded default.
local band_exprs = {
    pie      = "theta_c",
    spiral   = "(theta_c + clamp((var('claustorephobic-shape') - var('claustorephobic-inner-radius')) / \z
        (var('claustorephobic-inner-radius') * 20), 0, 1e30)) %% 1",
    scrambled = "(1 - random_penalty{x = x, y = y, source = 1, seed = map_seed, amplitude = 1}) % 1",
    noise    = "abs(multioctave_noise{x = x, y = y, seed0 = map_seed, " ..
        "seed1 = \"claustorephobic-band\", persistence = 0.5, octaves = 4, " ..
        "input_scale = 0.00390625, output_scale = 0.5}) % 1",
}

data:extend{
    -- Per-mode alternatives selectable in map gen GUI (scrambled is default, order "2000").
    { type = "noise-expression", name = "claustorephobic-preset-pie"
    , intended_property = "claustorephobic-preset"
    , expression = band_exprs.pie
    }
  , { type = "noise-expression", name = "claustorephobic-preset-spiral"
    , intended_property = "claustorephobic-preset"
    , expression = band_exprs.spiral
    }
  , { type = "noise-expression", name = "claustorephobic-preset"
    -- also claustorephobic-preset-scrambled
    , intended_property = "claustorephobic-preset"
    , order = "2000"
    , expression = "(" .. band_exprs.scrambled .. " + offset) % 1"
    , local_expressions = {
      offset = band_exprs.noise
    }
    }
  , { type = "noise-expression", name = "claustorephobic-preset-noise"
    , intended_property = "claustorephobic-preset"
    , expression = band_exprs.noise
    }
}