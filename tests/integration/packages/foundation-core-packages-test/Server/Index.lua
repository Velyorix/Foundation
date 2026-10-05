local Messages = Package.Require("foundation/Shared/foundation/core/messages.lua")
local Errors = Package.Require("foundation/Shared/foundation/core/errors.lua")
local Check = Package.Require("foundation/Shared/foundation/core/check.lua")
local Log = Package.Require("foundation/Shared/foundation/core/log.lua")
local Ownership = Package.Require("foundation/Shared/foundation/core/ownership.lua")
local Invoker = Package.Require("foundation/Shared/foundation/core/invoke.lua")
local Registry = Package.Require("foundation/Shared/foundation/core/packages.lua")
local en = Package.Require("foundation/Shared/foundation/locales/en/core.lua")

local FIXTURE = "foundation-packages-fixture"

local messages = Messages.new({ en = en })
local check = Check.new(Errors.new(messages))
local log = Log.new({
	sink = Log.console_sink(Console),
	messages = messages,
	clock = function()
		return Server.GetTime() / 1000
	end,
})
local invoker = Invoker.new({ log = log, side = "server" })
local ownership = Ownership.new({ check = check, invoker = invoker })
local registry =
	Registry.new({ check = check, log = log, ownership = ownership, invoker = invoker, api_version = "0.1" })

local probe = { registry = registry, events = {}, contexts = {} }
Package.Export("PackagesProbe", probe)

local function events_text()
	return table.concat(probe.events, ",")
end

local suite = FoundationTest.Suite("core-packages")

suite:Test("fixture is ready once the server has started", function()
	FoundationTest.Equal(registry:State(FIXTURE), "ready")
	FoundationTest.Equal(events_text(), "registered,ready")
	FoundationTest.Equal(ownership:Count(FIXTURE), 1)
end)

suite:Do(function()
	Server.ReloadPackage(FIXTURE)
end)
suite:Wait(500)

suite:Test("reload disables the old registration and accepts a new one", function()
	FoundationTest.Equal(events_text(), "registered,ready,disabled,released,registered,ready")
	FoundationTest.Equal(#probe.contexts, 2)
	FoundationTest.Equal(probe.contexts[1]:GetState(), "disabled")
	FoundationTest.Raises(function()
		probe.contexts[1]:Track("late", function() end)
	end, "can no longer be used")
	FoundationTest.Equal(probe.contexts[2]:GetState(), "ready")
	FoundationTest.Equal(ownership:Count(FIXTURE), 1)
end)

suite:Do(function()
	Server.UnloadPackage(FIXTURE)
end)
suite:Wait(500)

suite:Test("unload disables the package and releases its resources", function()
	FoundationTest.Equal(events_text(), "registered,ready,disabled,released,registered,ready,disabled,released")
	FoundationTest.Equal(registry:State(FIXTURE), "disabled")
	FoundationTest.Equal(ownership:Count(FIXTURE), 0)
	FoundationTest.Equal(Server.IsPackageLoaded(FIXTURE), false)
end)

suite:Run()
