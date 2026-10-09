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

local function setup(with_core_config)
	local loader = Loader.new({ side = "Server" })
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Files = loader:require("foundation/core/files.lua")
	local PackageConfigs = loader:require("foundation/core/package_config.lua")
	local raw = memory_files()
	local parsed = {}
	local lines = {}
	local function parse(text)
		local data = parsed[text]
		if data == nil then
			error("bad format")
		end
		return data
	end
	local create_config
	if with_core_config then
		local Config = loader:require("foundation/core/config.lua")
		local Settings = loader:require("foundation/core/settings.lua")
		local I18n = loader:require("foundation/core/i18n.lua")
		create_config = function(rt)
			return Config.new({
				spec = Settings(rt.schema, rt.messages, I18n.IsLocale),
				files = Files.new(raw),
				parse = parse,
				schema = rt.schema,
				log = rt.log:For("foundation", "config"),
				errors = rt.errors,
			})
		end
	end
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
		create_config = create_config,
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
	})
	runtime:Start()
	local native = {
		GetName = function()
			return "shop"
		end,
		GetTitle = function()
			return "Shop"
		end,
		Subscribe = function() end,
	}
	local context = runtime.packages:Register(native, { api = "0.1" })
	return runtime, context, raw, parsed, lines
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.line
	end
	return table.concat(parts, "\n")
end

describe("package configuration", function()
	local runtime, context, raw, parsed, lines, S

	before_each(function()
		runtime, context, raw, parsed, lines = setup()
		S = runtime.schema
	end)

	local function spec()
		return {
			fields = {
				{
					key = "limits.max_homes",
					schema = S:Integer({ min = 0 }),
					default = 3,
					reload = "hot",
					description = "Homes per player.",
				},
				{ key = "motd", schema = S:String(), default = "Welcome", description = "Shown on join." },
				{ key = "limits.cooldown", schema = S:Number({ min = 0 }), default = 1.5 },
				{ key = "database.password", schema = S:String(), default = "", secret = true },
			},
		}
	end

	it("creates the package file with root settings first, in declaration order", function()
		local settings = context:Config(spec())
		expect.equal(settings:GetPath(), "foundation/config/shop.toml")
		expect.equal(
			raw.contents["foundation/config/shop.toml"],
			table.concat({
				"# Settings of Shop (shop).",
				"# Read when the package starts. Delete this file to recreate it with the default values.",
				"",
				"# Format version of this file. Do not change it.",
				"config_version = 1",
				"",
				"# Shown on join.",
				'motd = "Welcome"',
				"",
				"[limits]",
				"# Homes per player.",
				"max_homes = 3",
				"",
				"cooldown = 1.5",
				"",
				"[database]",
				'password = ""',
				"",
			}, "\n")
		)
		expect.equal(settings:Get("limits.max_homes"), 3)
		expect.equal(settings:Get("motd"), "Welcome")
		expect.same(
			settings:Values(),
			{ motd = "Welcome", limits = { max_homes = 3, cooldown = 1.5 }, database = { password = "" } }
		)
	end)

	it("writes array defaults, including empty and nested ones", function()
		context:Config({
			fields = {
				{ key = "kits", schema = S:List(S:String()), default = { "starter", "vip" } },
				{ key = "banned", schema = S:List(S:String()), default = {} },
				{ key = "zones", schema = S:List(S:List(S:Integer())), default = { { 1, 2 }, { 3 } } },
			},
		})
		local written = raw.contents["foundation/config/shop.toml"]
		expect.contains(written, 'kits = ["starter", "vip"]')
		expect.contains(written, "banned = []")
		expect.contains(written, "zones = [[1, 2], [3]]")
	end)

	it("loads existing values and masks secrets in the snapshot", function()
		parsed.FILE = { limits = { max_homes = 7 }, database = { password = "hunter2-long" } }
		raw.contents["foundation/config/shop.toml"] = "FILE"
		local settings = context:Config(spec())
		expect.equal(settings:Get("limits.max_homes"), 7)
		expect.equal(settings:Get("database.password"), "hunter2-long")
		expect.equal(runtime:Snapshot().package_configs[1].values["database.password"], "***")
	end)

	it("returns copies so callers cannot change the settings", function()
		local settings =
			context:Config({ fields = { { key = "list", schema = S:List(S:String()), default = { "a" } } } })
		settings:Get("list")[1] = "changed"
		expect.equal(settings:Get("list")[1], "a")
	end)

	it("refuses unknown keys in Get", function()
		local settings = context:Config(spec())
		expect.raises(function()
			settings:Get("limits.unknown")
		end, "'limits.unknown' is not a declared setting")
		expect.raises(function()
			settings:Get("nosection.key")
		end, "is not a declared setting")
	end)

	describe("declaration checks", function()
		local function rejects(declaration, fragment)
			expect.raises(function()
				context:Config(declaration)
			end, fragment)
		end

		it("rejects malformed declarations", function()
			rejects({ fields = {} }, "'spec.fields' is invalid: must not be empty")
			rejects({ fields = {}, path = "x" }, "unknown field 'path'")
			rejects(
				{ fields = { { key = "a.b.c", schema = S:Any(), default = 1 } } },
				"must be '<name>' or '<section>.<name>'"
			)
			rejects(
				{ fields = { { key = "config_version", schema = S:Integer(), default = 1 } } },
				"'config_version' is reserved"
			)
			rejects({
				fields = { { key = "a", schema = S:Any(), default = 1 }, { key = "a", schema = S:Any(), default = 2 } },
			}, "'a' is declared twice")
			rejects({
				fields = {
					{ key = "log", schema = S:Any(), default = 1 },
					{ key = "log.level", schema = S:Any(), default = 2 },
				},
			}, "'log' is used both as a setting and as a section")
			rejects({
				fields = {
					{ key = "log.level", schema = S:Any(), default = 2 },
					{ key = "log", schema = S:Any(), default = 1 },
				},
			}, "'log' is used both as a setting and as a section")
			rejects(
				{ fields = { { key = "a", schema = "string", default = 1 } } },
				"'spec.fields[1].schema' must be schema"
			)
			rejects(
				{ fields = { { key = "a", schema = S:Integer({ max = 5 }), default = 9 } } },
				"the default value does not match its schema: $: must be at most 5"
			)
			rejects(
				{ fields = { { key = "a", schema = S:Map(S:String(), S:Integer()), default = { x = 1 } } } },
				"'spec.fields[1].default' is invalid: must be a string, number, boolean or an array"
			)
			rejects({
				fields = {
					{
						key = "a",
						schema = S:List(S:Record({ n = S:Integer() })),
						default = { { n = 1 } },
					},
				},
			}, "tables with named keys cannot be written")
			rejects(
				{ fields = { { key = "a", schema = S:Integer(), default = 1, reload = "live" } } },
				"expected one of hot, restart"
			)
			rejects(
				{ fields = { { key = "a", schema = S:Integer(), default = 1, label = "x" } } },
				"unknown field 'label'"
			)
		end)

		it("reports declaration errors at the package's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				context:Config({ fields = { { key = "a b", schema = S:Any(), default = 1 } } })
			end)
			expect.falsy(ok)
			expect.equal(tonumber(message:match("package_config_spec%.lua:(%d+):")), expected_line)
		end)

		it("allows one configuration per package", function()
			context:Config(spec())
			rejects(spec(), "'shop' already declared its configuration")
		end)
	end)

	describe("reload", function()
		local settings, notifications

		before_each(function()
			parsed.FILE = { motd = "One" }
			raw.contents["foundation/config/shop.toml"] = "FILE"
			settings = context:Config(spec())
			notifications = {}
			settings:OnChange(function(changed, values)
				notifications[#notifications + 1] = { changed = changed, max = values.limits.max_homes }
			end)
		end)

		it("applies hot settings and notifies the package", function()
			parsed.NEXT = { motd = "One", limits = { max_homes = 10 } }
			raw.contents["foundation/config/shop.toml"] = "NEXT"
			local report = runtime:ReloadConfig()
			expect.is_nil(report.core, "no Foundation file in this runtime")
			expect.same(report.packages.shop.changed, { "limits.max_homes" })
			expect.equal(settings:Get("limits.max_homes"), 10)
			expect.same(notifications, { { changed = { "limits.max_homes" }, max = 10 } })
		end)

		it("announces each reloaded file with foundation:config_reloaded", function()
			local announced = {}
			context:Listen("foundation:config_reloaded", function(event)
				announced[#announced + 1] = event:GetData()
			end)
			parsed.NEXT = { motd = "Two", limits = { max_homes = 10 } }
			raw.contents["foundation/config/shop.toml"] = "NEXT"
			runtime:ReloadConfig()
			expect.same(announced, {
				{
					package = "shop",
					path = "foundation/config/shop.toml",
					changed = { "limits.max_homes" },
					pending = { "motd" },
				},
			})
			raw.contents["foundation/config/shop.toml"] = "broken"
			runtime:ReloadConfig()
			expect.equal(#announced, 1)
		end)

		it("announces Foundation's own file first", function()
			local core_runtime, core_context, core_raw, core_parsed = setup(true)
			core_parsed.CORE = { language = "fr" }
			core_raw.contents["foundation/config.toml"] = "CORE"
			local announced = {}
			core_context:Listen("foundation:config_reloaded", function(event)
				announced[#announced + 1] = event:GetData()
			end)
			core_runtime:ReloadConfig()
			expect.same(announced, {
				{ package = "foundation", path = "foundation/config.toml", changed = { "language" }, pending = {} },
			})
		end)

		it("keeps restart-only settings and does not notify", function()
			parsed.NEXT = { motd = "Two" }
			raw.contents["foundation/config/shop.toml"] = "NEXT"
			runtime:ReloadConfig()
			expect.equal(settings:Get("motd"), "One")
			expect.same(notifications, {})
			expect.contains(
				text(lines),
				"'motd' changed in foundation/config/shop.toml; restart the server to apply it"
			)
		end)

		it("isolates a failing change hook", function()
			settings:OnChange(function()
				error("hook exploded")
			end)
			parsed.NEXT = { motd = "One", limits = { max_homes = 4 } }
			raw.contents["foundation/config/shop.toml"] = "NEXT"
			expect.no_error(function()
				runtime:ReloadConfig()
			end)
			expect.contains(text(lines), "config_hook callback of shop failed")
			expect.equal(#notifications, 1)
		end)
	end)

	it("stops serving settings when the package is disabled but keeps the file", function()
		local settings = context:Config(spec())
		runtime.packages:Disable("shop", "unload")
		expect.raises(function()
			settings:Get("motd")
		end, "the context of 'shop' is disabled")
		expect.truthy(raw.contents["foundation/config/shop.toml"])
		expect.same(runtime:Snapshot().package_configs, {})
		expect.no_error(function()
			runtime:ReloadConfig()
		end)
	end)
end)
