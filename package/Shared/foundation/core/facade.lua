local Facade = {}

function Facade.new(runtime)
	local api = {
		VERSION = runtime.env.version,
		API_VERSION = runtime.env.api_version,
	}

	function api.Register(package, manifest)
		runtime:RequireRunning("Foundation.Register")
		-- Tail call keeps error levels inside Register pointing at the package's code.
		return runtime.packages:Register(package, manifest)
	end

	return setmetatable({}, {
		__index = api,
		__newindex = function(_, key)
			runtime.errors:Raise("invalid_state", {
				api = "Foundation." .. tostring(key),
				reason = runtime.messages:Format("reason.read_only"),
			})
		end,
		__metatable = false,
	})
end

return Facade
