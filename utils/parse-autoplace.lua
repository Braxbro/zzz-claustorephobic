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

-- ─── Noise expression tokeniser / parser ─────────────────────────────────────
--
-- Single-pass tokeniser: at each position, all value patterns are tried and the
-- one with the smallest start position wins (ties resolved by recognition order).
-- Characters in the gap before the winning match are emitted as operator tokens
-- (two-char operators recognised first; whitespace silently dropped).
-- Function-call interiors are tokenised recursively so nested commas are already
-- hidden inside call tokens when the argument list is later split.
--
-- Token types emitted by tokenise():
--   {type="number",          value=<number>}
--   {type="string",          value=<string>}   -- content including surrounding quotes
--   {type="ident",           name=<string>}
--   {type="call_positional", name=<string>, args_tokens=<list>}
--   {type="call_named",      name=<string>, args_tokens=<list>}
--   {type="group",           tokens=<list>}    -- bare parenthesised sub-expression
--   {type="op",              value=<string>}   -- single- or two-char operator

local tokenise  -- forward declaration (call-token handlers reference it recursively)

local TWO_CHAR_OPS = {
  ["=="] = true, ["~="] = true, ["!="] = true,
  ["<="] = true, [">="] = true, ["%%"] = true,
}

local function emit_gap_ops(tokens, text)
  local i = 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      i = i + 1
    elseif TWO_CHAR_OPS[text:sub(i, i + 1)] then
      tokens[#tokens + 1] = {type = "op", value = text:sub(i, i + 1)}
      i = i + 2
    else
      tokens[#tokens + 1] = {type = "op", value = c}
      i = i + 1
    end
  end
end

-- Each entry: {pattern_string, make_token_fn(capture1, capture2)}.
-- Listed most-specific first: ties on start position go to the earlier entry.
local VALUE_PATTERNS = {
  {'(%b"")',                           function(m)    return {type = "string",          value = m} end},
  {"(%b'')",                           function(m)    return {type = "string",          value = m} end},
  {"([a-zA-Z_][a-zA-Z0-9_:]*)(%b{})",  function(n, b) return {type = "call_named",      name = n, args_tokens = tokenise(b:sub(2, -2))} end},
  -- var('name') / var("name") is syntactic sugar for a named identifier reference.
  -- Recognised at lex time so the token stream contains a plain ident, not a call.
  {"var(%b())", function(a)
    local interior = a:sub(2, -2):match("^%s*(.-)%s*$")
    local name = interior:match("^'(.*)'$") or interior:match('^"(.*)"$')
    if name then return {type = "ident", name = name} end
    -- Malformed var() — fall back to a regular positional call.
    return {type = "call_positional", name = "var", args_tokens = tokenise(interior)}
  end},
  {"([a-zA-Z_][a-zA-Z0-9_:]*)(%b())",  function(n, a) return {type = "call_positional", name = n, args_tokens = tokenise(a:sub(2, -2))} end},
  {"(%b())",                           function(m)    return {type = "group",           tokens    = tokenise(m:sub(2, -2))} end},
  {"([a-zA-Z_][a-zA-Z0-9_:]*)",        function(n)    return {type = "ident",           name = n} end},
  {"(0x[0-9a-fA-F]+)",                 function(m)    return {type = "number",          value = m} end},
  {"([0-9]*%.?[0-9]+e[-+]?[0-9]+)",    function(m)    return {type = "number",          value = m} end},
  {"([0-9]*%.?[0-9]+)",                function(m)    return {type = "number",          value = m} end},
}

tokenise = function(expr)
  local tokens = {}
  local pos    = 1
  local len    = #expr

  while pos <= len do
    local best_start, best_end, best_tok = nil, nil, nil

    for _, p in ipairs(VALUE_PATTERNS) do
      local s, e, c1, c2 = expr:find(p[1], pos)
      if s and (not best_start or s < best_start) then
        best_start, best_end, best_tok = s, e, p[2](c1, c2)
      end
      if best_start == pos then break end
    end

    -- Characters before the earliest token are operators (or whitespace).
    local gap_end = best_start and (best_start - 1) or len
    if gap_end >= pos then
      emit_gap_ops(tokens, expr:sub(pos, gap_end))
    end

    if not best_start then break end

    tokens[#tokens + 1] = best_tok
    pos = best_end + 1
  end

  return tokens
end

-- ─── AST builder ─────────────────────────────────────────────────────────────
--
-- Pratt / precedence-climbing parser operating directly on a token list.

local PREC = {
  ["|"]  = {1, false},
  ["~"]  = {2, false},
  ["&"]  = {3, false},
  ["=="] = {4, false}, ["~="] = {4, false}, ["!="] = {4, false},
  ["<"]  = {5, false}, ["<="] = {5, false}, [">"] = {5, false}, [">="] = {5, false},
  ["+"]  = {6, false}, ["-"]  = {6, false},
  ["*"]  = {7, false}, ["/"]  = {7, false}, ["%"] = {7, false}, ["%%"] = {7, false},
  ["^"]  = {9, true},
}
local UNARY_PREC = 8

-- Split a flat token list on comma op tokens.
-- Returns a list of token-list segments (empty segments omitted).
local function split_on_commas(tokens)
  local segs, cur = {}, {}
  for _, tok in ipairs(tokens) do
    if tok.type == "op" and tok.value == "," then
      if #cur > 0 then segs[#segs + 1] = cur end
      cur = {}
    else
      cur[#cur + 1] = tok
    end
  end
  if #cur > 0 then segs[#segs + 1] = cur end
  return segs
end

local _build_ast  -- forward declaration

local function parse_primary(tokens, pos)
  local tok = tokens[pos]
  if not tok then return nil, pos end
  local npos = pos + 1

  -- Bare parenthesised sub-expression (tokenised as a group token by the lexer)
  if tok.type == "group" then
    return _build_ast(tok.tokens, 0, 1), npos
  end

  -- Unary prefix operators
  if tok.type == "op" and (tok.value == "-" or tok.value == "+" or tok.value == "~") then
    local operand, p2 = _build_ast(tokens, UNARY_PREC, npos)
    return {type = "unop", op = tok.value, operand = operand}, p2
  end

  -- Literals
  if tok.type == "number" or tok.type == "string" then
    return tok, npos
  end

  -- Plain identifier
  if tok.type == "ident" then
    return tok, npos
  end

  -- Positional call
  if tok.type == "call_positional" then
    local segs = split_on_commas(tok.args_tokens)
    local args = {}
    for _, seg in ipairs(segs) do
      args[#args + 1] = _build_ast(seg, 0, 1)
    end
    return {type = "call_positional", name = tok.name, args = args}, npos
  end

  -- Named call
  if tok.type == "call_named" then
    local segs = split_on_commas(tok.args_tokens)
    local args = {}
    for _, seg in ipairs(segs) do
      -- Key is always a single ident token; = op is at index 2.
      local eq_idx
      for i, t in ipairs(seg) do
        if t.type == "op" and t.value == "=" then eq_idx = i; break end
      end
      if eq_idx and eq_idx == 2 and seg[1].type == "ident" then
        local val_toks = {}
        for i = eq_idx + 1, #seg do val_toks[#val_toks + 1] = seg[i] end
        local val_node = _build_ast(val_toks, 0, 1)
        if val_node then
          args[#args + 1] = {key = seg[1].name, val = val_node}
        end
      end
    end
    return {type = "call_named", name = tok.name, args = args}, npos
  end

  error("unexpected token in AST: type=" .. tostring(tok.type) .. " value=" .. tostring(tok.value or tok.name))
end

_build_ast = function(tokens, min_prec, pos)
  pos      = pos      or 1
  min_prec = min_prec or 0

  local left, p = parse_primary(tokens, pos)
  if not left then return nil, pos end

  while true do
    local tok = tokens[p]
    if not tok or tok.type ~= "op" then break end
    local pe = PREC[tok.value]
    if not pe then break end
    local prec, right_assoc = pe[1], pe[2]
    if prec <= min_prec then break end
    local rhs, p2 = _build_ast(tokens, right_assoc and prec - 1 or prec, p + 1)
    if not rhs then break end
    left = {type = "binop", op = tok.value, left = left, right = rhs}
    p = p2
  end

  return left, p
end

-- Public entry point: parse a noise expression string into an AST node.
local function parse(expr)
  local tokens = tokenise(expr)
  local node   = _build_ast(tokens, 0, 1)
  return node
end

-- ─── Serialiser ──────────────────────────────────────────────────────────────

local BARE_IDENT = "^[a-zA-Z_][a-zA-Z0-9_:]*$"

local function serialize(node)
  if node.type == "number" then
    local v = node.value
    if type(v) == "string" then return v end
    if v == math.floor(v) and math.abs(v) < 1e15 then
      return string.format("%d", v)
    else
      return string.format("%.14g", v)
    end
  elseif node.type == "string" then
    return node.value  -- stored with original quotes intact
  elseif node.type == "ident" then
    if node.name:match(BARE_IDENT) then
      return node.name
    elseif node.name:find("'") then
      assert(not node.name:find('"'), "ident name contains both quote types and is unreachable: " .. node.name)
      return 'var("' .. node.name .. '")'
    else
      return "var('" .. node.name .. "')"
    end
  elseif node.type == "unop" then
    return node.op .. serialize(node.operand)
  elseif node.type == "binop" then
    return "(" .. serialize(node.left) .. " " .. node.op .. " " .. serialize(node.right) .. ")"
  elseif node.type == "call_positional" then
    local parts = {}
    for _, arg in ipairs(node.args) do parts[#parts + 1] = serialize(arg) end
    return node.name .. "(" .. table.concat(parts, ", ") .. ")"
  elseif node.type == "call_named" then
    local parts = {}
    for _, pair in ipairs(node.args) do
      parts[#parts + 1] = pair.key .. " = " .. serialize(pair.val)
    end
    return node.name .. "{" .. table.concat(parts, ", ") .. "}"
  else
    error("unknown node type: " .. tostring(node.type))
  end
end

-- ─── AST utilities ───────────────────────────────────────────────────────────

-- Returns true if name refers to a verified no-op noise-function:
-- exactly one parameter and expression equal to that parameter name.
local function is_noop_fn(name)
  if not (data and data.raw and data.raw["noise-function"]) then return false end
  local nf = data.raw["noise-function"][name]
  if not nf or not nf.parameters or #nf.parameters ~= 1 then return false end
  if type(nf.expression) ~= "string" then return false end
  return nf.expression:match("^%s*" .. nf.parameters[1] .. "%s*$") ~= nil
end

-- Walk an AST looking for the first call (named or positional) with the given function name.
-- stop_fn: optional function name; subtrees rooted at a call to stop_fn are not searched.
-- stop_fn must be a verified no-op noise-function (single parameter, expression == parameter name).
local function find_call(node, name, stop_fn)
  local recurse = find_call
  if stop_fn and data and data.raw then
    assert(is_noop_fn(stop_fn), "find_call: stop_fn '" .. stop_fn .. "' is not a verified no-op noise-function")
  end
  if not node or type(node) ~= "table" then return nil end
  if (node.type == "call_named" or node.type == "call_positional") and node.name == name then
    return node
  end
  if stop_fn and (node.type == "call_named" or node.type == "call_positional") and node.name == stop_fn then
    return nil
  end
  if node.type == "binop" then
    return recurse(node.left, name, stop_fn) or recurse(node.right, name, stop_fn)
  elseif node.type == "unop" then
    return recurse(node.operand, name, stop_fn)
  elseif node.type == "call_positional" then
    for _, arg in ipairs(node.args) do
      local r = recurse(arg, name, stop_fn)
      if r then return r end
    end
  elseif node.type == "call_named" then
    for _, pair in ipairs(node.args) do
      local r = recurse(pair.val, name, stop_fn)
      if r then return r end
    end
  end
  return nil
end

-- Walk an AST collecting all calls with the given function name into a list.
-- stop_fn: optional function name; subtrees rooted at a call to stop_fn are not searched.
-- stop_fn must be a verified no-op noise-function (single parameter, expression == parameter name).
local function find_all_calls(node, name, stop_fn, out)
  local recurse = find_all_calls
  if stop_fn and data and data.raw then
    assert(is_noop_fn(stop_fn), "find_all_calls: stop_fn '" .. stop_fn .. "' is not a verified no-op noise-function")
  end
  out = out or {}
  if not node or type(node) ~= "table" then return out end
  if (node.type == "call_named" or node.type == "call_positional") and node.name == name then
    out[#out + 1] = node
  end
  if stop_fn and (node.type == "call_named" or node.type == "call_positional") and node.name == stop_fn then
    return out
  end
  if node.type == "binop" then
    recurse(node.left, name, stop_fn, out)
    recurse(node.right, name, stop_fn, out)
  elseif node.type == "unop" then
    recurse(node.operand, name, stop_fn, out)
  elseif node.type == "call_positional" then
    for _, arg in ipairs(node.args) do
      recurse(arg, name, stop_fn, out)
    end
  elseif node.type == "call_named" then
    for _, pair in ipairs(node.args) do
      recurse(pair.val, name, stop_fn, out)
    end
  end
  return out
end

-- Like find_all_calls but also searches inside stop_fn calls and flags them.
-- Returns list of {call, ignored=bool} where ignored is true if inside stop_fn.
local function find_all_calls_including_ignored(node, name, stop_fn)
  local recurse
  if stop_fn and data and data.raw then
    assert(is_noop_fn(stop_fn), "find_all_calls_including_ignored: stop_fn '" .. stop_fn .. "' is not a verified no-op noise-function")
  end
  local out = {}

  recurse = function(n, inside_stop_fn)
    if not n or type(n) ~= "table" then return end
    if n.type == "call_named" or n.type == "call_positional" then
      if n.name == name then
        out[#out + 1] = { call = n, ignored = inside_stop_fn }
      end
      local is_stop_fn = stop_fn and n.name == stop_fn
      local next_inside = inside_stop_fn or is_stop_fn
      for _, arg in ipairs(n.args) do
        if n.type == "call_named" then
          recurse(arg.val, next_inside)
        else
          recurse(arg, next_inside)
        end
      end
    elseif n.type == "binop" then
      recurse(n.left, inside_stop_fn)
      recurse(n.right, inside_stop_fn)
    elseif n.type == "unop" then
      recurse(n.operand, inside_stop_fn)
    elseif n.type == "group" then
      for _, t in ipairs(n.tokens) do
        recurse(t, inside_stop_fn)
      end
    end
  end

  recurse(node, false)
  return out
end

-- Get the AST node for a named arg by key string.
local function get_named_arg(call_node, key)
  for _, pair in ipairs(call_node.args) do
    if pair.key == key then return pair.val end
  end
  return nil
end

-- Signatures for built-in noise primitives (not defined in data.raw["noise-function"]).
local BUILTIN_SIGNATURES = {
  clamp         = {"value", "lower_bound", "upper_bound"},
  max           = {"a", "b"},
  min           = {"a", "b"},
  abs           = {"value"},
  sqrt          = {"value"},
  log2          = {"value"},
  cos           = {"value"},
  sin           = {"value"},
  atan2         = {"y", "x"},
  ["if"]        = {"condition", "when_true", "when_false"},
  floor         = {"value"},
  ceil          = {"value"},
  ridge         = {"value", "min", "max"},
  less_than     = {"a", "b"},
  less_or_equal = {"a", "b"},
  equals        = {"a", "b"},
}

-- Return the ordered parameter list for a noise function name.
-- Checks data.raw["noise-function"] first (covers all mod-defined functions),
-- then falls back to BUILTIN_SIGNATURES for engine primitives.
local function resolve_signature(name)
  if data and data.raw and data.raw["noise-function"] then
    local nf = data.raw["noise-function"][name]
    if nf and nf.parameters then return nf.parameters end
  end
  return BUILTIN_SIGNATURES[name]
end

-- Get the AST node for a positional arg by parameter name.
-- Returns nil if the function signature is unknown or the parameter is not found.
local function get_positional_arg(call_node, name)
  local sig = resolve_signature(call_node.name)
  if not sig then return nil end
  for i, param in ipairs(sig) do
    if param == name then return call_node.args[i] end
  end
  return nil
end

-- Evaluate a constant numeric expression.  Returns a number or nil.
local function eval_const(node)
  if not node then return nil end
  if node.type == "number" then return tonumber(node.value) end
  if node.type == "unop" then
    local v = eval_const(node.operand)
    if node.op == "-" then return v and -v end
    if node.op == "+" then return v end
  end
  if node.type == "binop" then
    local l, r = eval_const(node.left), eval_const(node.right)
    if l and r then
      if node.op == "+"  then return l + r end
      if node.op == "-"  then return l - r end
      if node.op == "*"  then return l * r end
      if node.op == "/"  then return r ~= 0 and l / r or nil end
      if node.op == "^"  then return l ^ r end
      if node.op == "%"  then return l % r end
      if node.op == "%%" then return l % r end
    end
  end
  return nil
end

-- Walk an AST for the first ident node whose name matches a Lua pattern.
-- stop_fn: optional function name; subtrees rooted at a call to stop_fn are not searched.
-- stop_fn must be a verified no-op noise-function (single parameter, expression == parameter name).
local function find_ident(node, pattern, stop_fn)
  if not node or type(node) ~= "table" then return nil end
  if stop_fn and (node.type == "call_named" or node.type == "call_positional") and node.name == stop_fn then
    return nil
  end
  if node.type == "ident" and node.name:match(pattern) then return node end
  if node.type == "binop" then
    return find_ident(node.left, pattern, stop_fn) or find_ident(node.right, pattern, stop_fn)
  elseif node.type == "unop" then
    return find_ident(node.operand, pattern, stop_fn)
  elseif node.type == "call_positional" then
    for _, arg in ipairs(node.args) do
      local r = find_ident(arg, pattern, stop_fn)
      if r then return r end
    end
  elseif node.type == "call_named" then
    for _, pair in ipairs(node.args) do
      local r = find_ident(pair.val, pattern, stop_fn)
      if r then return r end
    end
  end
  return nil
end

-- Walk an AST collecting all ident nodes whose names match a Lua pattern.
-- stop_fn: optional function name; subtrees rooted at a call to stop_fn are not searched.
-- stop_fn must be a verified no-op noise-function (single parameter, expression == parameter name).
local function find_all_idents(node, pattern, out, stop_fn)
  out = out or {}
  if not node or type(node) ~= "table" then return out end
  if stop_fn and (node.type == "call_named" or node.type == "call_positional") and node.name == stop_fn then
    return out
  end
  if node.type == "ident" and node.name:match(pattern) then
    out[#out + 1] = node
  end
  if node.type == "binop" then
    find_all_idents(node.left, pattern, out, stop_fn)
    find_all_idents(node.right, pattern, out, stop_fn)
  elseif node.type == "unop" then
    find_all_idents(node.operand, pattern, out, stop_fn)
  elseif node.type == "call_positional" then
    for _, arg in ipairs(node.args) do find_all_idents(arg, pattern, out, stop_fn) end
  elseif node.type == "call_named" then
    for _, pair in ipairs(node.args) do find_all_idents(pair.val, pattern, out, stop_fn) end
  end
  return out
end

-- Flatten a left-associative * tree into a list of factor nodes.
local function collect_mul_factors(node, out)
  out = out or {}
  if node and node.type == "binop" and node.op == "*" then
    collect_mul_factors(node.left, out)
    collect_mul_factors(node.right, out)
  elseif node then
    out[#out + 1] = node
  end
  return out
end

-- ─── Parameter extraction ─────────────────────────────────────────────────────

-- Extract call-level params from a single resource_autoplace_all_patches call node.
-- patches_name: the *-patches NE name, or nil for inline calls.
-- rich_ast:     parsed richness AST, or nil if parse failed.
-- Does NOT set control_name — caller sets that (it is an ore-level field).
local function extract_one_call_params(call, patches_name, rich_ast)
  local result = {
    patches_name                       = patches_name,
    base_density                       = "unfound",
    has_starting_area_placement        = nil,
    seed1                              = 100,
    regular_patch_set_index            = 0,
    regular_patch_set_count            = 1,
    starting_patch_set_index           = 0,
    starting_patch_set_count           = 1,
    base_spots_per_km2                 = 2.5,
    random_spot_size_minimum           = 0.25,
    random_spot_size_maximum           = 2,
    regular_blob_amplitude_multiplier  = 1,
    starting_blob_amplitude_multiplier = 1,
    regular_rq_factor_multiplier       = 1,
    starting_rq_factor_multiplier      = 1,
    random_probability                 = 1,
    additional_richness                = 0,
    minimum_richness                   = 0,
    richness_post_multiplier           = 1,
  }

  -- Unified arg accessor: named args for call_named, positional lookup for call_positional.
  local function get_arg(key)
    if call.type == "call_named" then
      return get_named_arg(call, key)
    else
      return get_positional_arg(call, key)
    end
  end

  -- Helper: get an arg as a constant, with optional unmangling multiplier.
  local function get_num(key, factor)
    local node = get_arg(key)
    local v = node and eval_const(node)
    if v and factor then v = v * factor end
    return v
  end

  -- Helper: patch_set_count args are bare ident names pointing to a
  -- noise-expression whose .expression field holds the integer count.
  local function get_patch_count(key)
    local node = get_arg(key)
    if not node or node.type ~= "ident" then return nil end
    local ne = data.raw["noise-expression"] and data.raw["noise-expression"][node.name]
    if not ne then return nil end
    local expr = ne.expression
    if type(expr) == "number" then return expr end
    if type(expr) == "string" then return tonumber(expr) end
    return nil
  end

  -- resource-autoplace.lua stores blob amplitudes /8, rq_factors /10 and /7.
  result.base_density                        = get_num("base_density")                       or "unfound"
  result.base_spots_per_km2                  = get_num("base_spots_per_km2")                 or 2.5
  result.random_spot_size_minimum            = get_num("random_spot_size_minimum")           or 0.25
  result.random_spot_size_maximum            = get_num("random_spot_size_maximum")           or 2
  result.regular_blob_amplitude_multiplier   = get_num("regular_blob_amplitude_multiplier",  8) or 1
  result.starting_blob_amplitude_multiplier  = get_num("starting_blob_amplitude_multiplier", 8) or 1
  result.regular_rq_factor_multiplier        = get_num("regular_rq_factor",  10)             or 1
  result.starting_rq_factor_multiplier       = get_num("starting_rq_factor",  7)             or 1
  result.seed1                               = get_num("seed1")                              or 100
  result.regular_patch_set_index             = get_num("regular_patch_set_index")            or 0
  result.starting_patch_set_index            = get_num("starting_patch_set_index")           or 0
  result.regular_patch_set_count             = get_patch_count("regular_patch_set_count")    or 1
  result.starting_patch_set_count            = get_patch_count("starting_patch_set_count")   or 1

  -- has_starting_area_placement: -1 → nil (no concept), 0 → false, 1 → true
  local hsap = get_num("has_starting_area_placement")
  if     hsap == 1 then result.has_starting_area_placement = true
  elseif hsap == 0 then result.has_starting_area_placement = false
  end

  -- ── Richness params (from richness_expression) ────────────────────────────
  if rich_ast then
    local factors = collect_mul_factors(rich_ast)

    -- RPM: the factor that evaluates to a constant.
    for _, f in ipairs(factors) do
      local v = eval_const(f)
      if v then result.richness_post_multiplier = v ; break end
    end

    -- INNER: the factor containing this call's patches ident.
    local inner = nil
    if patches_name then
      local pat_escaped = patches_name:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
      for _, f in ipairs(factors) do
        if find_ident(f, "^" .. pat_escaped .. "$") then inner = f ; break end
      end
    end

    if inner then
      -- Peel max(INNER, min_richness)
      if inner.type == "call_positional" and inner.name == "max" and #inner.args == 2 then
        local min_v = eval_const(inner.args[2])
        if min_v then result.minimum_richness = min_v end
        inner = inner.args[1]
      end
      -- Peel + additional_richness
      if inner.type == "binop" and inner.op == "+" then
        local ar = eval_const(inner.right)
        if ar then result.additional_richness = ar end
        inner = inner.left
      end
      -- Peel / random_probability
      if inner.type == "binop" and inner.op == "/" then
        local rp = eval_const(inner.right)
        if rp then result.random_probability = rp end
      end
    end
  end

  return result, serialize(call)
end

local function extract_autoplace_params(autoplace, stop_fn)
  -- Default result for early-exit paths (parse failure, no call found).
  local result = {
    patches_name                       = nil,
    base_density                       = "unfound",
    control_name                       = "unfound",
    has_starting_area_placement        = nil,
    seed1                              = 100,
    regular_patch_set_index            = 0,
    regular_patch_set_count            = 1,
    starting_patch_set_index           = 0,
    starting_patch_set_count           = 1,
    base_spots_per_km2                 = 2.5,
    random_spot_size_minimum           = 0.25,
    random_spot_size_maximum           = 2,
    regular_blob_amplitude_multiplier  = 1,
    starting_blob_amplitude_multiplier = 1,
    regular_rq_factor_multiplier       = 1,
    starting_rq_factor_multiplier      = 1,
    random_probability                 = 1,
    additional_richness                = 0,
    minimum_richness                   = 0,
    richness_post_multiplier           = 1,
  }

  local prob_str = autoplace.probability_expression
  local rich_str = autoplace.richness_expression
  if type(prob_str) ~= "string" or type(rich_str) ~= "string" then return result end

  local ok, prob_ast = pcall(parse, prob_str)
  if not ok then return result end

  -- ── Patches expression name and control name ──────────────────────────────
  local patches_ident = find_ident(prob_ast, "%-patches$", stop_fn)
  if not patches_ident then
    local ok2, rich_ast_fb = pcall(parse, rich_str)
    if ok2 then patches_ident = find_ident(rich_ast_fb, "%-patches$", stop_fn) end
  end

  local size_ident = find_ident(prob_ast, "^control:.*:size$", stop_fn)
  if size_ident then
    result.control_name = size_ident.name:match("^control:(.*):size$")
  end

  -- ── Find the resource_autoplace_all_patches call ──────────────────────────
  local patches_name
  local call
  if patches_ident then
    patches_name = patches_ident.name
    result.patches_name = patches_name
    local patches_ne = data.raw["noise-expression"] and data.raw["noise-expression"][patches_name]
    if patches_ne and type(patches_ne.expression) == "string" then
      local ok3, patches_ast = pcall(parse, patches_ne.expression)
      if ok3 then call = find_call(patches_ast, "resource_autoplace_all_patches", stop_fn) end
    end
  else
    call = find_call(prob_ast, "resource_autoplace_all_patches", stop_fn)
  end
  if not call then return result end

  local ok4, rich_ast = pcall(parse, rich_str)
  local call_result = extract_one_call_params(call, patches_name, ok4 and rich_ast or nil)
  call_result.control_name = result.control_name
  return call_result
end

-- ─── Public API ──────────────────────────────────────────────────────────────

local function find_autoplace_argument(argument, autoplace)
  local params = extract_autoplace_params(autoplace)
  if argument == "all" then
    return params
  elseif params[argument] ~= nil then
    return params[argument]
  else
    error("Attempt to find invalid autoplace argument " .. tostring(argument))
  end
end

-- Return a list of per-call params tables for every resource_autoplace_all_patches
-- call found in the autoplace expression.  Includes calls whose weight params are
-- unfound — callers must check result[i].base_density ~= "unfound" for eligibility.
-- control_name is set on every entry (ore-level; identical across all calls).
local function find_all_autoplace_arguments(autoplace, stop_fn)
  local results = {}
  local expressions = {}
  local prob_str = autoplace.probability_expression
  local rich_str = autoplace.richness_expression
  if type(prob_str) ~= "string" or type(rich_str) ~= "string" then return results, expressions end

  local ok, prob_ast = pcall(parse, prob_str)
  if not ok then return results, expressions end

  local ok_r, rich_ast = pcall(parse, rich_str)
  local parsed_rich = ok_r and rich_ast or nil

  -- Ore-level: control name from probability expression.
  local control_name = "unfound"
  local size_ident = find_ident(prob_ast, "^control:.*:size$", stop_fn)
  if size_ident then
    control_name = size_ident.name:match("^control:(.*):size$")
  end

  -- Collect all unique *-patches ident names from prob_ast, then rich_ast fallback.
  local all_patch_idents = find_all_idents(prob_ast, "%-patches$", nil, stop_fn)
  if #all_patch_idents == 0 and parsed_rich then
    all_patch_idents = find_all_idents(parsed_rich, "%-patches$", nil, stop_fn)
  end

  local seen = {}
  for _, ident in ipairs(all_patch_idents) do
    local patches_name = ident.name
    if not seen[patches_name] then
      seen[patches_name] = true
      local patches_ne = data.raw["noise-expression"] and data.raw["noise-expression"][patches_name]
      if patches_ne and type(patches_ne.expression) == "string" then
        local ok3, patches_ast = pcall(parse, patches_ne.expression)
        if ok3 then
          local calls_with_ignored = find_all_calls_including_ignored(patches_ast, "resource_autoplace_all_patches", stop_fn)
          for _, item in ipairs(calls_with_ignored) do
            local r, expr = extract_one_call_params(item.call, patches_name, parsed_rich)
            r.control_name = control_name
            r.ignored = item.ignored
            results[#results + 1] = r
            expressions[#expressions + 1] = expr
          end
        end
      end
    end
  end

  -- Inline fallback: no *-patches NE found; call lives directly in probability_expression.
  if #results == 0 then
    local calls_with_ignored = find_all_calls_including_ignored(prob_ast, "resource_autoplace_all_patches", stop_fn)
    for _, item in ipairs(calls_with_ignored) do
      local r, expr = extract_one_call_params(item.call, nil, parsed_rich)
      r.control_name = control_name
      r.ignored = item.ignored
      results[#results + 1] = r
      expressions[#expressions + 1] = expr
    end
  end

  return results, expressions
end

local util_functions = {}
util_functions.match                              = match
util_functions.search_table                       = search_table
util_functions.find_autoplace_argument            = find_autoplace_argument
util_functions.find_all_autoplace_arguments       = find_all_autoplace_arguments
util_functions.find_all_calls_including_ignored   = find_all_calls_including_ignored
util_functions.parse                             = parse
util_functions.serialize                         = serialize
util_functions.eval_const                        = eval_const
util_functions.tokenise                          = tokenise
util_functions.is_noop_fn              = is_noop_fn
util_functions.find_call               = find_call
util_functions.find_all_calls          = find_all_calls
util_functions.find_all_idents         = find_all_idents
util_functions.get_named_arg           = get_named_arg
util_functions.get_positional_arg      = get_positional_arg
util_functions.resolve_signature       = resolve_signature
return util_functions
