local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local grants = { ["alex foundation-core-permissions-test.admin"] = true }

context:ProvideService("foundation:permission_provider", "1.0", {
	Check = function(_, subject, node)
		return grants[subject .. " " .. node]
	end,
})
