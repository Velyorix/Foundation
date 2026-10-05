-- Search order of Package.Require: current file, <side>/, Shared/, package root.

local Loader = {}
Loader.__index = Loader

local STANDARD_GLOBALS = {
	"assert",
	"collectgarbage",
	"error",
	"getmetatable",
	"ipairs",
	"load",
	"next",
	"pairs",
	"pcall",
	"print",
	"rawequal",
	"rawget",
	"rawlen",
	"rawset",
	"select",
	"setmetatable",
	"tonumber",
	"tostring",
	"type",
	"xpcall",
	"_VERSION",
	"coroutine",
	"debug",
	"math",
	"string",
	"table",
	"utf8",
}

local function normalize(path)
	path = path:gsub("\\", "/")
	local parts = {}
	for segment in path:gmatch("[^/]+") do
		if segment == ".." then
			if #parts == 0 or parts[#parts] == ".." then
				parts[#parts + 1] = ".."
			else
				parts[#parts] = nil
			end
		elseif segment ~= "." then
			parts[#parts + 1] = segment
		end
	end
	local prefix = path:sub(1, 1) == "/" and "/" or ""
	return prefix .. table.concat(parts, "/")
end

local function directory_of(path)
	return path:match("^(.*)/[^/]*$") or "."
end

local function file_exists(path)
	local handle = io.open(path, "rb")
	if handle then
		handle:close()
		return true
	end
	return false
end

local function read_file(path)
	local handle = assert(io.open(path, "rb"))
	local content = handle:read("a")
	handle:close()
	return content
end

function Loader.new(options)
	options = options or {}
	local self = setmetatable({
		root = normalize(options.root or "package"),
		side = options.side or "Server",
		name = options.name or "foundation",
		cache = {},
		stack = {},
		loaded_order = {},
	}, Loader)

	local env = {}
	for _, name in ipairs(STANDARD_GLOBALS) do
		env[name] = _G[name]
	end
	env.os = { clock = os.clock, time = os.time, date = os.date, difftime = os.difftime }
	env._G = env

	local package_api = {}
	for key, value in pairs(options.package or {}) do
		package_api[key] = value
	end
	package_api.Require = function(path, force_load)
		return self:require(path, force_load)
	end
	if package_api.GetName == nil then
		package_api.GetName = function()
			return self.name
		end
	end
	env.Package = package_api

	for key, value in pairs(options.globals or {}) do
		env[key] = value
	end

	self.env = env
	return self
end

function Loader:resolve(path)
	if type(path) ~= "string" or path == "" then
		error("Package.Require expects a non-empty string path", 3)
	end
	local candidates = {}
	local current = self.stack[#self.stack]
	if current then
		candidates[#candidates + 1] = directory_of(current) .. "/" .. path
	end
	candidates[#candidates + 1] = self.root .. "/" .. self.side .. "/" .. path
	candidates[#candidates + 1] = self.root .. "/Shared/" .. path
	candidates[#candidates + 1] = self.root .. "/" .. path
	for _, candidate in ipairs(candidates) do
		local resolved = normalize(candidate)
		if file_exists(resolved) then
			return resolved
		end
	end
	return nil
end

function Loader:require(path, force_load)
	local resolved = self:resolve(path)
	if not resolved then
		error(
			string.format("Package.Require: file '%s' not found from '%s'", path, self.stack[#self.stack] or self.root),
			2
		)
	end
	local cached = self.cache[resolved]
	if cached and not force_load then
		return table.unpack(cached, 1, cached.n)
	end
	local chunk, compile_error = load(read_file(resolved), "@" .. resolved, "t", self.env)
	if not chunk then
		error(compile_error, 0)
	end
	self.stack[#self.stack + 1] = resolved
	local results = table.pack(xpcall(chunk, debug.traceback))
	self.stack[#self.stack] = nil
	if not results[1] then
		error(results[2], 0)
	end
	local values = table.pack(table.unpack(results, 2, results.n))
	self.cache[resolved] = values
	self.loaded_order[#self.loaded_order + 1] = resolved
	return table.unpack(values, 1, values.n)
end

function Loader:run(path)
	return self:require(path, true)
end

Loader.normalize = normalize

return Loader
