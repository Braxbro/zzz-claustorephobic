local integrations = {["exotic-industries"] = "integrations.control.exotic-industries"} -- explicit mod integration scripts. If the mod is present, the path will be replaced with the script's output; otherwise, it will be deleted.
for mod, path in pairs(integrations) do
	if script.active_mods[mod] then
		integrations[mod] = require(path)
	else
		integrations[mod] = nil
	end
end

script.on_event(defines.events.on_built_entity, function(eventdata)
    for mod, integration in pairs(integrations) do -- Try to find out which integration this should be handled by.
        if integration.on_built_entity then
            if integration.on_built_entity(eventdata) then
                return
            end
        end
    end
end, nil)