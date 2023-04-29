local util_functions = require("utils.parse-autoplace")

local resources = data.raw["resource"]

log("ClaustOrephobic scraping ore autoplaces.")
local noise = require("noise")
local tne = noise.to_noise_expression
local orePrototypes = {}
local oreData = {}
local i
for resourceName, prototype in pairs(resources) do
	if prototype.autoplace then
		-- log(serpent.block(prototype.autoplace, {refcomment = true}))
		local bBox = prototype.collision_box
		local longestDimension = math.max(bBox[2][1] - bBox[1][1], bBox[2][2] - bBox[1][2])
		if longestDimension <= 1 then -- if it's a nondisabled ore
			i = (i or 0) + 1
			orePrototypes[resourceName] = prototype
			oreData[resourceName] = util_functions.find_autoplace_argument("all", prototype.autoplace)
			if oreData[resourceName].base_density == "unfound" then
				-- if another mod is messing with ore gen in a way that this mod can't parse,
				-- exclude affected ores from this mod's modifications; otherwise, finish setup
				oreData[resourceName] = nil
				orePrototypes[resourceName] = nil
				i = i - 1
			else
				oreData[resourceName].index = i
			end
			-- log(longestDimension .. " " .. serpent.block(oreData[resourceName]))
		end
	end
end
log("Autoplace dump complete.")

local startingResourceInnerRadius = settings.startup["claustorephobic-starting-radius"]
.value                                                                                        -- the radius that will not be initially covered by ore
local startingResourceOuterRadius = math.sqrt(2) *
startingResourceInnerRadius                                                                   -- the radius in which starter placement has full influence
local regularResourceRadius = math.sqrt(4 * (2 * math.pow(startingResourceOuterRadius, 2) -
	---@diagnostic disable-next-line: param-type-mismatch
	math.pow(startingResourceInnerRadius, 2)))
-- the radius beyond which regular placement has full influence; between this and startingResourceOuterRadius, placement is interpolated

local regularInfluence = (noise.var("distance") - startingResourceOuterRadius) /
	(regularResourceRadius - startingResourceOuterRadius)
regularInfluence = noise.delimit_procedure(noise.clamp(regularInfluence, 0, 1, noise.csloc(0)))

local adjustedDensity = {}
local totalStarterDensity
local totalRegularDensity
for resourceName, data in pairs(oreData) do
	local control_settings = noise.get_control_setting(resourceName)
	adjustedDensity[resourceName] =
		noise.delimit_procedure(control_settings["frequency_multiplier"] * control_settings["size_multiplier"] *
			data.base_density)
	if data.has_starting_area_placement then
		totalStarterDensity =
			totalStarterDensity and totalStarterDensity + adjustedDensity[resourceName] or adjustedDensity[resourceName]
	end
	totalRegularDensity =
		totalRegularDensity and totalRegularDensity + adjustedDensity[resourceName] or adjustedDensity[resourceName]
end
totalStarterDensity = noise.delimit_procedure(totalStarterDensity)
totalRegularDensity = noise.delimit_procedure(totalRegularDensity)
local totalDensity = totalStarterDensity + (totalRegularDensity - totalStarterDensity) * regularInfluence

log("ClaustOrephobic starting autoplace modifications.")
for toPlace, dataToPlace in pairs(oreData) do
	log("ClaustOrephobic modifying autoplace expressions of " .. toPlace .. "...")
	orePrototypes[toPlace].autoplace.order = "e"
	local target = noise.random_penalty(1, 1, { x = tne(dataToPlace.index), y = noise.var("map_seed") })
	local regularDensityBelowTarget
	local starterDensityBelowTarget
	for toOrder, dataToOrder in pairs(oreData) do
		if toPlace ~= toOrder then
			local compareTo = noise.random_penalty(1, 1, { x = tne(dataToOrder.index), y = noise.var("map_seed") })
			local comparison
			if dataToPlace.index < dataToOrder.index then
				comparison = noise.less_or_equal(compareTo, target)
			else
				comparison = noise.less_than(compareTo, target)
			end
			regularDensityBelowTarget =
				regularDensityBelowTarget and regularDensityBelowTarget + comparison * adjustedDensity[toOrder]
				or comparison * adjustedDensity[toOrder]
			if dataToOrder.has_starting_area_placement then
				starterDensityBelowTarget =
					starterDensityBelowTarget and starterDensityBelowTarget + comparison * adjustedDensity[toOrder]
					or comparison * adjustedDensity[toOrder]
			end
		end
	end
	regularDensityBelowTarget = noise.delimit_procedure(regularDensityBelowTarget)
	starterDensityBelowTarget = noise.delimit_procedure(starterDensityBelowTarget)
	local densityBelowTarget = starterDensityBelowTarget +
		(regularDensityBelowTarget - starterDensityBelowTarget) * regularInfluence
	local probabilityExpression
	local expression
	if settings.startup["claustorephobic-ore-generation-mode"].value == "scrambled" then
		expression = 1 - noise.random(1) -- random between [0 and 1)
	end
	if settings.startup["claustorephobic-ore-generation-mode"].value == "pie" or settings.startup["claustorephobic-ore-generation-mode"].value == "spiral" then
		expression = ((noise.atan2(noise.var("y"), noise.var("x")) / (math.pi)) + 1) / 2
		if settings.startup["claustorephobic-ore-generation-mode"].value == "spiral" then
			expression = noise.fmod(
				expression +
				noise.clamp((noise.var("distance") - startingResourceInnerRadius) / (startingResourceInnerRadius * 20), 0,
					math.huge),
				1
			)
		end
	end
	if settings.startup["claustorephobic-ore-generation-mode"].value == "noise" then
		expression = noise.function_application("factorio-quick-multioctave-noise",
			{
				x = noise.var("x") + 1 / 257 * noise.var("distance") / noise.absolute_value(noise.var("distance")),
				y = noise.var("y") + 1 / 257 * noise.var("distance") / noise.absolute_value(noise.var("distance")),
				seed0 = noise.var("map_seed"),
				seed1 = 100,
				input_scale = 1 / 256,
				output_scale = 1,
				octaves = 10,
				octave_input_scale_multiplier = 1 / 2,
				octave_output_scale_multiplier = 1 / 2,
				octave_seed0_shift = 100,
			},
			noise.csloc(0)
		) / 1.998046875 + 1
		expression = noise.ridge(noise.fmod(expression, 1), 0, 1)
	end
	expression = expression * totalDensity
	local aboveMin
	local aboveMax
	local doPlace
	local densityAboveTarget
	if dataToPlace.has_starting_area_placement then
		doPlace = noise.less_than(0, adjustedDensity[toPlace]) -- always true for starter ores
		densityAboveTarget = densityBelowTarget + adjustedDensity[toPlace]
	else
		doPlace = noise.less_than(0, (adjustedDensity[toPlace] * regularInfluence))
		densityAboveTarget = densityBelowTarget + (adjustedDensity[toPlace] * regularInfluence)
	end
	aboveMin = noise.if_else_chain( -- ensure ores that aren't suitable for placement are never placed
		doPlace,
		noise.less_or_equal(
			noise.if_else_chain( -- widen range if at start or end of order to ensure no gaps
				noise.equals(densityBelowTarget, 0)
				- 1,
				densityBelowTarget
			),
			expression
		),
		0
	)
	aboveMax = noise.if_else_chain(
		doPlace,
		noise.less_than(
			noise.if_else_chain(
				noise.equals(densityAboveTarget, totalDensity),
				totalDensity + 1,
				densityAboveTarget
			),
			expression
		),
		1
	) -- the above shouldn't have any actual effect on ore distribution, as 'expression' ranges from [0,totalDensity)
	-- but this ensures no ores can be placed in the starting area where they don't belong, and that no gap is left behind
	expression = aboveMin - aboveMax
	expression = expression * noise.less_or_equal(startingResourceInnerRadius, noise.var("distance"))
	orePrototypes[toPlace].autoplace.probability_expression = expression
	probabilityExpression = expression
	local richnessMultiplier = noise.get_control_setting(toPlace)["richness_multiplier"]
	local rqMultiplier = dataToPlace.starting_rq_factor_multiplier +
		(dataToPlace.regular_rq_factor_multiplier - dataToPlace.starting_rq_factor_multiplier) * regularInfluence
	rqMultiplier = rqMultiplier * (adjustedDensity[toPlace] / dataToPlace.base_density) ^ (1 / 3)
	local relativeStarterArea = 70 -- An estimate of how much larger the starting area is than the starter ore patches.
	local richness = (relativeStarterArea ^ (1 / 3)) * totalDensity +
		(dataToPlace.additional_richness / relativeStarterArea * rqMultiplier) * (startingResourceInnerRadius / 120) ^ 2
	-- turns out, adjusting adjusted_density according to distribution equals totaldensity...
	richness = richness * richnessMultiplier * dataToPlace.richness_post_multiplier
	richness = richness *
		(1 + (noise.clamp(noise.var("distance") - startingResourceOuterRadius, 0, math.huge) * regularInfluence) / (1300 / (relativeStarterArea ^ (1 / 3))))
	richness = noise.max(richness, dataToPlace.minimum_richness)
	orePrototypes[toPlace].autoplace.richness_expression = richness * probabilityExpression
end
log("Finished autoplace modifications.")

local ignoredGroups = { "resource", "mining-drill" }
if settings.startup["claustorephobic-easy-mode"].value then -- Only use easy mode allowed-prototypes setting if easy mode is on
	---@diagnostic disable-next-line: param-type-mismatch
	for group in string.gmatch(settings.startup["claustorephobic-allowed-prototypes"].value, "%S+") do
		log("Ignoring all " .. group .. " prototypes...")
		if not util_functions.search_table(ignoredGroups, group) then
			table.insert(ignoredGroups, group)
		end
	end
end

log("ClaustOrephobic starting modification of collision masks.")
for group, _ in pairs(defines.prototypes.entity) do
	for _, prototype in pairs(data.raw[group]) do
		if not util_functions.search_table(ignoredGroups, prototype.type) and prototype.collision_mask then
			-- only change prototypes that aren't excluded via easy-mode or initial list
			local mask
			local oldMask
			local replaceGroup
			if prototype then
				while prototype.collision_mask do -- replicate changes through all upgrades, regardless of initial eligibility
					oldMask = table.deepcopy(prototype.collision_mask)
					replaceGroup = prototype.fast_replaceable_group
					if not util_functions.search_table(prototype.collision_mask, "resource-layer") and not mask then
						table.insert(prototype.collision_mask, "resource-layer")
					elseif mask then
						prototype.collision_mask = mask
					end
					mask = prototype.collision_mask
					if prototype.next_upgrade then
						for _, tbl in pairs(data.raw) do
							for name, upgrade in pairs(tbl) do
								if (
										name == prototype.next_upgrade and
										upgrade.fast_replaceable_group == replaceGroup and
										upgrade.collision_mask and
										util_functions.match(upgrade.collision_mask, oldMask)
									) then
									prototype = upgrade
								end
							end
						end
					else
						break
					end
				end
			end
		end
	end
end
log("Finished collision mask modifications.")
