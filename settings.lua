data:extend({
    -- worldgen settings
    {
        type          = "int-setting"
      , name          = "claustorephobic-polygon-sides"
      , setting_type  = "startup"
      , default_value = 6
      , minimum_value = 3
      , maximum_value = 100
      , order         = "03a"
    }
    -- restriction settings
  , {
        type          = "bool-setting"
      , name          = "claustorephobic-easy-mode"
      , setting_type  = "startup"
      , default_value = false
      , order         = "10"
    }
  , {
        type          = "string-setting"
      , name          = "claustorephobic-allowed-prototypes"
      , setting_type  = "startup"
      , default_value = "inserter transport-belt splitter underground-belt electric-pole pipe pipe-to-ground pump container logistic-container storage-tank offshore-pump wall gate"
      , order         = "11"
    }
})
