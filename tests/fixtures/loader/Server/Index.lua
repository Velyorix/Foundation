local shared = Package.Require("lib/shared_value.lua")
local sibling = Package.Require("sibling.lua")
return { shared = shared, sibling = sibling, side = "server" }
