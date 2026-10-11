local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local store = context:Store()
local state = { loads = nil, previous = nil }

store:Get("loads"):Then(function(previous)
	state.previous = previous
	state.loads = (previous or 0) + 1
	return store:Set("loads", state.loads)
end)

local visits = context:DefineData("visits", Foundation.Schema.Integer({ min = 0 }), { default = 0 })
visits:Get("76561198000000001"):Then(function(count)
	return visits:Set("76561198000000001", count + 1)
end)

Package.Export("StorageFixture", state)
