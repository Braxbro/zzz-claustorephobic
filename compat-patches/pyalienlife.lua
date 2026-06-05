local nexelit = data.raw["resources"]["ore-nexelit"] 
nexelit.autoplace.probability_expression = "claustorephobic_force(" .. 
    nexelit.autoplace.probability_expression .. ")"
nexelit.autoplace.richness_expression = "claustorephobic_force(" .. 
    nexelit.autoplace.richness_expression .. ")"