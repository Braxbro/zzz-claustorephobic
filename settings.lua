data:extend({
	-- worldgen settings
	{
		type = "string-setting",
		name = "claustorephobic-ore-generation-mode",
		setting_type = "startup",
		default_value = "scrambled",
		allowed_values = {"scrambled","noise","pie","spiral"},
		order = "01"
	},
	{
		type = "int-setting",
		name = "claustorephobic-starting-radius",
		setting_type = "startup",
        default_value = 120,
        minimum_value = 0,
        maximum_value = 300,
        order = "02"
	},
	{
		type = "string-setting",
		name = "claustorephobic-starting-area-shape",
		setting_type = "startup",
		default_value = "circle",
		allowed_values = {"circle", "square"},
		order = "03"
	},
	-- restriction settings
	{
		type = "bool-setting",
        name = "claustorephobic-easy-mode",
        setting_type = "startup",
        default_value = false,
        order = "10"
	},
	{	
		type = "string-setting",
		name = "claustorephobic-allowed-prototypes",
		setting_type = "startup",
		default_value = "inserter transport-belt splitter underground-belt electric-pole pipe pipe-to-ground pump container logistic-container storage-tank offshore-pump wall gate",
		order = "11"
	}
})
