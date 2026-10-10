local Keys = Package.Require("keys.lua")
local Schema = Package.Require("schema.lua")

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

	local schema = runtime.schema
	api.Schema = read_only(runtime, "Foundation.Schema", {
		String = function(options)
			return schema:String(options)
		end,
		Number = function(options)
			return schema:Number(options)
		end,
		Integer = function(options)
			return schema:Integer(options)
		end,
		Boolean = function()
			return schema:Boolean()
		end,
		Any = function()
			return schema:Any()
		end,
		Enum = function(values)
			return schema:Enum(values)
		end,
		Optional = function(inner, default)
			return schema:Optional(inner, default)
		end,
		Record = function(fields, options)
			return schema:Record(fields, options)
		end,
		List = function(inner, options)
			return schema:List(inner, options)
		end,
		Map = function(key_schema, value_schema, options)
			return schema:Map(key_schema, value_schema, options)
		end,
		Custom = function(key, fn)
			return schema:Custom(key, fn)
		end,
		Validate = function(target, value, limits)
			return schema:Validate(target, value, limits)
		end,
		IsSchema = Schema.IsSchema,
	})

	local capabilities = runtime.capabilities
	api.Capabilities = read_only(runtime, "Foundation.Capabilities", {
		Has = function(name, version)
			return capabilities:Has(name, version)
		end,
		Providers = function(name, version)
			return capabilities:Providers(name, version)
		end,
	})

	return read_only(runtime, "Foundation", api)
end

return Facade
