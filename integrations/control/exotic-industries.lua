local output = {}
local ei_gate_handler = require("__exotic-industries__/scripts/control/gate.lua")

output.on_built_entity = function(eventdata)
    if eventdata.created_entity.name == "ClaustOrephobic-ei_gate" then -- gate bug bypass
        local entitydata = {
            name = "ei_gate",
            position = eventdata.created_entity.position,
            direction = eventdata.created_entity.direction,
            force = eventdata.created_entity.force,
            item = eventdata.stack,
            raise_built = true
        }
        local surface = eventdata.created_entity.surface
        eventdata.created_entity.destroy()
        local entity = surface.create_entity(entitydata)
        return true -- event was acted upon
    end
    return false -- event was not acted upon
end

return output