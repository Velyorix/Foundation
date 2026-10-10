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
	local Json = loader:require("foundation/core/json.lua")
	local Operators = loader:require("foundation/core/operators.lua")
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
		create_operators = function(rt)
			return Operators.new({
				files = Files.new(raw),
				json = Json,
				messages = rt.messages,
				log = rt.log:For("foundation", "operators"),
				now = function()
					return 1760100000
				end,
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
	local function sender(kind, id)
		local replies = {}
		return Senders.new({
			kind = kind,
			id = id or kind,
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
			"choose one of: version, help, packages, services, reload-config, op, permissions",
			"Usage: foundation <version|help|packages|services|reload-config|op|permissions>",
		})
	end)

	it("opens commands to players according to their permissions", function()
		local player, player_replies = sender("player", "alex-id")
		expect.equal(runtime.commands:Execute(player, "foundation version").status, "ok")
		expect.equal(runtime.commands:Execute(player, "foundation packages").status, "denied")
		expect.equal(runtime.commands:Execute(player, "foundation op add alex-id").status, "denied")
		expect.same(player_replies, {
			"Foundation 0.1.0 (API 0.1)",
			"you do not have permission to use this command",
			"you do not have permission to use this command",
		})
		run("foundation op add alex-id Alex")
		expect.equal(runtime.commands:Execute(player, "foundation packages").status, "ok")
	end)

	describe("op", function()
		it("adds, lists and removes operators", function()
			run("foundation op list")
			run("foundation op add alex-id Alex the Great")
			run("foundation op add sam-id")
			run("foundation op add sam-id")
			run("foundation op list")
			run("foundation op remove sam-id")
			run("foundation op remove sam-id")
			expect.same(replies, {
				"There is no operator.",
				"alex-id is now an operator",
				"sam-id is now an operator",
				"this account is already an operator",
				"Operators (2):",
				"  alex-id Alex the Great (added by console)",
				"  sam-id (added by console)",
				"sam-id is no longer an operator",
				"this account is not an operator",
			})
			expect.truthy(raw.contents["foundation/operators.json"]:find('"alex-id"', 1, true))
		end)

		it("records who made the change and audits it", function()
			run("foundation op add alex-id")
			local alex = sender("player", "alex-id")
			runtime.commands:Execute(alex, "foundation op add sam-id")
			expect.equal(runtime.operators:List()[2].added_by, "player:alex-id")
			local actions = {}
			for _, record in ipairs(audited) do
				actions[#actions + 1] = record.action
			end
			expect.same(actions, {
				"foundation:command/foundation/op/add",
				"foundation:command/foundation/op/add",
			})
		end)
	end)

	describe("permissions", function()
		before_each(function()
			local homes = register("homes")
			homes:DeclarePermission("homes.admin", { description = "Manage homes", default = "nobody" })
			homes:DeclarePermission("homes.use", { default = "everyone" })
			register("games"):AttachPermission("alex-id", "homes.admin", true)
		end)

		it("explains the decision for an account", function()
			run("foundation permissions check alex-id homes.admin")
			run("foundation permissions check sam-id HOMES.ADMIN")
			run("foundation permissions check sam-id other.thing")
			expect.same(replies, {
				"homes.admin for alex-id: allowed (attachment from games)",
				"  declared by homes, default: nobody",
				"  Manage homes",
				"homes.admin for sam-id: denied (declared default)",
				"  declared by homes, default: nobody",
				"  Manage homes",
				"other.thing for sam-id: denied (declared default)",
				"  not declared: only operators have it",
			})
		end)

		it("lists declared permissions, optionally for one package", function()
			run("foundation permissions list homes")
			expect.same(replies, {
				"Permissions (2):",
				"  homes.admin (nobody) - Manage homes",
				"  homes.use (everyone)",
			})
			replies[1] = nil
			for index = #replies, 1, -1 do
				replies[index] = nil
			end
			run("foundation permissions list foundation")
			expect.equal(replies[1], "Permissions (7):")
			expect.equal(replies[2], "  foundation.command.help (everyone) - Use foundation help")
		end)
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
				"foundation <version|help|packages|services|reload-config|op|permissions> - Foundation administration",
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

	describe("services", function()
		it("says when nothing is declared", function()
			run("foundation services")
			expect.same(replies, { "No service or capability is declared." })
		end)

		it("shows providers, requirements, missing services and capabilities", function()
			register("coins"):ProvideService("economy:bank", "1.2", {}, { priority = 10 })
			register("gems"):ProvideService("economy:bank", "1.0", {})
			register("shop", {
				api = "0.1",
				services = {
					{ name = "economy:bank", version = "1.1" },
					{ name = "chat:format", optional = true },
				},
			})
			register("auction", { api = "0.1", services = { { name = "economy:bank", version = "2" } } })
			local capabilities = { { name = "chat:emotes", version = "2.1" }, "chat:colors", "chat:bold" }
			local chat = register("chat-plus", { api = "0.1", capabilities = capabilities })
			runtime.packages:mark_ready(runtime.packages.entries["chat-plus"])
			expect.equal(chat:GetState(), "ready")
			run("foundation services")
			expect.same(replies, {
				"Services (2):",
				"chat:format",
				"  no provider",
				"  used if present by: shop (any version, MISSING)",
				"economy:bank",
				"  provided by: coins 1.2 (priority 10), gems 1.0 (priority 0)",
				"  required by: shop (1.1), auction (2, MISSING)",
				"Capabilities (3):",
				"  chat:bold: chat-plus",
				"  chat:colors: chat-plus",
				"  chat:emotes: chat-plus 2.1",
			})
		end)
	end)
end)
