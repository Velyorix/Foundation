local function fake_engine()
	local engine = { lines = {}, exports = {}, server_events = {}, package_events = {}, time = 1759679465000 }
	local function writer(level)
		return function(format, line)
			engine.lines[#engine.lines + 1] = { level = level, line = string.format(format, line) }
		end
	end
	engine.Console = { Log = writer("log"), Warn = writer("warn"), Error = writer("error") }
	engine.Server = {
		GetTime = function()
			return engine.time
		end,
		Subscribe = function(event, callback)
			engine.server_events[event] = callback
		end,
	}
	engine.File = setmetatable({
		Exists = function()
			return false
		end,
		CreateDirectory = function()
			return true
		end,
		IsDirectory = function()
			return true
		end,
	}, {
		__call = function()
			error("no file system in unit tests")
		end,
	})
	engine.package = {
		Export = function(name, value)
			engine.exports[name] = value
		end,
		Subscribe = function(event, callback)
			engine.package_events[event] = callback
		end,
	}
	return engine
end

local function boot()
	local engine = fake_engine()
	local loader = Loader.new({
		side = "Server",
		globals = { Console = engine.Console, Server = engine.Server, File = engine.File },
		package = engine.package,
	})
	loader:run("../Shared/Index.lua")
	loader:run("Index.lua")
	return engine
end

local function dependent(name)
	local package = { events = {} }
	function package.GetName()
		return name
	end
	function package.Subscribe(event, callback)
		package.events[event] = callback
	end
	return package
end

local function text(engine)
	local parts = {}
	for index, entry in ipairs(engine.lines) do
		parts[index] = entry.level .. " " .. entry.line
	end
	return table.concat(parts, "\n")
end

describe("server bootstrap", function()
	it("exports a running Foundation with the package versions", function()
		local engine = boot()
		local foundation = engine.exports.Foundation
		local version = Loader.new():require("foundation/version.lua")
		expect.truthy(foundation)
		expect.equal(foundation.VERSION, version.PRODUCT)
		expect.equal(foundation.API_VERSION, version.API)
		expect.contains(
			text(engine),
			"log [foundation] INFO  foundation/core: Foundation " .. version.PRODUCT .. " started"
		)
	end)

	it("lets packages register and become ready", function()
		local engine = boot()
		local native = dependent("my-package")
		local context = engine.exports.Foundation.Register(native, { api = engine.exports.Foundation.API_VERSION })
		native.events.Load()
		expect.equal(context:GetState(), "ready")
	end)

	it("stops quietly when the server stops", function()
		local engine = boot()
		local native = dependent("my-package")
		engine.exports.Foundation.Register(native, { api = engine.exports.Foundation.API_VERSION })
		engine.server_events.Stop()
		engine.package_events.Unload()
		local output = text(engine)
		expect.contains(output, "my-package disabled: Foundation is stopping")
		expect.contains(output, "Foundation stopped")
		expect.falsy(output:find("was unloaded while", 1, true))
	end)

	it("warns with a recovery command when Foundation is unloaded alone", function()
		local engine = boot()
		for _, name in ipairs({ "alpha", "beta" }) do
			engine.exports.Foundation.Register(dependent(name), { api = engine.exports.Foundation.API_VERSION })
		end
		engine.package_events.Unload()
		local output = text(engine)
		expect.contains(
			output,
			"warn [foundation] WARN  foundation/core: Foundation was unloaded while 2 package(s) still use it (alpha, beta)"
		)
		expect.contains(output, "Run 'package reload alpha beta' or restart the server")
		expect.raises(function()
			engine.exports.Foundation.Register(dependent("late"), { api = engine.exports.Foundation.API_VERSION })
		end, "Foundation is not running (state: stopped)")
	end)

	it("does not warn when no package uses Foundation", function()
		local engine = boot()
		engine.package_events.Unload()
		expect.falsy(text(engine):find("was unloaded while", 1, true))
	end)
end)
