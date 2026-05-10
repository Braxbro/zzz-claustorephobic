
local controls = {
    { name = "claustorephobic-clearings" }
  , { name = "claustorephobic-resource-multiplier", richness = true, can_be_disabled = false }
}

local entries = {}
for _, ctrl in ipairs(controls) do
    entries[#entries + 1] = {
        type            = "autoplace-control"
      , name            = ctrl.name
      , order           = "a"
      , category        = "resource"
      , richness        = ctrl.richness
      , can_be_disabled = ctrl.can_be_disabled
    }
end
data:extend(entries)

for _, ctrl in ipairs(controls) do
    data.raw.planet.nauvis.map_gen_settings.autoplace_controls[ctrl.name] = {}
end
