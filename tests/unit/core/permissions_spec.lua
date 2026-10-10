local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Facade = loader:require("foundation/core/facade.lua")
	local Senders = loader:require("foundation/core/senders.lua")
	local lines = {}
	local clock = { now = 0 }
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(_, line)
			lines[#lines + 1] = line
		end,
		clock = function()
			return clock.now
		end,
		now = function()
			return 0
		end,
	})
	runtime:Start()
	local function register(id)
		local native = {
			GetName = function()
				return id
			end,
			Subscribe = function() end,
		}
		return runtime.packages:Register(native, { api = "0.1" })
	end
	return runtime, Facade.new(runtime), register, Senders, lines, clock
end

describe("Permissions", function()
	local runtime, Foundation, register, Senders, lines, clock, homes

	before_each(function()
		runtime, Foundation, register, Senders, lines, clock = setup()
		homes = register("homes")
		runtime.permissions.is_operator = function(id)
			return id == "op-1"
		end
	end)

	local function has(subject, node)
		return Foundation.Permissions.Has(subject, node)
	end

	describe("declarations", function()
		it("returns the normalized node and describes it", function()
			expect.equal(
				homes:DeclarePermission("Homes.Set", { description = "Set a home", default = "everyone" }),
				"homes.set"
			)
			expect.same(Foundation.Permissions.Get("homes.set"), {
				node = "homes.set",
				owner = "homes",
				description = "Set a home",
				default = "everyone",
			})
			expect.is_nil(Foundation.Permissions.Get("homes.unknown"))
		end)

		it("lists declarations, optionally for one package", function()
			homes:DeclarePermission("homes.set")
			homes:DeclarePermission("homes.admin.delete", { default = "nobody" })
			register("warps"):DeclarePermission("warps.use")
			local nodes = {}
			for index, item in ipairs(Foundation.Permissions.List("homes")) do
				nodes[index] = item.node .. "=" .. item.default
			end
			expect.same(nodes, { "homes.admin.delete=nobody", "homes.set=operators" })
			expect.equal(#Foundation.Permissions.List(), 3)
		end)

		it("rejects malformed or foreign nodes", function()
			local cases = {
				{ { "homes" }, "must be dotted segments" },
				{ { "homes..set" }, "must be dotted segments" },
				{ { "homes.set home" }, "must be dotted segments" },
				{ { "warps.use" }, "must start with 'homes.'" },
				{ { "homesick.use" }, "must start with 'homes.'" },
				{
					{ "homes.set", { default = "admins" } },
					"expected one of everyone, nobody, operators, non_operators",
				},
				{ { "homes.set", { level = 1 } }, "unknown field 'level'" },
				{ { "homes.set", { deprecated = 1 } }, "'definition.deprecated' must be string|true|nil (got number)" },
				{ { 42 }, "'node' must be string (got number)" },
			}
			for _, case in ipairs(cases) do
				expect.raises(function()
					homes:DeclarePermission(table.unpack(case[1]))
				end, case[2])
			end
		end)

		it("refuses a second declaration of the same node", function()
			homes:DeclarePermission("homes.set")
			expect.raises(function()
				homes:DeclarePermission("homes.set")
			end, "'homes.set' is already declared by homes")
		end)

		it("goes away with its package", function()
			homes:DeclarePermission("homes.set", { default = "everyone" })
			runtime.packages:Disable("homes", "unload")
			expect.is_nil(Foundation.Permissions.Get("homes.set"))
			expect.falsy(has("player-1", "homes.set"))
		end)
	end)

	describe("resolution", function()
		before_each(function()
			homes:DeclarePermission("homes.use", { default = "everyone" })
			homes:DeclarePermission("homes.locked", { default = "nobody" })
			homes:DeclarePermission("homes.admin", { default = "operators" })
			homes:DeclarePermission("homes.guide", { default = "non_operators" })
		end)

		it("applies the declared default for players and operators", function()
			local expected = {
				["homes.use"] = { true, true },
				["homes.locked"] = { false, false },
				["homes.admin"] = { false, true },
				["homes.guide"] = { true, false },
			}
			for node, values in pairs(expected) do
				expect.equal(has("player-1", node), values[1], node .. " for a player")
				expect.equal(has("op-1", node), values[2], node .. " for an operator")
			end
		end)

		it("treats undeclared nodes as operator-only", function()
			expect.falsy(has("player-1", "other.thing"))
			expect.truthy(has("op-1", "other.thing"))
		end)

		it("accepts senders and gives the console every permission", function()
			local console = Senders.new({ kind = "console", reply = function() end })
			local player = Senders.new({ kind = "player", id = "op-1", reply = function() end })
			expect.truthy(has(console, "homes.locked"))
			expect.truthy(has(player, "homes.admin"))
			expect.equal(select(2, runtime.permissions:Resolve(console, "homes.locked", "test", 2)), "console")
		end)

		it("ignores the case of nodes", function()
			expect.truthy(has("player-1", "HOMES.USE"))
		end)

		it("warns once when a deprecated permission is checked", function()
			homes:DeclarePermission("homes.old", { default = "everyone", deprecated = "use homes.use" })
			has("player-1", "homes.old")
			clock.now = 60
			has("player-1", "homes.old")
			local count = 0
			for _, line in ipairs(lines) do
				if line:find("the deprecated permission 'homes.old' was checked use homes.use", 1, true) then
					count = count + 1
				end
			end
			expect.equal(count, 1)
		end)

		it("validates arguments at the caller's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				has(42, "homes.use")
			end)
			expect.falsy(ok)
			expect.contains(message, "'subject' must be sender or account id (got number)")
			expect.equal(tonumber(message:match("permissions_spec%.lua:(%d+):")), expected_line)
			expect.raises(function()
				has("player-1", "homes")
			end, "must be dotted segments")
		end)
	end)

	describe("attachments", function()
		local games

		before_each(function()
			homes:DeclarePermission("homes.use", { default = "everyone" })
			homes:DeclarePermission("homes.admin")
			games = register("games")
		end)

		local function explain(subject, node)
			local result = Foundation.Permissions.Explain(subject, node)
			return tostring(result.allowed)
				.. ":"
				.. result.source
				.. (result.package and (":" .. result.package) or "")
		end

		it("override the default for one subject", function()
			games:AttachPermission("player-1", "homes.use", false)
			games:AttachPermission("player-2", "homes.admin", true)
			expect.equal(explain("player-1", "homes.use"), "false:attachment:games")
			expect.equal(explain("player-2", "homes.admin"), "true:attachment:games")
			expect.equal(explain("player-3", "homes.use"), "true:default")
		end)

		it("let a deny win over an allow from another package", function()
			games:AttachPermission("player-1", "homes.admin", true)
			homes:AttachPermission("player-1", "homes.admin", false)
			register("events"):AttachPermission("player-1", "homes.admin", true)
			expect.equal(explain("player-1", "homes.admin"), "false:attachment:homes")
		end)

		it("expire after their duration", function()
			games:AttachPermission("player-1", "homes.admin", true, { duration = 5000 })
			clock.now = 4.999
			expect.truthy(has("player-1", "homes.admin"))
			clock.now = 5
			expect.falsy(has("player-1", "homes.admin"))
			expect.same(runtime.permissions.attachments, {})
		end)

		it("are removed with their handle or their package", function()
			local handle = games:AttachPermission("player-1", "homes.admin", true)
			expect.truthy(has("player-1", "homes.admin"))
			expect.truthy(handle:Release())
			expect.falsy(has("player-1", "homes.admin"))
			games:AttachPermission("player-1", "homes.admin", true)
			runtime.packages:Disable("games", "unload")
			expect.falsy(has("player-1", "homes.admin"))
			expect.equal(runtime.ownership:Count("games"), 0)
		end)

		it("can be cleared for a subject", function()
			games:AttachPermission("player-1", "homes.admin", true)
			runtime.permissions:ClearSubject("player-1")
			expect.falsy(has("player-1", "homes.admin"))
		end)

		it("work on undeclared nodes and accept senders", function()
			local player = Senders.new({ kind = "player", id = "player-1", reply = function() end })
			games:AttachPermission(player, "other.fly", true)
			expect.truthy(has("player-1", "other.fly"))
		end)

		it("validate their arguments at the caller's line", function()
			local console = Senders.new({ kind = "console", reply = function() end })
			local cases = {
				{ { console, "homes.use", true }, "the console has every permission" },
				{ { "player-1", "homes", true }, "must be dotted segments" },
				{ { "player-1", "homes.use", "yes" }, "'value' must be boolean (got string)" },
				{ { "player-1", "homes.use", true, { duration = 0 } }, "must be a positive number of milliseconds" },
				{ { "player-1", "homes.use", true, { permanent = true } }, "unknown field 'permanent'" },
			}
			for _, case in ipairs(cases) do
				local expected_line
				local ok, message = pcall(function()
					expected_line = debug.getinfo(1, "l").currentline + 1
					games:AttachPermission(table.unpack(case[1]))
				end)
				expect.falsy(ok)
				expect.contains(message, case[2])
				expect.equal(tonumber(message:match("permissions_spec%.lua:(%d+):")), expected_line)
			end
		end)
	end)
end)
