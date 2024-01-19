ClaustOrephobic = type(ClaustOrephobic) == "table" and ClaustOrephobic or {} -- in case someone comes before me and wants to use my interface, I'll just run basic format checks here.

--[[
    The proper format is as follows:
    ClaustOrephobic = {
        "allowed_subgroups" = {},
        "allowed_types" = {},
        "allowed_entity_names" = {}
    }
    with the contents of each of the three tables being subgroup, type, or entity name strings respectively.

    If you wish to use this global in data.lua, before my mod loads, fear not. If you create this global table early, my mod will recognize that and keep any valid changes you've made to it.
]]

if type(ClaustOrephobic.allowed_subgroups) == "table" then -- Entity subgroups that should not be altered.
    table.insert(ClaustOrephobic.allowed_subgroups, "enemies")
else
    ClaustOrephobic.allowed_subgroups = {"enemies"}
end
ClaustOrephobic.allowed_types = type(ClaustOrephobic.allowed_types) == "table" and ClaustOrephobic.allowed_types or {} -- Entity types that should not be altered.
ClaustOrephobic.allowed_entity_names = type(ClaustOrephobic.allowed_entity_names) == "table" and ClaustOrephobic.allowed_entity_names or {} -- Entity names that should not be altered.

for index, value in pairs(ClaustOrephobic.allowed_subgroups) do
    if type(value) ~= "string" then
        ClaustOrephobic.allowed_subgroups[index] = nil -- delete invalid entry
    end
end
for index, value in pairs(ClaustOrephobic.allowed_types) do
    if type(value) ~= "string" then
        ClaustOrephobic.allowed_types[index] = nil -- delete invalid entry
    end
end
for index, value in pairs(ClaustOrephobic.allowed_entity_names) do
    if type(value) ~= "string" then
        ClaustOrephobic.allowed_entity_names[index] = nil -- delete invalid entry
    end
end