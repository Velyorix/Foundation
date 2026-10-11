local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local store = context:Store()
local state = { loads = nil, previous = nil }

store:Get("loads"):Then(function(previous)
	state.previous = previous
	state.loads = (previous or 0) + 1
	return store:Set("loads", state.loads)
end)

Package.Export("StorageFixture", state)
