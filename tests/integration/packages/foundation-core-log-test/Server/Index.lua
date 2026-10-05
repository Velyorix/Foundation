-- The resulting console lines are checked by the runner (suites.json, expected_log_lines).

local Messages = Package.Require("foundation/Shared/foundation/core/messages.lua")
local Log = Package.Require("foundation/Shared/foundation/core/log.lua")
local en = Package.Require("foundation/Shared/foundation/locales/en/core.lua")

local suite = FoundationTest.Suite("core-log")

local catalog = { ["test.percent"] = "progress 100% done {value}", ["test.plain"] = "core-log marker" }
for key, value in pairs(en) do
	catalog[key] = value
end

local logger = Log.new({
	sink = Log.console_sink(Console),
	messages = Messages.new({ en = catalog }),
	clock = function()
		return Server.GetTime() / 1000
	end,
	level = "debug",
})

suite:Test("writes every level through the console", function()
	logger:For("foundation-core-log-test", "levels"):Debug("test.plain", nil, { level = "debug" })
	logger:For("foundation-core-log-test", "levels"):Info("test.plain", nil, { level = "info" })
	logger:For("foundation-core-log-test", "levels"):Warning("test.plain", nil, { level = "warning" })
	logger:For("foundation-core-log-test", "levels"):Error("test.plain", nil, { level = "error" })
end)

suite:Test("keeps percent signs and masks secrets", function()
	logger:RegisterSecret("integration-secret")
	logger:Info("test.percent", { value = "%s %d" }, { note = "integration-secret", password = "abc" })
end)

suite:Test("suppresses repeats and reports them on flush", function()
	local repeated = logger:For("foundation-core-log-test", "repeat")
	for _ = 1, 3 do
		repeated:Info("test.plain")
	end
	logger:Flush()
end)

suite:Run()
