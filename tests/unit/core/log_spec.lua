local function setup(options)
	options = options or {}
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Log = loader:require("foundation/core/log.lua")
	local catalogs = {
		en = loader:require("foundation/locales/en/core.lua"),
		fr = loader:require("foundation/locales/fr/core.lua"),
	}
	catalogs.en["test.hello"] = "Hello {name}"
	catalogs.en["test.plain"] = "plain message"
	local state = { now = 0, lines = {} }
	local logger = Log.new({
		sink = function(level, line)
			state.lines[#state.lines + 1] = { level = level, line = line }
		end,
		messages = Messages.new(catalogs, options.locale or "en"),
		clock = function()
			return state.now
		end,
		level = options.level,
		repeat_window = options.repeat_window,
	})
	return logger, state, Log
end

local function last_line(state)
	local entry = state.lines[#state.lines]
	return entry and entry.line
end

describe("Log", function()
	describe("format", function()
		it("writes owner, domain, level and the rendered message", function()
			local logger, state = setup()
			logger:Info("test.hello", { name = "Ana" })
			expect.equal(last_line(state), "[foundation] INFO  foundation/core: Hello Ana")
			expect.equal(state.lines[1].level, "info")
		end)

		it("appends fields sorted by name and quotes values that need it", function()
			local logger, state = setup()
			logger:Warning("test.plain", nil, { zeta = 1, alpha = "two words", eq = "a=b", empty = "" })
			expect.equal(
				last_line(state),
				'[foundation] WARN  foundation/core: plain message alpha="two words" empty="" eq="a=b" zeta=1'
			)
		end)

		it("writes a trace on the following lines", function()
			local logger, state = setup()
			logger:Error("test.plain", nil, { trace = "stack traceback:\n\tline 1", code = "x" })
			expect.equal(
				last_line(state),
				"[foundation] ERROR foundation/core: plain message code=x\nstack traceback:\n\tline 1"
			)
		end)

		it("escapes newlines inside field values so a record stays on one line", function()
			local logger, state = setup()
			logger:Info("test.plain", nil, { value = "a\nb" })
			expect.equal(last_line(state), '[foundation] INFO  foundation/core: plain message value="a\\nb"')
		end)

		it("renders the message in the active locale", function()
			local logger, state = setup({ locale = "fr" })
			logger:Info("log.repeated", { count = 2 })
			expect.equal(
				last_line(state),
				"[foundation] INFO  foundation/core: message précédent répété 2 fois de plus"
			)
		end)

		it("uses the owner and domain of derived loggers", function()
			local logger, state = setup()
			local child = logger:For("my-package", "storage")
			child:Info("test.plain")
			expect.equal(last_line(state), "[foundation] INFO  my-package/storage: plain message")
			expect.equal(child:GetOwner(), "my-package")
			expect.equal(child:For(nil, "events"):GetOwner(), "my-package")
		end)
	end)

	describe("levels", function()
		it("drops records below the minimum level", function()
			local logger, state = setup({ level = "warning" })
			logger:Debug("test.plain")
			logger:Info("test.plain")
			logger:Warning("test.plain")
			logger:Error("test.plain")
			expect.equal(#state.lines, 2)
		end)

		it("shares the level across derived loggers", function()
			local logger, state = setup()
			local child = logger:For("pkg", "x")
			expect.truthy(logger:SetLevel("error"))
			child:Warning("test.plain")
			expect.equal(#state.lines, 0)
			expect.equal(child:GetLevel(), "error")
		end)

		it("rejects unknown levels without changing the configuration", function()
			local logger = setup()
			expect.falsy(logger:SetLevel("verbose"))
			expect.equal(logger:GetLevel(), "info")
		end)

		it("enables debug output per domain", function()
			local logger, state = setup()
			local storage = logger:For(nil, "storage")
			local events = logger:For(nil, "events")
			logger:EnableDebugCategory("storage")
			storage:Debug("test.plain")
			events:Debug("test.plain")
			expect.equal(#state.lines, 1)
			expect.contains(last_line(state), "DEBUG foundation/storage")
			logger:DisableDebugCategory("storage")
			storage:Debug("test.hello", { name = "again" })
			expect.equal(#state.lines, 1)
		end)
	end)

	describe("secret masking", function()
		it("masks fields with sensitive names", function()
			local logger, state = setup()
			logger:Info("test.plain", nil, { db_password = "hunter22", api_key = "k", auth_token = "t", user = "ana" })
			local line = last_line(state)
			expect.contains(line, "db_password=***")
			expect.contains(line, "api_key=***")
			expect.contains(line, "auth_token=***")
			expect.contains(line, "user=ana")
			expect.falsy(line:find("hunter22", 1, true))
		end)

		it("masks registered secret values anywhere in the line, including message and trace", function()
			local logger, state = setup()
			logger:RegisterSecret("s3cr%t.value")
			logger:Error(
				"test.hello",
				{ name = "s3cr%t.value" },
				{ detail = "x s3cr%t.value y", trace = "at s3cr%t.value" }
			)
			local line = last_line(state)
			expect.falsy(line:find("s3cr%t.value", 1, true), line)
			expect.contains(line, "Hello ***")
			expect.contains(line, "at ***")
		end)

		it("ignores very short secrets", function()
			local logger, state = setup()
			logger:RegisterSecret("ab")
			logger:Info("test.hello", { name = "ab" })
			expect.contains(last_line(state), "Hello ab")
		end)
	end)

	describe("repeat suppression", function()
		it("writes identical lines once per window and reports the suppressed count", function()
			local logger, state = setup({ repeat_window = 10 })
			for _ = 1, 4 do
				logger:Warning("test.plain")
			end
			expect.equal(#state.lines, 1)
			state.now = 11
			logger:Warning("test.plain")
			expect.equal(#state.lines, 3)
			expect.equal(
				state.lines[2].line,
				"[foundation] WARN  foundation/core: previous message repeated 3 more time(s)"
			)
			expect.equal(state.lines[2].level, "warning")
			expect.equal(state.lines[3].line, "[foundation] WARN  foundation/core: plain message")
		end)

		it("does not suppress lines that differ", function()
			local logger, state = setup()
			logger:Warning("test.hello", { name = "a" })
			logger:Warning("test.hello", { name = "b" })
			logger:For("other", "core"):Warning("test.hello", { name = "a" })
			expect.equal(#state.lines, 3)
		end)

		it("reports pending repeats on Flush", function()
			local logger, state = setup()
			logger:Warning("test.plain")
			logger:Warning("test.plain")
			logger:Flush()
			expect.equal(#state.lines, 2)
			expect.contains(state.lines[2].line, "repeated 1 more time(s)")
			logger:Warning("test.plain")
			expect.equal(#state.lines, 3, "tracking restarts after Flush")
		end)

		it("never suppresses info and debug lines", function()
			local logger, state = setup({ level = "debug" })
			logger:Info("test.plain")
			logger:Info("test.plain")
			logger:Debug("test.plain")
			logger:Debug("test.plain")
			expect.equal(#state.lines, 4)
		end)

		it("can be disabled", function()
			local logger, state = setup({ repeat_window = 0 })
			logger:Warning("test.plain")
			logger:Warning("test.plain")
			expect.equal(#state.lines, 2)
		end)

		it("bounds the number of tracked lines", function()
			local logger, state = setup()
			for index = 1, 300 do
				logger:Warning("test.hello", { name = index })
			end
			expect.equal(#state.lines, 300)
			logger:Warning("test.hello", { name = 300 })
			expect.equal(#state.lines, 300, "recent line still tracked after eviction")
		end)
	end)

	describe("console sink", function()
		it("maps levels to Console functions and passes the line as a format argument", function()
			local _, _, Log = setup()
			local calls = {}
			local function recorder(name)
				return function(...)
					calls[#calls + 1] = { name, ... }
				end
			end
			local sink = Log.console_sink({ Log = recorder("Log"), Warn = recorder("Warn"), Error = recorder("Error") })
			sink("debug", "100% d")
			sink("info", "i")
			sink("warning", "w")
			sink("error", "e")
			expect.same(calls, {
				{ "Log", "%s", "100% d" },
				{ "Log", "%s", "i" },
				{ "Warn", "%s", "w" },
				{ "Error", "%s", "e" },
			})
		end)
	end)
end)
