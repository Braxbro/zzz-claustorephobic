-- this stuff was made obsolete by my discovery of serpent, but might be useful later? not sure.
-- keeping because it hardly takes any file size at all and won't run on its own here.

local function tableToString(tbl, indexParseFunc, valueParseFunc, indexValueSeparator)
    -- tostring() for tables. Optionally uses a given string-yielding function for indexes and/or values.
    local recurse = tableToString
    indexValueSeparator = indexValueSeparator or " = "
    if tostring(tbl) == "table" then
        local str = "{\n"
        for index, value in pairs(tbl) do
            str = str ..
            tostring((indexParseFunc or recurse)(index)) ..
            indexValueSeparator .. tostring((valueParseFunc or recurse)(value)) .. ",\n"
        end
        str = string.sub(str, 1, string.len(str) - 3) -- shave ,\n off of the last element
        return (str .. "\n}")
    else
        return tostring(tbl) -- fallback if you call function on non-table
    end
end

local function autoplaceExpressionToString(expression)   -- tostring() for autoplace expressions
    local recurse = autoplaceExpressionToString
    local form = {
        ["variable"] = function(expression)
            return expression.variable_name
        end,
        ["literal-boolean"] = function(expression)
            return expression.literal_value
        end,
        ["literal-number"] = function(expression)
            return expression.literal_value
        end,
        ["literal-string"] = function(expression)
            return expression.literal_value
        end,
        ["literal-object"] = function(expression)
            return tableToString(expression.literal_value)
        end,
        ["literal-expression"] = function(expression)
            return recurse(expression.literal_value)
        end,
        ["array-construction"] = function(expression)
            return tableToString(expression.value_expressions, nil, recurse)
        end,
        ["procedure-delimiter"] = function(expression)
            return "evaluate(" .. recurse(expression.expression) .. ")"
        end,
        ["if-else-chain"] = function(expression)
            local str = "{\n"
            for i, argument in pairs(expression.arguments) do
                str = str .. recurse(argument)
                if i == #expression.arguments then
                    return (str .. "\n}")
                elseif i % 2 == 1 then
                    str = str .. ": "
                else
                    str = str .. ",\n"
                end
            end
        end,
        ["function-application"] = function(expression)
            local gsubArguments = {}
            local indices = {}
            for i, argument in pairs(expression.arguments) do
                gsubArguments["%" .. i .. "%"] = recurse(argument)
                indices[i] = "%" .. i .. "%"
            end
            local fmt = {}
            do
                fmt.add = table.concat(indices, " + ") -- variable argument count
                fmt.subtract = "%1% - %2%"
                fmt.multiply = table.concat(indices, " * ")
                fmt.divide = "%1% / %2%"
                fmt.exponentiate = "pow(%1%, %2%)"
                fmt["absolute-value"] = "|%1%|"
                fmt.clamp = "clamp(%1%, %2%, %3%)"
                fmt["compile-time-log"] = indices[#indices] -- last argument; all others are effectively comments
                fmt.ridge = "ridge(%1%, %2%, %3%)"
                fmt.terrace = "terrace(%1%, %2%, %3%, %4%)"
                fmt.modulo = "%1% % %2%"
                fmt.floor = "floor(%1%)"
                fmt.ceil = "ceil(%1%)"
                fmt["bitwise-and"] = table.concat(indices, " & ")
                fmt["bitwise-or"] = table.concat(indices, " | ")
                fmt["bitwise-xor"] = table.concat(indices, " ^ ")
                fmt["bitwise-not"] = "~%1%"
                fmt.sin = "sin(%1%)"
                fmt.cos = "cos(%1%)"
                fmt.atan2 = "atan2(%1%, %2%)"
                fmt["less-than"] = "%1% < %2%"
                fmt["less-or-equal"] = "%1% <= %2%"
                fmt.equals = "%1% == %2%"
                fmt.log2 = "log2(%1%)"
                fmt["noise-layer-name-to-id"] = "noise-id(%1%)"
                fmt["autoplace-probability"] = "autoplace-probability(%1%)"
                fmt["autoplace-richness"] = "autoplace-richness(%1%)"
                fmt["offset-points"] = "offset(%1%, %2%)"
            end
            local needsParentheses = {}
            do --setup
                needsParentheses.add = true
                needsParentheses.subtract = true
                needsParentheses.multiply = true
                needsParentheses.divide = true
                needsParentheses.exponentiate = true
                needsParentheses.modulo = true
                needsParentheses["bitwise-and"] = true
                needsParentheses["bitwise-or"] = true
                needsParentheses["bitwise-xor"] = true
                needsParentheses["bitwise-not"] = true
                needsParentheses["less-than"] = true
                needsParentheses["less-or-equal"] = true
                needsParentheses.equals = true
            end
            local str
            if fmt[expression.function_name] then
                str = string.gsub(fmt[expression.function_name], "%%%d+%%", gsubArguments)
            else
                str = expression.function_name .. tableToString(expression.arguments, recurse, recurse, ": ")
            end
            if needsParentheses[expression.function_name] then
                str = "(" .. str .. ")"
            end
            return str
        end
    }
    return (form[expression.type] or tableToString)(expression) -- fallback if you call function on non-autoplace expression
end
