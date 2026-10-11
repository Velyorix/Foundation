local TOGGLE = "foundation/migration-fixture.txt"
local version = 1
if File.Exists(TOGGLE) then
	local file = File(TOGGLE)
	version = tonumber(file:Read()) or 1
	file:Close()
end

local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local state = { version = version }
local migrations = {
	function(entries)
		local result = {}
		for name, coins in pairs(entries) do
			result["account:" .. name] = { coins = coins }
		end
		return result
	end,
	function()
		error("this migration always fails")
	end,
}

local store = context:Store("bank", { version = version, migrations = migrations })
if version == 1 then
	store:Batch({ { op = "set", key = "alex", value = 10 }, { op = "set", key = "sam", value = 3 } })
end
store:Get("account:alex"):Then(function(account)
	state.alex = account
end)

Package.Export("MigrationFixture", state)
