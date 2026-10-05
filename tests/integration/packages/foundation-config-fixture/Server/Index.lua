local context = Foundation.Register(Package, { api = Foundation.API_VERSION, name = "Config Fixture" })
local S = Foundation.Schema

local settings = context:Config({
	fields = {
		{ key = "motd", schema = S.String({ max = 32 }), default = "Welcome", description = "Shown on join." },
		{ key = "homes.max", schema = S.Integer({ min = 0 }), default = 3, reload = "hot" },
	},
})

Package.Export("ConfigFixture", { settings = settings })
