local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local S = Foundation.Schema

local weapons = context:DefineRegistry("weapons", {
	contributions = "open",
	schema = S.Record({ damage = S.Integer({ min = 1 }), slot = S.Optional(S.String(), "primary") }),
})
weapons:Register("rifle", { damage = 30 })
weapons:Register("musket", { damage = 12 }, { deprecated = "use foundation-registries-fixture:rifle" })
weapons:Alias("gun", "rifle")
