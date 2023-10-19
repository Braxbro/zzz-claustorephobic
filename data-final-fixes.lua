local util_functions = require("utils.parse-autoplace")
local maskUtil = require("collision-mask-util")
local claustorephobicLayer = maskUtil.get_first_unused_layer()

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
		prototype.collision_mask = table.deepcopy(maskUtil.get_mask(prototype))
		prototype.selection_priority = 49 -- one lower than standard building priority, one higher than artillery remote entities priority
		maskUtil.add_layer(prototype.collision_mask, claustorephobicLayer)
		local bBox = prototype.collision_box
		local longestDimension = math.max(bBox[2][1] - bBox[1][1], bBox[2][2] - bBox[1][2])
		if longestDimension <= 1 then -- if it's a nondisabled ore
			i = (i or 0) + 1
			orePrototypes[resourceName] = prototype
			oreData[resourceName] = util_functions.find_autoplace_argument("all", prototype.autoplace)
			local isInvalid
			if oreData[resourceName].starter_patch_metaset == "unfound" then -- ignore if it can't find starter patch metasets.
				oreData[resourceName].starter_patch_metaset = nil
				isInvalid = util_functions.search_table(oreData[resourceName], "unfound")
				oreData[resourceName].starter_patch_metaset = "unfound"
			else
				isInvalid = util_functions.search_table(oreData[resourceName], "unfound")
			end
			if isInvalid then
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

for group, prototypes in pairs(data.raw) do
	if group ~= "resource" then
		for _, prototype in pairs(prototypes) do
			if prototype.selection_priority and prototype.selection_priority <= 49 then
				prototype.selection_priority = prototype.selection_priority > 0 and prototype.selection_priority - 1 or 0 -- knock everything at 49 or lower down a priority to maintain consistency
			end
		end
	end
end
log("Autoplace dump complete.")

local startingAreaShapes = {} --[[
	Table of tables of four values in order, indexed numerically:
	x - The effective x position function
	y - The effective y position function
	distance - the effective distance function
	theta - How far around the perimeter of the shape with a radius equal to distance is, from 0 to 1
]]
startingAreaShapes["circle"] = {noise.var("x"), noise.var("y"), noise.var("distance"), ((noise.atan2(noise.var("y"), noise.var("x")) / (math.pi)) + 1) / 2} -- circle
do -- square
	local x, y, distance, theta
	distance = noise.if_else_chain(noise.less_or_equal(noise.absolute_value(noise.var("x")), noise.absolute_value(noise.var("y"))), noise.absolute_value(noise.var("y")), noise.absolute_value(noise.var("x")))
	theta = ((noise.atan2(noise.var("y"), noise.var("x")) / (math.pi)) + 1) / 2
	x = noise.cos(theta * 2 * math.pi) * distance
	y = noise.sin(theta * 2 * math.pi) * distance
	startingAreaShapes["square"] = {x, y, distance, theta}
end
local x, y, distance, theta = table.unpack(startingAreaShapes[settings.startup["claustorephobic-starting-area-shape"].value])

local startingResourceInnerRadius = settings.startup["claustorephobic-starting-radius"].value -- the radius that will not be initially covered by ore
local startingResourceOuterRadius = math.sqrt(2) * startingResourceInnerRadius -- the radius in which starter placement has full influence
local regularResourceRadius = math.sqrt(4 * (2 * math.pow(startingResourceOuterRadius, 2) -
	---@diagnostic disable-next-line: param-type-mismatch
	math.pow(startingResourceInnerRadius, 2)))
-- the radius beyond which regular placement has full influence; between this and startingResourceOuterRadius, placement is interpolated

local regularInfluence = (distance - startingResourceOuterRadius) /
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
	orePrototypes[toPlace].autoplace.order = "z" -- place absolute last in generation
	orePrototypes[toPlace].tree_removal_probability = nil -- don't remove trees on affected ores
	orePrototypes[toPlace].tree_removal_max_distance = nil
	orePrototypes[toPlace].cliff_removal_probability = 0
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
		expression = theta
		if settings.startup["claustorephobic-ore-generation-mode"].value == "spiral" then
			expression = noise.fmod(
				expression +
				noise.clamp((distance - startingResourceInnerRadius) / (startingResourceInnerRadius * 20), 0,
					math.huge),
				1
			)
		end
	end
	if settings.startup["claustorephobic-ore-generation-mode"].value == "noise" then
		expression = noise.function_application("factorio-quick-multioctave-noise",
			{
				x = x + 1 / 257 * distance / noise.absolute_value(distance),
				y = y + 1 / 257 * distance / noise.absolute_value(distance),
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
				noise.equals(densityBelowTarget, 0),
				-1,
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
	expression = expression * noise.less_or_equal(startingResourceInnerRadius, distance)
	
	local probabilityTarget = oreData[toPlace].random_probability == 1 and {
		function_name = "multiply",
		source_location = {
		filename = "__core__/lualib/resource-autoplace.lua",
		line_number = 377
		},
		type = "function-application"
	} or {
		function_name = "clamp",
		source_location = {
			filename = "__core__/lualib/resource-autoplace.lua",
			line_number = 374
		},
		type = "function-application"
	}
	local _, probabilityIndexTable = util_functions.search_table(orePrototypes[toPlace].autoplace.probability_expression, probabilityTarget)
	if probabilityIndexTable then 
		-- try to replace in-place for mods like bz-lead that wrap autoplaces in modifiers. 
		-- Probably a bad idea for probability, but if I'm gonna respect nonstandard noise expressions I might as well respect probability modifications too.
		local lastIndex, subTable
		for _, index in pairs(probabilityIndexTable) do
			if not lastIndex then
				subTable = orePrototypes[toPlace].autoplace.probability_expression
			else
				subTable = subTable[lastIndex]
			end
			lastIndex = index
		end
		subTable[lastIndex] = expression
	else
		orePrototypes[toPlace].autoplace.probability_expression = expression
	end
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
		(1 + (noise.clamp(distance - startingResourceOuterRadius, 0, math.huge) * regularInfluence) / (1300 / (relativeStarterArea ^ (1 / 3))))
	richness = noise.max(richness, dataToPlace.minimum_richness)

	local richnessTarget = {
		function_name = "multiply",
		source_location = {
		filename = "__core__/lualib/resource-autoplace.lua",
		line_number = 407
		},
		type = "function-application"
	}
	local _, richnessIndexTable = util_functions.search_table(orePrototypes[toPlace].autoplace.richness_expression, richnessTarget)
	if richnessIndexTable then 
		-- try to replace in-place for mods like bz-lead that wrap autoplaces in modifiers.
		local lastIndex, subTable
		for _, index in pairs(richnessIndexTable) do
			if not lastIndex then
				subTable = orePrototypes[toPlace].autoplace.richness_expression
			else
				subTable = subTable[lastIndex]
			end
			lastIndex = index
		end
		subTable[lastIndex] = richness * probabilityExpression
	else
		orePrototypes[toPlace].autoplace.richness_expression = richness * probabilityExpression
	end
end
log("Finished autoplace modifications.")

local ignoredGroups = { "resource", "mining-drill" }
local ignoredSubgroups = ClaustOrephobic.allowed_subgroups
if settings.startup["claustorephobic-easy-mode"].value then -- Only use easy mode allowed-prototypes setting if easy mode is on
	---@diagnostic disable-next-line: param-type-mismatch
	for group in string.gmatch(settings.startup["claustorephobic-allowed-prototypes"].value, "%S+") do
		log("Ignoring all " .. group .. " prototypes...")
		if not util_functions.search_table(ignoredGroups, group) then
			table.insert(ignoredGroups, group)
		end
	end
end

local ownableEntities = require("utils.data.entities-with-owners") -- list of entityWithOwners
local alteredPrototypes = {}

log("ClaustOrephobic starting modification of collision masks.")
for group, _ in pairs(ownableEntities) do
	for _, prototype in pairs(data.raw[group]) do
		if
			(not util_functions.search_table(ignoredGroups, prototype.type)) and
			(prototype.collision_mask or maskUtil.get_default_mask(group)) and
			(not util_functions.search_table(ignoredSubgroups, prototype.subgroup)) -- subgroup check to ignore enemies
		then
			-- only change prototypes that aren't excluded via easy-mode or initial list
			if prototype and not alteredPrototypes[prototype.name] then
				-- ignore nonexistent prototypes and ones that have already been fixed
				prototype.collision_mask = maskUtil.get_mask(prototype)
				alteredPrototypes[prototype.name] = true
				if maskUtil.mask_contains_layer(prototype.collision_mask, "object-layer") then
					-- check the mask is supposed to collide with objects
					-- log("Modifying collision mask of " .. prototype.name)
					local oldMask = table.deepcopy(prototype.collision_mask) 
					-- the mask before it is modified; used for finding upgrades
					maskUtil.add_layer(prototype.collision_mask, claustorephobicLayer)
					while prototype.next_upgrade and prototype.next_upgrade ~= "" and not alteredPrototypes[prototype.next_upgrade] do
						local upgrade
						for _, possibleUpgrade in pairs(maskUtil.collect_prototypes_with_mask(oldMask)) do
							if (
								possibleUpgrade.name == prototype.next_upgrade and
								possibleUpgrade.fast_replaceable_group == prototype.fast_replaceable_group and
								util_functions.match(possibleUpgrade.collision_box, prototype.collision_box)
							) then
								upgrade = possibleUpgrade
								break
							end
						end
						-- log("Replicating collision mask changes to upgrade " .. upgrade.name .. " from " .. prototype.name)
						upgrade.collision_mask = prototype.collision_mask
						prototype = upgrade
						alteredPrototypes[prototype.name] = true
					end
					if prototype.next_upgrade == "" then
						log("Prototype " .. prototype.name .. " has an empty string for its next_upgrade property. This property is optional and should be nil if there is no next_upgrade.")
					end
				end
			end
		end
	end
end

log("Finished collision mask modifications.")
