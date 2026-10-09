local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local lines = {}
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(level, line)
			lines[#lines + 1] = { level = level, line = line }
		end,
		clock = function()
			return 0
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
	return runtime, register, lines
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.line
	end
	return table.concat(parts, "\n")
end

local function noop() end

local function words(line)
	local result = {}
	for word in line:gmatch("%S+") do
		result[#result + 1] = word
	end
	return result
end

describe("Commands", function()
	local runtime, register, lines, homes, warps

	before_each(function()
		runtime, register, lines = setup()
		homes = register("homes")
		warps = register("warps")
	end)

	local function resolve(line)
		local result = runtime.commands:Resolve(words(line))
		if not result then
			return nil
		end
		return {
			owner = result.root.owner,
			path = table.concat(result.path, " "),
			arguments = table.concat(result.arguments, " "),
		}
	end

	describe("registration", function()
		it("builds a tree reachable by name, alias and namespaced label", function()
			homes:RegisterCommand({
				name = "home",
				aliases = { "h" },
				description = "Teleport to a home",
				run = noop,
				subcommands = {
					{ name = "set", aliases = { "add" }, run = noop },
					{
						name = "share",
						subcommands = { { name = "with", run = noop } },
					},
				},
			})
			expect.same(resolve("home"), { owner = "homes", path = "home", arguments = "" })
			expect.same(resolve("H Set base"), { owner = "homes", path = "home set", arguments = "base" })
			expect.same(resolve("homes:home add base"), { owner = "homes", path = "home set", arguments = "base" })
			expect.same(
				resolve("homes:h share with alex"),
				{ owner = "homes", path = "home share with", arguments = "alex" }
			)
			expect.same(resolve("home unknown x"), { owner = "homes", path = "home", arguments = "unknown x" })
			expect.is_nil(resolve("nothing"))
		end)

		it("rejects malformed specifications", function()
			local cases = {
				{ {}, "'spec.name' is invalid: must start with a lowercase letter" },
				{ { name = "Home", run = noop }, "'spec.name' is invalid" },
				{ { name = "home" }, "'spec' is invalid: needs a run function or subcommands" },
				{ { name = "home", run = "go" }, "'spec.run' must be function? (got string)" },
				{ { name = "home", run = noop, permission = "x" }, "unknown field 'permission'" },
				{ { name = "home", aliases = { "home" }, run = noop }, "'home' is used twice under 'home'" },
				{
					{ name = "home", subcommands = { { name = "set", run = noop }, { name = "set", run = noop } } },
					"'spec.subcommands[2]' is invalid: 'set' is used twice under 'home'",
				},
				{
					{ name = "home", subcommands = { { name = "x" } } },
					"'spec.subcommands[1]' is invalid: needs a run",
				},
				{ { name = "foundation", run = noop }, "'foundation' is reserved for Foundation" },
				{
					{ name = "admin", aliases = { "foundation" }, run = noop },
					"'foundation' is reserved for Foundation",
				},
			}
			for _, case in ipairs(cases) do
				expect.raises(function()
					homes:RegisterCommand(case[1])
				end, case[2])
			end
		end)

		it("limits nesting", function()
			local spec = { name = "level9", run = noop }
			for level = 8, 1, -1 do
				spec = { name = "level" .. level, subcommands = { spec } }
			end
			expect.raises(function()
				homes:RegisterCommand(spec)
			end, "subcommands are nested more than 8 levels deep")
		end)

		it("refuses labels already used by the same package", function()
			homes:RegisterCommand({ name = "home", aliases = { "h" }, run = noop })
			expect.raises(function()
				homes:RegisterCommand({ name = "h", run = noop })
			end, "'h' is already used by this package's command 'home'")
		end)

		it("reports errors at the package's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				homes:RegisterCommand({ name = "Bad" })
			end)
			expect.falsy(ok)
			expect.equal(tonumber(message:match("commands_spec%.lua:(%d+):")), expected_line)
		end)
	end)

	describe("collisions between packages", function()
		it("keeps the plain label for the first package and points the second to its namespaced label", function()
			homes:RegisterCommand({ name = "spawn", run = noop })
			warps:RegisterCommand({ name = "spawn", run = noop })
			expect.equal(resolve("spawn").owner, "homes")
			expect.equal(resolve("warps:spawn").owner, "warps")
			expect.contains(text(lines), "/spawn of warps is already used by homes; it is available as /warps:spawn")
		end)

		it("gives names priority over aliases of other packages", function()
			homes:RegisterCommand({ name = "home", aliases = { "w" }, run = noop })
			warps:RegisterCommand({ name = "w", run = noop })
			expect.equal(resolve("w").owner, "warps")
			expect.equal(resolve("homes:w").owner, "homes")
			expect.contains(text(lines), "alias /w of homes is now used by the command of warps")
		end)

		it("ignores an alias already taken", function()
			homes:RegisterCommand({ name = "home", aliases = { "go" }, run = noop })
			warps:RegisterCommand({ name = "warp", aliases = { "go" }, run = noop })
			expect.equal(resolve("go").owner, "homes")
			expect.equal(resolve("warps:go").owner, "warps")
			expect.contains(text(lines), "alias /go of warps is already used by homes and is ignored")
		end)

		it("gives a freed label back when its holder goes away", function()
			homes:RegisterCommand({ name = "spawn", run = noop })
			warps:RegisterCommand({ name = "spawn", run = noop })
			runtime.packages:Disable("homes", "unload")
			expect.equal(resolve("spawn").owner, "warps")
			expect.is_nil(resolve("homes:spawn"))
		end)
	end)

	describe("cleanup", function()
		it("removes a command with its handle", function()
			local handle = homes:RegisterCommand({ name = "home", aliases = { "h" }, run = noop })
			expect.truthy(handle:Release())
			expect.is_nil(resolve("home"))
			expect.is_nil(resolve("h"))
			expect.no_error(function()
				homes:RegisterCommand({ name = "home", run = noop })
			end)
		end)

		it("removes the commands of a disabled package", function()
			homes:RegisterCommand({ name = "home", run = noop })
			runtime.packages:Disable("homes", "unload")
			expect.is_nil(resolve("home"))
			expect.same(runtime.commands:Snapshot().commands, {
				{ owner = "foundation", name = "foundation", labels = { "foundation", "foundation:foundation" } },
			})
			expect.equal(runtime.ownership:Count("homes"), 0)
		end)
	end)

	it("lists labels for the console and chat bridges", function()
		homes:RegisterCommand({ name = "home", aliases = { "h" }, run = noop })
		local labels = runtime.commands:Labels()
		expect.same(labels.home, { owner = "homes", name = "home", kind = "name" })
		expect.same(labels.h, { owner = "homes", name = "home", kind = "alias" })
		expect.same(labels["homes:h"], { owner = "homes", name = "home", kind = "namespaced" })
		expect.same(runtime.commands:Snapshot().commands[2], {
			owner = "homes",
			name = "home",
			labels = { "h", "home", "homes:h", "homes:home" },
		})
	end)
end)
