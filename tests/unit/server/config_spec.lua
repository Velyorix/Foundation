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
				return raw.fail_write == true
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

local function setup(options)
	options = options or {}
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Check = loader:require("foundation/core/check.lua")
	local Keys = loader:require("foundation/core/keys.lua")
	local Log = loader:require("foundation/core/log.lua")
	local Invoker = loader:require("foundation/core/invoke.lua")
	local Schema = loader:require("foundation/core/schema.lua")
	local Files = loader:require("foundation/core/files.lua")
	local Config = loader:require("foundation/core/config.lua")
	local catalog = loader:require("foundation/locales/en/core.lua")
	catalog["test.header"] = "Test settings."
	catalog["test.motd"] = "Message of the day.\nShown on join."
	catalog["test.slots"] = "Reserved slots."
	catalog["test.token"] = "API token."
	local messages = Messages.new({ en = catalog })
	local errors = Errors.new(messages)
	local lines = {}
	local log = Log.new({
		sink = function(level, line)
			lines[#lines + 1] = { level = level, line = line }
		end,
		messages = messages,
		clock = function()
			return 0
		end,
		repeat_window = 0,
	})
	local S = Schema.new({
		errors = errors,
		check = Check.new(errors),
		keys = Keys.new(errors),
		invoker = Invoker.new({ log = log, side = "server" }),
	})
	local raw = memory_files()
	local parsed = options.parsed or {}
	local spec = {
		path = "foundation/test.toml",
		version = options.version or 1,
		migrations = options.migrations,
		header_key = "test.header",
		sections = {
			{
				fields = {
					{
						key = "motd",
						schema = S:String({ max = 64 }),
						default = 'Hi "all"',
						reload = "hot",
						comment_key = "test.motd",
					},
				},
			},
			{
				name = "server",
				fields = {
					{
						key = "slots",
						schema = S:Integer({ min = 0 }),
						default = 2,
						reload = "restart",
						comment_key = "test.slots",
					},
					{
						key = "token",
						schema = S:String(),
						default = "",
						reload = "hot",
						secret = true,
						comment_key = "test.token",
					},
				},
			},
		},
	}
	local config = Config.new({
		spec = spec,
		files = Files.new(raw),
		parse = function(text)
			local data = parsed[text]
			if data == nil then
				error("bad format: unknown value appeared")
			end
			return data
		end,
		schema = S,
		log = log,
		errors = errors,
	})
	return config, raw, lines, parsed, Errors
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.level .. " " .. entry.line
	end
	return table.concat(parts, "\n")
end

describe("Config", function()
	it("writes a commented template when the file is missing and uses the defaults", function()
		local config, raw, lines = setup()
		local values = config:Load()
		expect.same(values, { motd = 'Hi "all"', server = { slots = 2, token = "" } })
		expect.equal(
			raw.contents["foundation/test.toml"],
			table.concat({
				"# Test settings.",
				"",
				"# Format version of this file. Do not change it.",
				"config_version = 1",
				"",
				"# Message of the day.",
				"# Shown on join.",
				'motd = "Hi \\"all\\""',
				"",
				"[server]",
				"# Reserved slots.",
				"slots = 2",
				"",
				"# API token.",
				'token = ""',
				"",
			}, "\n")
		)
		expect.truthy(raw.directories["foundation"])
		expect.is_nil(raw.contents["foundation/test.tmp.toml"], "temporary file renamed")
		expect.contains(text(lines), "info [foundation] INFO  foundation/core: created foundation/test.toml")
		expect.equal(config:Snapshot().state, "loaded")
	end)

	it("loads a valid file and fills missing settings with defaults", function()
		local config, raw =
			setup({ parsed = { FILE = { config_version = 1, motd = "Welcome", server = { slots = 5 } } } })
		raw.contents["foundation/test.toml"] = "FILE"
		expect.same(config:Load(), { motd = "Welcome", server = { slots = 5, token = "" } })
	end)

	it("uses the defaults and reports every problem when the file is invalid", function()
		local config, raw, lines = setup({
			parsed = { FILE = { motd = 5, server = { slots = -1 }, unknown = true } },
		})
		raw.contents["foundation/test.toml"] = "FILE"
		local values = config:Load()
		expect.same(values, { motd = 'Hi "all"', server = { slots = 2, token = "" } })
		local output = text(lines)
		expect.contains(output, "foundation/test.toml is invalid (3 problem(s))")
		expect.contains(output, "foundation/test.toml: $.motd: expected string, got integer")
		expect.contains(output, "foundation/test.toml: $.server.slots: must be at least 0")
		expect.contains(output, "foundation/test.toml: $.unknown: is not an allowed field")
		expect.contains(output, "Foundation runs with the default settings until the file is fixed")
		expect.equal(config:Snapshot().state, "invalid")
		expect.equal(config:Snapshot().problems, 3)
		expect.equal(raw.contents["foundation/test.toml"], "FILE", "an invalid file is never rewritten")
	end)

	it("reports unparseable files", function()
		local config, raw, lines = setup()
		raw.contents["foundation/test.toml"] = "not toml"
		config:Load()
		expect.contains(text(lines), "could not read foundation/test.toml: ")
		expect.contains(text(lines), "bad format")
	end)

	describe("versions", function()
		it("refuses files from a newer format", function()
			local config, raw, lines = setup({ parsed = { FILE = { config_version = 2 } } })
			raw.contents["foundation/test.toml"] = "FILE"
			config:Load()
			expect.contains(text(lines), "has config_version 2; this version of Foundation supports 1 to 1")
		end)

		it("migrates older files in memory without rewriting them", function()
			local config, raw, lines = setup({
				version = 2,
				migrations = {
					[1] = function(data)
						data.motd = data.welcome
						data.welcome = nil
						return data
					end,
				},
				parsed = { FILE = { config_version = 1, welcome = "Old" } },
			})
			raw.contents["foundation/test.toml"] = "FILE"
			expect.equal(config:Load().motd, "Old")
			expect.contains(text(lines), "uses config_version 1; it was converted to version 2 in memory")
			expect.equal(raw.contents["foundation/test.toml"], "FILE")
		end)

		it("reports missing and failing migrations", function()
			local missing, raw_missing, missing_lines =
				setup({ version = 2, parsed = { FILE = { config_version = 1 } } })
			raw_missing.contents["foundation/test.toml"] = "FILE"
			missing:Load()
			expect.contains(text(missing_lines), "no migration from config_version 1")

			local failing, raw_failing, failing_lines = setup({
				version = 2,
				migrations = {
					[1] = function()
						error("cannot convert")
					end,
				},
				parsed = { FILE = { config_version = 1 } },
			})
			raw_failing.contents["foundation/test.toml"] = "FILE"
			failing:Load()
			expect.contains(text(failing_lines), "migration from config_version 1 failed")
			expect.contains(text(failing_lines), "cannot convert")
		end)
	end)

	describe("Reload", function()
		local config, raw, lines, parsed

		before_each(function()
			config, raw, lines, parsed = setup({ parsed = { FILE = { motd = "One", server = { slots = 2 } } } })
			raw.contents["foundation/test.toml"] = "FILE"
			config:Load()
		end)

		it("applies hot settings and reports what changed", function()
			parsed.NEXT = { motd = "Two", server = { slots = 2 } }
			raw.contents["foundation/test.toml"] = "NEXT"
			local changed, pending = config:Reload()
			expect.same(changed, { "motd" })
			expect.same(pending, {})
			expect.equal(config:Values().motd, "Two")
			expect.contains(text(lines), "configuration reloaded (1 setting changed)")
		end)

		it("keeps restart-only settings until restart and says so", function()
			parsed.NEXT = { motd = "One", server = { slots = 9 } }
			raw.contents["foundation/test.toml"] = "NEXT"
			local changed, pending = config:Reload()
			expect.same(changed, {})
			expect.same(pending, { "server.slots" })
			expect.equal(config:Values().server.slots, 2)
			expect.contains(
				text(lines),
				"'server.slots' changed in foundation/test.toml; restart the server to apply it"
			)
			expect.same(config:Snapshot().pending_restart, { "server.slots" })
		end)

		it("rejects an invalid candidate and keeps the current values", function()
			parsed.NEXT = { motd = "Two", server = { slots = "many" } }
			raw.contents["foundation/test.toml"] = "NEXT"
			local changed, err = config:Reload()
			expect.is_nil(changed)
			expect.equal(err.code, "config_invalid")
			expect.equal(err.category, "configuration")
			expect.equal(#err.details.problems, 1)
			expect.equal(config:Values().motd, "One", "nothing applied from a rejected file")
			expect.contains(
				text(lines),
				"configuration reload rejected; the current settings of foundation/test.toml are kept"
			)
		end)
	end)

	it("masks secret settings in logs and snapshots", function()
		local config, raw, lines = setup({ parsed = { FILE = { server = { token = "s3cr3t-token" } } } })
		raw.contents["foundation/test.toml"] = "FILE"
		config:Load()
		expect.equal(config:Snapshot().values["server.token"], "***")
		expect.equal(config:Values().server.token, "s3cr3t-token")
		config.log:Info("test.motd", nil, { value = "uses s3cr3t-token" })
		expect.falsy(text(lines):find("s3cr3t-token", 1, true))
	end)

	it("falls back to the defaults when the template cannot be written", function()
		local config, raw, lines = setup()
		raw.fail_write = true
		local values = config:Load()
		expect.equal(values.server.slots, 2)
		expect.contains(text(lines), "could not create foundation/test.toml")
		expect.equal(config:Snapshot().state, "invalid")
	end)
end)
