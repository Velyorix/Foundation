local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local lines = {}
	local time = { now = 0 }
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(_, line)
			lines[#lines + 1] = line
		end,
		clock = function()
			return time.now
		end,
		now = function()
			return 0
		end,
	})
	runtime:Start()
	local function register(id)
		return runtime.packages:Register({
			GetName = function()
				return id
			end,
			Subscribe = function() end,
		}, { api = "0.1" })
	end
	return runtime, register, lines, time
end

local function at_caller(fn, expected)
	local message = expect.raises(fn, expected)
	expect.truthy(tostring(message):find("registries_spec%.lua:%d+:"), tostring(message))
end

describe("Registries", function()
	local runtime, register, lines, time, shooter, S

	before_each(function()
		runtime, register, lines, time = setup()
		shooter = register("shooter")
		S = runtime.schema
	end)

	it("keeps entries under keys of the registering package", function()
		local weapons = shooter:DefineRegistry("weapons")
		expect.equal(weapons:GetName(), "shooter:weapons")
		local rifle = { damage = 30 }
		local handle = weapons:Register("rifle", rifle)
		expect.equal(weapons:Get("shooter:rifle"), rifle)
		expect.equal(weapons:Get("Shooter:Rifle"), rifle)
		expect.truthy(weapons:Has("shooter:rifle"))
		expect.falsy(weapons:Has("shooter:bow"))
		expect.is_nil(weapons:Get("shooter:bow"))
		expect.same(weapons:GetEntry("shooter:rifle"), { key = "shooter:rifle", value = rifle, owner = "shooter" })
		expect.equal(weapons:Count(), 1)
		expect.same(weapons:Keys(), { "shooter:rifle" })
		handle:Release()
		expect.falsy(weapons:Has("shooter:rifle"))
		expect.equal(weapons:Count(), 0)
	end)

	it("lets other packages read and, when open, contribute in their own namespace", function()
		local weapons = shooter:DefineRegistry("weapons", { contributions = "open" })
		weapons:Register("rifle", 1)
		local extra = register("extra-guns")
		local view = extra:Registry("shooter:weapons")
		view:Register("laser", 2)
		expect.equal(weapons:Get("extra-guns:laser"), 2)
		expect.same(view:Keys(), { "extra-guns:laser", "shooter:rifle" })
		expect.same(view:Keys("extra-guns"), { "extra-guns:laser" })
		at_caller(function()
			view:Register("shooter:shotgun", 3)
		end, "must be in the 'extra-guns' namespace")
		expect.is_nil(extra:Registry("shooter:armors"))
	end)

	it("refuses contributions from other packages unless the registry is open", function()
		shooter:DefineRegistry("weapons")
		local view = register("extra-guns"):Registry("shooter:weapons")
		expect.equal(view:Count(), 0)
		at_caller(function()
			view:Register("laser", 2)
		end, "only shooter can register entries in 'shooter:weapons'")
	end)

	it("never replaces an entry silently", function()
		local weapons = shooter:DefineRegistry("weapons")
		local changes = {}
		weapons:OnChange(function(action, key, value)
			changes[#changes + 1] = action .. " " .. key .. " " .. tostring(value)
		end)
		local first = weapons:Register("rifle", 1)
		at_caller(function()
			weapons:Register("rifle", 2)
		end, "'shooter:rifle' is already registered in 'shooter:weapons'")
		local second = weapons:Register("rifle", 2, { replace = true })
		expect.falsy(first:IsActive())
		expect.truthy(second:IsActive())
		expect.equal(weapons:Get("shooter:rifle"), 2)
		expect.equal(weapons:Count(), 1)
		second:Release()
		expect.same(changes, { "added shooter:rifle 1", "replaced shooter:rifle 2", "removed shooter:rifle 2" })
	end)

	it("validates values with the registry schema and stores the validated copy", function()
		local weapons = shooter:DefineRegistry("weapons", {
			schema = S:Record({ damage = S:Integer({ min = 1 }), ammo = S:Optional(S:String(), "9mm") }),
		})
		weapons:Register("pistol", { damage = 10 })
		expect.same(weapons:Get("shooter:pistol"), { damage = 10, ammo = "9mm" })
		at_caller(function()
			weapons:Register("broken", { damage = 0 })
		end, "does not match the schema of 'shooter:weapons': $.damage: must be at least 1")
	end)

	it("removes the entries of a package when it stops", function()
		local weapons = shooter:DefineRegistry("weapons", { contributions = "open" })
		local removed = {}
		weapons:OnChange(function(action, key)
			if action == "removed" then
				removed[#removed + 1] = key
			end
		end)
		local extra = register("extra-guns")
		local handle = extra:Registry("shooter:weapons"):Register("laser", 2)
		runtime.packages:Disable("extra-guns", "unload")
		expect.falsy(handle:IsActive())
		expect.falsy(weapons:Has("extra-guns:laser"))
		expect.same(removed, { "extra-guns:laser" })
	end)

	it("removes the registry with its package and tells the watchers", function()
		local extra = register("extra-guns")
		local seen = {}
		extra:OnRegistry("shooter:weapons", function(view)
			seen[#seen + 1] = view and view:GetName() or "none"
			if view then
				view:Register("laser", 2)
			end
		end)
		local weapons = shooter:DefineRegistry("weapons", { contributions = "open" })
		expect.equal(weapons:Get("extra-guns:laser"), 2)
		local view = extra:Registry("shooter:weapons")
		runtime.packages:Disable("shooter", "unload")
		expect.same(seen, { "shooter:weapons", "none" })
		at_caller(function()
			view:Get("extra-guns:laser")
		end, "'shooter:weapons' was removed because the package that defined it stopped")
		expect.is_nil(extra:Registry("shooter:weapons"))
		expect.equal(runtime.ownership:Count("extra-guns", "registry_entry"), 0)

		local again = register("shooter"):DefineRegistry("weapons", { contributions = "open" })
		expect.same(seen, { "shooter:weapons", "none", "shooter:weapons" })
		expect.equal(again:Get("extra-guns:laser"), 2)
	end)

	it("keeps listings to its package when not enumerable", function()
		local secrets = shooter:DefineRegistry("secrets", { enumerable = false })
		secrets:Register("code", 1)
		expect.same(secrets:Keys(), { "shooter:code" })
		local view = register("other"):Registry("shooter:secrets")
		expect.equal(view:Get("shooter:code"), 1)
		at_caller(function()
			view:Keys()
		end, "cannot be listed by other packages")
	end)

	it("reports wrong calls at the caller's line", function()
		local weapons = shooter:DefineRegistry("weapons")
		at_caller(function()
			shooter:DefineRegistry("weapons")
		end, "'shooter:weapons' is already defined")
		at_caller(function()
			shooter:DefineRegistry("other:weapons")
		end, "must be in the 'shooter' namespace")
		at_caller(function()
			shooter:DefineRegistry("armors", { schema = "record" })
		end, "'options.schema' must be schema (got string)")
		at_caller(function()
			shooter:DefineRegistry("armors", { contributions = "everyone" })
		end, "must be 'owner' or 'open'")
		at_caller(function()
			shooter:DefineRegistry("armors", { listed = true })
		end, "unknown field 'listed'")
		at_caller(function()
			weapons:Register("rifle", nil)
		end, "'value' must be value (got nil)")
		at_caller(function()
			weapons:Register("rifle", 1, { force = true })
		end, "unknown field 'force'")
		at_caller(function()
			weapons:Register("rifle", 1, { deprecated = 3 })
		end, "'options.deprecated' must be string|true|nil (got number)")
		at_caller(function()
			weapons:Get("Bad Key")
		end, "'key' is invalid")
		at_caller(function()
			weapons:OnChange("nope")
		end, "'fn' must be function (got string)")
		at_caller(function()
			shooter:Registry(42)
		end, "'key' is invalid")
		at_caller(function()
			shooter:OnRegistry("shooter:weapons")
		end, "'fn' must be function (got nil)")
	end)

	it("warns each reading package once about a deprecated entry", function()
		local weapons = shooter:DefineRegistry("weapons", { contributions = "open" })
		weapons:Register("musket", 1, { deprecated = "use shooter:rifle" })
		local view = register("arena"):Registry("shooter:weapons")
		expect.equal(view:Get("shooter:musket"), 1)
		expect.truthy(view:Has("shooter:musket"))
		expect.equal(view:GetEntry("shooter:musket").deprecated, "use shooter:rifle")
		weapons:Get("shooter:musket")
		time.now = 60
		view:Get("shooter:musket")
		weapons:Get("shooter:musket")
		local output = table.concat(lines, "\n")
		local _, count = output:gsub("the deprecated entry 'shooter:musket' of 'shooter:weapons' was used", "")
		expect.equal(count, 2)
		expect.contains(
			output,
			"arena/registries: the deprecated entry 'shooter:musket' of 'shooter:weapons' was used use shooter:rifle"
		)
	end)

	it("keeps old names working for renamed entries", function()
		local weapons = shooter:DefineRegistry("weapons")
		local rifle = { damage = 30 }
		weapons:Register("assault-rifle", rifle)
		local alias = weapons:Alias("rifle", "assault-rifle")
		local view = register("arena"):Registry("shooter:weapons")
		expect.equal(view:Get("shooter:rifle"), rifle)
		expect.equal(view:Get("Shooter:Rifle"), rifle)
		expect.equal(view:GetEntry("shooter:rifle").key, "shooter:assault-rifle")
		expect.equal(view:Resolve("shooter:rifle"), "shooter:assault-rifle")
		expect.equal(view:Resolve("shooter:assault-rifle"), "shooter:assault-rifle")
		expect.is_nil(view:Resolve("shooter:bow"))
		expect.same(view:Keys(), { "shooter:assault-rifle" })
		local _, count =
			table.concat(lines, "\n"):gsub("'shooter:rifle' is an old name of 'shooter:assault%-rifle'", "")
		expect.equal(count, 1)
		at_caller(function()
			weapons:Register("rifle", 1)
		end, "'shooter:rifle' is already used in 'shooter:weapons'")
		at_caller(function()
			weapons:Alias("assault-rifle", "laser")
		end, "'shooter:assault-rifle' is already used in 'shooter:weapons'")
		at_caller(function()
			weapons:Alias("carbine", "rifle")
		end, "must point to current keys")
		at_caller(function()
			weapons:Alias("old-rifle", "shooter:old-rifle")
		end, "an old name cannot point to itself")
		at_caller(function()
			weapons:Alias("assault", "rifle2")
			weapons:Alias("rifle2", "x")
		end, "must point to current keys")
		alias:Release()
		expect.is_nil(view:Get("shooter:rifle"))
	end)

	it("refuses old names from packages that cannot contribute", function()
		shooter:DefineRegistry("weapons")
		at_caller(function()
			register("arena"):Registry("shooter:weapons"):Alias("rifle", "shooter:rifle")
		end, "only shooter can register entries in 'shooter:weapons'")
	end)

	it("runs watcher and listener errors guarded", function()
		local weapons = shooter:DefineRegistry("weapons")
		weapons:OnChange(function()
			error("listener broke")
		end)
		weapons:Register("rifle", 1)
		expect.equal(weapons:Get("shooter:rifle"), 1)
		local output = table.concat(lines, "\n")
		expect.contains(output, "registry_listener callback of shooter failed")
	end)
end)
