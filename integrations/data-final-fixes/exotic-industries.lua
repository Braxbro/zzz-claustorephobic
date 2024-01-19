local output = {}

local dummygate = table.deepcopy(data.raw["electric-energy-interface"]["ei_gate"]) -- copy the actual entity

dummygate.type = "simple-entity-with-owner"
dummygate.name = "ClaustOrephobic-ei_gate"
dummygate.localised_name = {"entity-name.ei_gate"}

data:extend({
    dummygate
})

local item = data.raw.item["ei_gate"]
item.place_result = dummygate.name

table.insert(ClaustOrephobic.allowed_entity_names, "ei_gate")

return output