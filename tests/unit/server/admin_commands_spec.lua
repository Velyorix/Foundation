local function memory_files()
	local raw = { contents = {}, directories = {} }
	function raw.Open(path, truncate)
		if truncate or raw.contents[path] == nil then
			raw.contents[path] = ""
		end
		return {
			Read = function()
				return raw.contents[path]
			end,
			Write = function(_, data)
				raw.contents[path] = raw.contents[path] .. data
			end,
			Flush = function() end,
			HasFailed = function()
				return false
			end,
			Close = function() end,
		}
	end
	function raw.Exists(path)
		return raw.contents[path] ~= nil
	end
	function raw.CreateDirectory(path)
		raw.directories[path] = true
		return true
	end
	function raw.IsDirectory(path)
		return raw.directories[path] == true
	end
	function raw.Rename(from, to)
		raw.contents[to] = raw.contents[from]
		raw.contents[from] = nil
		return true
	end
	return raw
end

local function setup()
	local loader = Loader.new({ side = "Server" })
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Files = loader:require("foundation/core/files.lua")
	local Config = loader:require("foundation/core/config.lua")
	local Settings = loader:require("foundation/core/settings.lua")
	local I18n = loader:require("foundation/core/i18n.lua")
	local PackageConfigs = loader:require("foundation/core/package_config.lua")
	local Senders = loader:require("foundation/core/senders.lua")
	local raw = memory_files()
	local parsed = {}
	local audited = {}
	local function parse(text)
		local data = parsed[text]
		if data == nil then
			error("bad format")
		end
		return data
	end
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function() end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
		create_config = function(rt)
			return Config.new({
				spec = Settings(rt.schema, rt.messages, I18n.IsLocale),
				files = Files.new(raw),
				parse = parse,
				schema = rt.schema,
				log = rt.log:For("foundation", "config"),
				errors = rt.errors,
			})
		end,
		create_package_configs = function(rt)
			return PackageConfigs.new({
				files = Files.new(raw),
				parse = parse,
				schema = rt.schema,
				check = rt.check,
				log = rt.log,
				invoker = rt.invoker,
			})
		end,
		create_audit = function()
			return {
				Record = function(_, owner, action, entry)
					audited[#audited + 1] = { owner = owner, action = action, outcome = entry.outcome }
					return true
				end,
			}
		end,
	})
	runtime:Start()
	local function register(id, manifest)
		local native = {
			GetName = function()
				return id
			end,
			GetVersion = function()
				return "1.2.0"
			end,
			Subscribe = function() end,
		}
		return runtime.packages:Register(native, manifest or { api = "0.1" })
	end
	local function sender(kind)
		local replies = {}
		return Senders.new({
			kind = kind,
			id = kind,
			reply = function(text)
				replies[#replies + 1] = text
			end,
		}),
			replies
	end
	return runtime, register, sender, raw, parsed, audited
end

describe("Foundation admin commands", function()
	local runtime, register, sender, raw, parsed, audited, console, replies

	before_each(function()
		runtime, register, sender, raw, parsed, audited = setup()
		console, replies = sender("console")
	end)

	local function run(line)
		return runtime.commands:Execute(console, line).status
	end

	it("shows the version", function()
		expect.equal(run("foundation version"), "ok")
		expect.same(replies, { "Foundation 0.1.0 (API 0.1)" })
	end)

	it("asks for a subcommand with the list", function()
		expect.equal(run("foundation"), "usage")
		expect.same(replies, {
			"choose one of: version, help, packages, reload-config",
			"Usage: foundation <version|help|packages|reload-config>",
		})
	end)

	it("is reserved to the console", function()
		local player, player_replies = sender("player")
		expect.equal(runtime.commands:Execute(player, "foundation version").status, "denied")
		expect.same(player_replies, { "this command can only be used from the server console" })
	end)

	it("lists packages and their state", function()
		expect.equal(run("foundation packages"), "ok")
		expect.same(replies, { "No package uses Foundation." })
		register("homes")
		local shop = register("shop")
		shop:OnReady(function()
			error("no database")
		end)
		runtime.packages:mark_ready(runtime.packages.entries.shop)
		replies = {}
		console, replies = sender("console")
		run("foundation packages")
		expect.same(replies, {
			"Packages (2):",
			"homes 1.2.0 - initializing",
			"shop 1.2.0 - failed: a ready hook of 'shop' failed",
		})
	end)

	describe("help", function()
		before_each(function()
			local homes = register("homes")
			homes:RegisterCommand({
				name = "home",
				aliases = { "h" },
				description = "Teleport to a home",
				arguments = { { name = "name", optional = true } },
				run = function() end,
				subcommands = { { name = "set", arguments = { { name = "name" } }, run = function() end } },
			})
		end)

		it("lists every command with its usage and description", function()
			run("foundation help")
			expect.same(replies, {
				"Commands (2):",
				"foundation <version|help|packages|reload-config> - Foundation administration",
				"home [name] - Teleport to a home",
			})
		end)

		it("describes one command with its aliases and subcommands", function()
			run("foundation help h")
			expect.same(replies, { "home [name] - Teleport to a home", "Aliases: h", "  home set <name>" })
		end)

		it("answers unknown commands", function()
			run("foundation help fly")
			expect.same(replies, { "unknown command: fly" })
		end)
	end)

	describe("reload-config", function()
		local settings, changes

		before_each(function()
			local shop = register("shop")
			parsed.SHOP = { motd = "Hello" }
			raw.contents["foundation/config/shop.toml"] = "SHOP"
			settings = shop:Config({
				fields = {
					{ key = "motd", schema = runtime.schema:String(), default = "Hi", reload = "hot" },
					{ key = "port", schema = runtime.schema:Integer(), default = 7777 },
				},
			})
			changes = {}
			settings:OnChange(function(changed)
				changes[#changes + 1] = table.concat(changed, ",")
			end)
		end)

		it("reloads every file, reports what changed and runs the change hooks", function()
			parsed.CORE = { language = "fr" }
			raw.contents["foundation/config.toml"] = "CORE"
			parsed.SHOP2 = { motd = "Welcome", port = 8000 }
			raw.contents["foundation/config/shop.toml"] = "SHOP2"
			expect.equal(run("foundation reload-config"), "ok")
			expect.same(replies, {
				"foundation/config.toml: 1 setting changed",
				"foundation/config/shop.toml: 1 setting changed",
				"foundation/config/shop.toml: restart the server to apply port",
			})
			expect.same(changes, { "motd" })
			expect.equal(settings:Get("motd"), "Welcome")
			expect.equal(settings:Get("port"), 7777)
			expect.same(audited, {
				{ owner = "foundation", action = "foundation:command/foundation/reload-config", outcome = "success" },
			})
		end)

		it("reports files left unchanged or rejected", function()
			parsed[raw.contents["foundation/config.toml"]] = {}
			raw.contents["foundation/config/shop.toml"] = "broken"
			run("foundation reload-config")
			expect.same(replies, {
				"foundation/config.toml: no change",
				"foundation/config/shop.toml: rejected, the current settings are kept (details in the log)",
			})
			expect.equal(settings:Get("motd"), "Hello")
		end)
	end)
end)
