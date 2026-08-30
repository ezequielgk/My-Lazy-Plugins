--!nonstrict
local lib = require("./lib.luau")

local function update(active_name)
    if active_name and active_name ~= "" then
        barWidget.setText(active_name)
    else
        barWidget.setText("Profiles")
    end
end

update(lib.getActiveProfile())
noctalia.state.watch("active_profile", function(val)
    update(val)
end)

function onClick()
    lib.cycleProfile()
end

function onRightClick()
    noctalia.togglePanel("ezequielgk/profiles:manager")
end

function onScroll(axis, steps, startsGesture)
    if steps < 0 then
        lib.cycleProfile()
    elseif steps > 0 then
        lib.cycleProfile()
    end
end
