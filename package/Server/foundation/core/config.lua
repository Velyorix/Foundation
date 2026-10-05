local Sensitive = Package.Require("../../../Shared/foundation/core/sensitive.lua")

local Config = {}
Config.__index = Config

local TOML_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }

local function toml_value(value)
	local kind = type(value)
	if kind == "string" then
		return '"'
			.. value:gsub('[%c"\\]', function(char)
				return TOML_ESCAPES[char] or string.format("\\u%04X", char:byte())
			end)
			.. '"'
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif math.type(value) == "integer" then
		return string.format("%d", value)
	elseif kind == "number" then
		local text = string.format("%.17g", value)
		return text:find("[%.eE]") and text or (text .. ".0")
	end
	local items = {}
	for index, item in ipairs(value) do
		items[index] = toml_value(item)
	end
	return "[" .. table.concat(items, ", ") .. "]"
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in pairs(value) do
		result[key] = copy(item)
	end
	return result
end

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- spec: { path, version, migrations = { [from] = fn(data) -> data }, header_key or header,
--         sections = { { name = nil|"section", fields = { { key, schema, default,
--         reload = "hot"|"restart", secret, comment_key or comment } } } } }
-- options: spec, files (core/files.lua), parse (TOML text -> table, raises), schema,
--          log, errors
function Config.new(options)
	local self = setmetatable({
		spec = options.spec,
		files = options.files,
		parse = options.parse,
		S = options.schema,
		log = options.log,
		errors = options.errors,
		messages = options.errors.messages,
		state = "unloaded",
		pending_restart = {},
	}, Config)
	self.fields = {}
	local root = { config_version = self.S:Optional(self.S:Integer({ min = 1 })) }
	for _, section in ipairs(self.spec.sections) do
		local target = root
		if section.name then
			target = {}
		end
		for _, field in ipairs(section.fields) do
			field.path = section.name and (section.name .. "." .. field.key) or field.key
			field.section = section.name
			target[field.key] = self.S:Optional(field.schema, field.default)
			self.fields[#self.fields + 1] = field
		end
		if section.name then
			root[section.name] = self.S:Optional(self.S:Record(target), {})
		end
	end
	self.record = self.S:Record(root)
	self.defaults = self:validate({})
	self.values = copy(self.defaults)
	return self
end

function Config:validate(data)
	local values, err = self.S:Validate(self.record, data)
	if values then
		values.config_version = nil
		for _, section in ipairs(self.spec.sections) do
			if section.name and values[section.name] == nil then
				values[section.name] = {}
			end
		end
		for _, field in ipairs(self.fields) do
			local holder = field.section and values[field.section] or values
			if holder[field.key] == nil then
				holder[field.key] = copy(field.default)
			end
		end
	end
	return values, err
end

function Config:get_path(values, field)
	local holder = field.section and values[field.section] or values
	return holder[field.key]
end

function Config:set_path(values, field, value)
	local holder = field.section and values[field.section] or values
	holder[field.key] = copy(value)
end

function Config:Template()
	local lines = {}
	local function comment(text)
		for line in (text or ""):gmatch("[^\n]+") do
			lines[#lines + 1] = "# " .. line
		end
	end
	comment(self.spec.header or self.messages:Format(self.spec.header_key))
	lines[#lines + 1] = ""
	comment(self.messages:Format("config.template.version"))
	lines[#lines + 1] = "config_version = " .. self.spec.version
	for _, section in ipairs(self.spec.sections) do
		if section.name then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "[" .. section.name .. "]"
		end
		for index, field in ipairs(section.fields) do
			if not (section.name and index == 1) then
				lines[#lines + 1] = ""
			end
			comment(field.comment or (field.comment_key and self.messages:Format(field.comment_key)))
			lines[#lines + 1] = field.key .. " = " .. toml_value(field.default)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Returns validated values, or nil, a log message key and its params.
function Config:read_candidate()
	local path = self.spec.path
	self.created = false
	local text, read_error = self.files:ReadText(path)
	if text == false then
		return nil, "config.unreadable", { path = path, reason = read_error }
	end
	if text == nil then
		local written, write_error = self.files:WriteAtomic(path, self:Template())
		if not written then
			return nil, "config.write_failed", { path = path, reason = write_error }
		end
		self.created = true
		return copy(self.defaults)
	end
	local parsed_ok, data = pcall(self.parse, text)
	if not parsed_ok or type(data) ~= "table" then
		return nil, "config.unreadable", { path = path, reason = tostring(data) }
	end
	local version = data.config_version or self.spec.version
	if math.type(version) ~= "integer" or version > self.spec.version or version < 1 then
		return nil,
			"config.unsupported_version",
			{ path = path, found = tostring(version), supported = self.spec.version }
	end
	for from = version, self.spec.version - 1 do
		local migrate = self.spec.migrations and self.spec.migrations[from]
		if not migrate then
			return nil, "config.migration_missing", { path = path, from = from }
		end
		local migrated_ok, migrated = pcall(migrate, data)
		if not migrated_ok or type(migrated) ~= "table" then
			return nil, "config.migration_failed", { path = path, from = from, reason = tostring(migrated) }
		end
		data = migrated
	end
	if version < self.spec.version then
		self.log:Warning("config.migrated", { path = path, from = version, to = self.spec.version })
	end
	data.config_version = nil
	local values, err = self:validate(data)
	if not values then
		return nil, "config.invalid", { path = path, count = err.details.count }, err.details.problems
	end
	return values
end

function Config:report_problems(problems)
	for _, problem in ipairs(problems or {}) do
		self.log:Error("config.problem", { path = self.spec.path, problem = problem.message })
	end
end

function Config:register_secrets()
	for _, field in ipairs(self.fields) do
		if field.secret then
			self.log:RegisterSecret(self:get_path(self.values, field))
		end
	end
end

-- Always leaves usable values: the file's, or the defaults when the file is unusable.
function Config:Load()
	local values, key, params, problems = self:read_candidate()
	if values then
		self.values = values
		self.state = "loaded"
		self.log:Info(self.created and "config.created" or "config.loaded", { path = self.spec.path })
	else
		self.values = copy(self.defaults)
		self.state = "invalid"
		self.problems = problems
		self.log:Error(key, params)
		self:report_problems(problems)
		self.log:Error("config.defaults_used", { path = self.spec.path })
	end
	self:register_secrets()
	return self.values
end

-- Validates the whole file before changing anything. Returns the changed paths and the
-- restart-only paths left pending, or nil and a `config_invalid` error.
function Config:Reload()
	local candidate, key, params, problems = self:read_candidate()
	if not candidate then
		self.log:Error(key, params)
		self:report_problems(problems)
		self.log:Error("config.reload_rejected", { path = self.spec.path })
		return nil,
			self.errors:New("config_invalid", { path = self.spec.path }, {
				details = { reason = self.messages:Format(key, params), problems = problems or {} },
			})
	end
	local changed, pending = {}, {}
	for _, field in ipairs(self.fields) do
		local new_value = self:get_path(candidate, field)
		if not same(new_value, self:get_path(self.values, field)) then
			if field.reload == "hot" then
				self:set_path(self.values, field, new_value)
				changed[#changed + 1] = field.path
			else
				pending[#pending + 1] = field.path
				self.log:Warning("config.restart_required", { key = field.path, path = self.spec.path })
			end
		end
	end
	self.pending_restart = pending
	self.state = "loaded"
	self.problems = nil
	self:register_secrets()
	self.log:Info("config.reloaded", { count = #changed })
	return changed, pending
end

function Config:Values()
	return copy(self.values)
end

function Config:Snapshot()
	local values = {}
	for _, field in ipairs(self.fields) do
		local value = self:get_path(self.values, field)
		values[field.path] = field.secret and Sensitive.MASK or copy(value)
	end
	return {
		path = self.spec.path,
		state = self.state,
		version = self.spec.version,
		values = values,
		pending_restart = copy(self.pending_restart),
		problems = self.problems and #self.problems or 0,
	}
end

return Config
