--[[
  Compares two values.
  If the values are tables, checks if all of b's indices are present and match in a.
  Otherwise, returns a == b.
]]
local function match(a, b)
  if type(a) == type(b) then
    if type(a) == "table" then
      for i, v in pairs(b) do
        if not match(a[i], v) then
          return false
        end
      end
      return true
    else
      return a == b
    end
  else
    return false
  end
end

--[[
  Searches for the first value in tbl that matches toMatch. (see match above)
  breadthFirst is an optional boolean argument that can be set to true to use a breadth-first search instead of a depth-first one.
  indexTable is an optional argument intended only for when the function calls itself recursively while depth-first searching.
]]
local function search_table(tbl, toMatch, breadthFirst, indexTable)
  local recurse = search_table
  if type(tbl) ~= "table" or not toMatch then -- There's nothing to search, or nothing to find
    -- if you require this and pass a table with an irresponsibly designed metatable to this function, I will not fix errors you cause.
    return nil
  end
  if not breadthFirst then -- depth-first search
    if not indexTable then -- make sure toMatch doesn't match source table
      if match(tbl, toMatch) then
        return tbl, indexTable
      end
      indexTable = {}
    end
    local found, finalIndexTable
    for index, value in pairs(tbl) do
      table.insert(indexTable, index)
      if match(value, toMatch) then -- try to match first
        found, finalIndexTable = value, indexTable
      elseif type(value) == "table" then -- can we go deeper?
        found, finalIndexTable = recurse(value, toMatch, breadthFirst, indexTable)
      end
      if found and finalIndexTable then
        return found, finalIndexTable
      end
      table.remove(indexTable)
    end
  else -- breadth-first search
    local queue = {[{}] = table.deepcopy(tbl)}
    repeat
    local depth = {}
    for index, value in pairs(queue) do
      if match(value, toMatch) then
        return value, index
      end
      depth[index] = value
      queue[index] = nil
    end
    for indexTable, checked in pairs(depth) do
      if type(checked) == "table" then
        for index, value in pairs(checked) do
          local queueIndex = table.deepcopy(indexTable)
          table.insert(queueIndex, index)
          queue[queueIndex] = value
        end
      end
      depth[indexTable] = nil
    end
    local queueLength = 0
    for _, _ in pairs(queue) do
      queueLength = queueLength + 1
    end
    until(queueLength == 0)
  end
end

--[[ 
  Attempts to find a named argument to resource_autoplace.resource_autoplace_settings in an autoplace expression.
  Returns the argument's value if it can be found and the given autoplace was created using resource_autoplace.resource_autoplace_settings, or nil otherwise.
  Some arguments cannot be retrieved, as they are processed before being converted into expressions, and therefore cannot be found via source locations.
  Additionally, 'name' and 'order' can always be retrieved, even if the autoplace was manually created.
]]
local function find_autoplace_argument(argument, autoplace, breadthFirst)
  local recurse = find_autoplace_argument
  -- set up function --
  autoplace.probability_expression = autoplace.probability_expression or {}
  autoplace.probability_expression.source_location = autoplace.probability_expression.source_location or {}
  autoplace.richness_expression = autoplace.richness_expression or {}
  autoplace.richness_expression.source_location = autoplace.richness_expression.source_location or {}
  local searchable_expressions = {} -- catch overridden/manually specified expressions
  if autoplace.probability_expression.source_location.filename == "__core__/lualib/resource-autoplace.lua" then
    table.insert(searchable_expressions, "probability_expression")
  end
  if autoplace.richness_expression.source_location.filename == "__core__/lualib/resource-autoplace.lua" then
    table.insert(searchable_expressions, "richness_expression")
  end
  local direct_indexes = {}
  do -- setup direct_indexes
    direct_indexes["name"] = autoplace.control
    direct_indexes["order"] = autoplace.order
  end
  local identifiers = {}
  do -- setup identifier table for each argument
    --[[
      Each element of identifiers is a table containing the following:
      table targets: a table of partial expressions to search for. 
        NOTE: Table indices must be included when they are different than 1. See lines 470, 450, and 312 for examples.
      table indices: an ordered list of indices to reach the desired value from a completed expression matching one of targets.
      optional function getValue: A function that accepts the following arguments and returns the desired value and a completed indexTable:
        found: a completed expression matching one of the targets
        indexTable: a list of indices forming a path to the completed expression from the source expression
        optional id: the index of targets that found is a completed version of
          NOTE: indexTable, when returned, should end at the last index containing all of the used values.
          For values that are plainly available, the last index is simply the index of the value.
        If getValue is present, identifiers[].indices may not be necessary. See line 371.
      optional table sources: A table of either probability_expression or richness_expression, for targets unique to either expression.
    ]]
    setmetatable(identifiers, {__index = function(tbl, key) -- Set default table; saves time and space below.
      tbl[key] = {}
      local newIndex = tbl[key]
      newIndex.targets = {}
      newIndex.indices = {}
      newIndex.sources = {}
      newIndex.getValue = function(found, indexTable)
        local indices = newIndex["indices"]
        -- log("Identifier default getter: navigating to value in " .. serpent.block(found) .. " by " .. serpent.block())
        for _, index in ipairs(indices) do
          found = found[index]
          table.insert(indexTable, index)
        end
        return found, indexTable
      end
      newIndex.addTarget = function(target) -- a fun little shorthand to make adding target expressions easier
        table.insert(newIndex.targets, target)
      end
      return newIndex
    end})
    identifiers["regular_patch_metaset"].addTarget({
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 264
      },
      type = "literal-number"
    })
    identifiers["regular_patch_metaset"].indices = {"literal_value"}
    identifiers["starter_patch_metaset"].addTarget({
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 293
      },
      type = "literal-number"
    })
    identifiers["starter_patch_metaset"].addTarget({
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 278
      },
      type = "literal-number"
    })
    identifiers["starter_patch_metaset"].indices = {"literal_value"}
    identifiers["base_density"].addTarget({
      arguments = {
        {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 78
          },
          type = "literal-number"
        }
      },
      function_name = "multiply",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 170
      },
      type = "function-application"
    })
    identifiers["base_density"].indices = {"arguments", 1, "literal_value"}
    identifiers["has_starting_area_placement"].addTarget({
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 293
      },
      type = "literal-number"
    })
    identifiers["has_starting_area_placement"].addTarget({
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 278
      },
      type = "literal-number"
    })
    identifiers["has_starting_area_placement"].default = false
    identifiers["has_starting_area_placement"].getValue = function(found, indexTable)
      if found then
        found = true
      else
        found = false
      end
      return found, indexTable -- Don't need to actually index anything; just the presence of a match indicates the value
    end
    identifiers["random_probability"].addTarget({
      arguments = {
        [2] = {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 86
          },
          type = "literal-number"
        }
      },
      function_name = "divide",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 376
      },
      type = "function-application"
    })
    identifiers["random_probability"].indices = {"arguments", 2, "literal_value"}
    identifiers["random_probability"].sources[1] = "richness_expression" -- technically available in both, but easier to find in richness
    identifiers["random_probability"].default = 1
    identifiers["base_spots_per_km2"].addTarget({
      arguments = {
        {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 78
          },
          type = "literal-number"
        }
      },
      function_name = "multiply",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 172
      },
      type = "function-application"
    })
    identifiers["base_spots_per_km2"].indices = {"arguments", 1, "literal_value"}
    identifiers["random_spot_size_minimum"].addTarget({
      arguments = {
        amplitude = {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 256
          },
          type = "literal-number"
        },
        source = {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 255
          },
          type = "literal-number"
        }
      },
      function_name = "random-penalty",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 196
      },
      type = "function-application"
    })
    identifiers["random_spot_size_minimum"].getValue = function(found,indexTable) -- need to calc from multiple values
      found = found["arguments"]
      table.insert(indexTable,"arguments") -- this will be the last value in the table, as both values are contained in this index
      found = found["source"]["literal_value"] - found["amplitude"]["literal_value"] -- maximum - (maximum - minimum) 
      return found, indexTable
    end
    identifiers["random_spot_size_maximum"].addTarget({
      arguments = {
        source = {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 255
          },
          type = "literal-number"
        }
      },
      function_name = "random-penalty",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 196
      },
      type = "function-application"
    })
    identifiers["random_spot_size_maximum"].indices = {"arguments", "source", "literal_value"}
    identifiers["regular_blob_amplitude_multiplier"].addTarget({arguments = {
        {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 78
          },
          type = "literal-number"
        }
      },
      function_name = "multiply",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 203
      },
      type = "function-application"
    })
    identifiers["regular_blob_amplitude_multiplier"].indices = {"arguments", 1, "literal_value"}
    identifiers["regular_blob_amplitude_multiplier"].getValue = function(found, indexTable)
      local indices = identifiers["regular_blob_amplitude_multiplier"].indices
      -- log("Identifier default getter: navigating to value in " .. serpent.block(found) .. " by " .. serpent.block())
      for _, index in ipairs(indices) do
        found = found[index]
        table.insert(indexTable, index)
      end
      return (found * 8), indexTable
    end
    identifiers["starter_blob_amplitude_multiplier"].addTarget({
      arguments = {
        {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 78
          },
          type = "literal-number"
        }
      },
      function_name = "multiply",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 238
      },
      type = "function-application"
    })
    identifiers["starter_blob_amplitude_multiplier"].indices = {"arguments", 1, "literal_value"}
    identifiers["starter_blob_amplitude_multiplier"].getValue = function(found, indexTable)
      local indices = identifiers["starter_blob_amplitude_multiplier"].indices
      -- log("Identifier default getter: navigating to value in " .. serpent.block(found) .. " by " .. serpent.block())
      for _, index in ipairs(indices) do
        found = found[index]
        table.insert(indexTable, index)
      end
      return (found * 8), indexTable
    end
    identifiers["additional_richness"].addTarget({
      arguments = {
        [2] = {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 54
          },
          type = "literal-number"
        }
      },
      function_name = "add",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 390
      },
      type = "function-application"
    })
    identifiers["additional_richness"].indices = {"arguments", 2, "literal_value"}
    identifiers["additional_richness"].sources[1] = "richness_expression"
    identifiers["additional_richness"].default = 0
    identifiers["minimum_richness"].addTarget({
      arguments = {
        [2] = {
          source_location = {
            filename = "__core__/lualib/resource-autoplace.lua",
            line_number = 393
          },
          type = "literal-number"
        },
      },
      function_name = "clamp",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 393
      },
      type = "function-application"
    })
    identifiers["minimum_richness"].indices = {"arguments", 2, "literal_value"}
    identifiers["minimum_richness"].sources[1] = "richness_expression"
    identifiers["minimum_richness"].default = 0
    identifiers["richness_post_multiplier"].addTarget({
      arguments = {
        {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 78
          },
          type = "literal-number"
        }
      },
      function_name = "multiply",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 113
      },
      type = "function-application"
    })
    identifiers["richness_post_multiplier"].indices = {"arguments", 1, "literal_value"}
    identifiers["richness_post_multiplier"].sources[1] = "richness_expression"
    identifiers["seed1"].addTarget({
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 259
      },
      type = "literal-number"
    })
    identifiers["seed1"].indices = {"literal_value"} -- literally trivial to get
    identifiers["regular_rq_factor_multiplier"].addTarget({
      arguments = {
        {
          source_location = {
            filename = "__core__/lualib/noise.lua",
            line_number = 78
          },
          type = "literal-number"
        }
      },
      function_name = "multiply",
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 197
      },
      type = "function-application"
    })
    identifiers["regular_rq_factor_multiplier"].indices = {"arguments", 1, "literal_value"}
    identifiers["regular_rq_factor_multiplier"].getValue = function(found, indexTable)
      local indices = identifiers["regular_rq_factor_multiplier"].indices
      -- log("Identifier default getter: navigating to value in " .. serpent.block(found) .. " by " .. serpent.block())
      for _, index in ipairs(indices) do
        found = found[index]
        table.insert(indexTable, index)
      end
      return (found * 10), indexTable
    end
    identifiers["regular_rq_factor_multiplier"].default = 1
    identifiers["starting_rq_factor_multiplier"].addTarget({
      literal_value = {
        arguments = {
          {
            source_location = {
              filename = "__core__/lualib/noise.lua",
              line_number = 78
            },
            type = "literal-number"
          }
        },
        function_name = "multiply",
        source_location = {
          filename = "__core__/lualib/resource-autoplace.lua",
          line_number = 300
        },
        type = "function-application"
      },
      source_location = {
        filename = "__core__/lualib/resource-autoplace.lua",
        line_number = 300
      },
      type = "literal-expression"
    })
    identifiers["starting_rq_factor_multiplier"].indices = {"literal_value", "arguments", 1, "literal_value"}
    identifiers["starting_rq_factor_multiplier"].getValue = function(found, indexTable)
      local indices = identifiers["starting_rq_factor_multiplier"].indices
      -- log("Identifier default getter: navigating to value in " .. serpent.block(found) .. " by " .. serpent.block())
      for _, index in ipairs(indices) do
        found = found[index]
        table.insert(indexTable, index)
      end
      return (found * 7), indexTable
    end
    identifiers["starting_rq_factor_multiplier"].default = 1
    setmetatable(identifiers, {}) -- make sure bad indexes properly return nil again
  end

  -- look for argument --
  
  if direct_indexes[argument] then -- for arguments with constant, known locations
    return direct_indexes[argument]
  end
  if identifiers[argument] then
    local found, indexTable
    for id, target in pairs(identifiers[argument].targets) do
      if not identifiers[argument].sources[id] then -- if the value isn't specific to probability or richness expressions, use probability
        identifiers[argument].sources[id] = searchable_expressions[1] -- use first 'resource-autoplace'-controlled expression
      end
      if not search_table(searchable_expressions, identifiers[argument].sources[id], breadthFirst) then
        log("Could not find source " .. tostring(identifiers[argument].sources[id]) .. " in " .. serpent.line(searchable_expressions))
        return nil -- there are no searchable_expressions that can be used as a source
      end
      found, indexTable = search_table(autoplace[identifiers[argument].sources[id]], target, breadthFirst)
      if found and indexTable then
        if not identifiers[argument].getValue then
          error("Couldn't find getValue() for argument " .. argument)
        end
        -- log("calling getValue for argument " .. argument)
        return identifiers[argument].getValue(found, indexTable, id)
      end
    end
    return identifiers[argument].default
  end
  if argument == "all" then
    local output = {}
    for argument, _ in pairs(direct_indexes) do
      -- log("Dumping value of all arguments: " .. argument)
      output[argument] = recurse(argument, autoplace, breadthFirst)
      -- log(argument .. " " .. tostring(output[argument]))
      if output[argument] == nil then
        output[argument] = "unfound"
      end
    end
    for argument, _ in pairs(identifiers) do
      -- log("Dumping value of all arguments: " .. argument)
      output[argument] = recurse(argument, autoplace, breadthFirst)
      -- log(argument .. " " .. tostring(output[argument]))
      if output[argument] == nil then
        output[argument] = "unfound"
      end
    end
    return output
  end
  error("Attempt to find invalid autoplace argument " .. argument) -- Only reaches this point if argument is bad.
end

local util_functions = {}
util_functions.match = match
util_functions.search_table = search_table
util_functions.find_autoplace_argument = find_autoplace_argument
return util_functions

