local Keys = Package.Require("keys.lua")

local Facade = {}

local function read_only(runtime, name, fields)
	return setmetatable({}, {
		__index = fields,
		__newindex = function(_, key)
			runtime.errors:Raise("invalid_state", {
				api = name .. "." .. tostring(key),
				reason = runtime.messages:Format("reason.read_only", { name = name }),
			})
		end,
		__metatable = false,
	})
end

function Facade.new(runtime)
	local api = {
		VERSION = runtime.env.version,
		API_VERSION = runtime.env.api_version,
	}

	-- Tail calls keep error levels inside the callee pointing at the package's code.
	function api.Register(package, manifest)
		runtime:RequireRunning("Foundation.Register")
		return runtime.packages:Register(package, manifest)
	end

	api.Keys = read_only(runtime, "Foundation.Keys", {
		Parse = function(text, default_namespace)
			return runtime.keys:Parse(text, default_namespace)
		end,
		Split = Keys.Split,
		IsReserved = Keys.IsReserved,
	})

	return read_only(runtime, "Foundation", api)
end

return Facade
