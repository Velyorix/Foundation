local Config = Package.Require("config.lua")

local PackageConfigs = {}
PackageConfigs.__index = PackageConfigs

local Settings = {}
Settings.__index = Settings

local FIELD_KEY = "^[%a_][%w_]*$"
local SPEC_FIELDS = { version = true, fields = true, migrations = true }
local FIELD_FIELDS = { key = true, schema = true, default = true, description = true, reload = true, secret = true }

-- The file template can only write scalars and (nested) arrays of them.
local function writable(value)
	if type(value) ~= "table" then
		return true
	end
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	for index = 1, count do
		if value[index] == nil or not writable(value[index]) then
			return false
		end
	end
	return true
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

-- options: files, parse, schema, check, log, invoker, messages
function PackageConfigs.new(options)
	return setmetatable({
		files = options.files,
		parse = options.parse,
		S = options.schema,
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		log = options.log,
		invoker = options.invoker,
		configs = {},
		order = {},
	}, PackageConfigs)
end

function PackageConfigs:invalid(api, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = 1,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

function PackageConfigs:check_spec(spec, api, level)
	local check = self.check
	check:Argument(api, 1, "spec", spec, "table", level)
	for key in pairs(spec) do
		if not SPEC_FIELDS[key] then
			self:invalid(api, "spec", "reason.manifest_unknown_field", { field = tostring(key) }, level)
		end
	end
	check:Argument(api, 1, "spec.version", spec.version, "integer?", level)
	if spec.version ~= nil and spec.version < 1 then
		self:invalid(api, "spec.version", "reason.config_version", nil, level)
	end
	check:Argument(api, 1, "spec.migrations", spec.migrations, "table?", level)
	for from, migrate in pairs(spec.migrations or {}) do
		check:Argument(api, 1, "spec.migrations key", from, "integer", level)
		check:Argument(api, 1, "spec.migrations[" .. tostring(from) .. "]", migrate, "function", level)
	end
	check:Argument(api, 1, "spec.fields", spec.fields, "table", level)
	if #spec.fields == 0 then
		self:invalid(api, "spec.fields", "reason.empty_list", nil, level)
	end

	local sections, by_name, seen, kinds = {}, {}, {}, {}
	for index, field in ipairs(spec.fields) do
		local name = "spec.fields[" .. index .. "]"
		check:Argument(api, 1, name, field, "table", level)
		for key in pairs(field) do
			if not FIELD_FIELDS[key] then
				self:invalid(api, name, "reason.manifest_unknown_field", { field = tostring(key) }, level)
			end
		end
		check:Argument(api, 1, name .. ".key", field.key, "string", level)
		local section_name, key = field.key:match("^([^.]+)%.([^.]+)$")
		if not section_name then
			key = field.key
		end
		if not key:match(FIELD_KEY) or (section_name and not section_name:match(FIELD_KEY)) then
			self:invalid(api, name .. ".key", "reason.config_key", nil, level)
		end
		if field.key == "config_version" then
			self:invalid(api, name .. ".key", "reason.config_reserved", nil, level)
		end
		if seen[field.key] then
			self:invalid(api, name .. ".key", "reason.config_duplicate", { key = field.key }, level)
		end
		seen[field.key] = true
		if not self.S.IsSchema(field.schema) then
			self.errors:Raise("invalid_argument", {
				api = api,
				index = 1,
				name = name .. ".schema",
				expected = "schema",
				actual = type(field.schema),
			}, level)
		end
		local valid, err = self.S:Validate(field.schema, field.default)
		if valid == nil and err then
			self:invalid(api, name .. ".default", "reason.config_default", {
				problem = err.details.problems[1] and err.details.problems[1].message or err.message,
			}, level)
		end
		if not writable(field.default) then
			self:invalid(api, name .. ".default", "reason.config_default_table", nil, level)
		end
		check:Argument(api, 1, name .. ".description", field.description, "string?", level)
		check:Argument(api, 1, name .. ".secret", field.secret, "boolean?", level)
		if field.reload ~= nil then
			check:OneOf(api, 1, name .. ".reload", field.reload, { "hot", "restart" }, level)
		end

		local internal = {
			key = key,
			schema = field.schema,
			default = copy(field.default),
			reload = field.reload or "restart",
			secret = field.secret == true,
			comment = field.description,
		}
		local section_key = section_name or false
		if not by_name[section_key] then
			by_name[section_key] = { name = section_name, fields = {} }
			sections[#sections + 1] = by_name[section_key]
		end
		table.insert(by_name[section_key].fields, internal)
		local root = section_name or key
		local kind = section_name and "section" or "setting"
		if kinds[root] and kinds[root] ~= kind then
			self:invalid(api, name .. ".key", "reason.config_section_conflict", { key = root }, level)
		end
		kinds[root] = kind
	end
	local ordered = { by_name[false] }
	for _, section in ipairs(sections) do
		if section.name then
			ordered[#ordered + 1] = section
		end
	end
	return ordered
end

-- `level` as for Check: 2 is the caller of Create, 3 the caller of that caller.
-- Returns the settings object and a release function for the owner's resource tracking.
function PackageConfigs:Create(owner, display_name, spec, api, level)
	if self.configs[owner] then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.messages:Format("reason.config_exists", { owner = owner }),
		}, level)
	end
	local sections = self:check_spec(spec, api, level + 1)
	local config = Config.new({
		spec = {
			path = "foundation/config/" .. owner .. ".toml",
			version = spec.version or 1,
			migrations = spec.migrations,
			header = self.messages:Format("config.template.package_header", { name = display_name, id = owner }),
			sections = sections,
		},
		files = self.files,
		parse = self.parse,
		schema = self.S,
		log = self.log:For(owner, "config"),
		errors = self.errors,
	})
	config:Load()
	local settings = setmetatable({ owner = owner, config = config, hooks = {}, manager = self }, Settings)
	self.configs[owner] = settings
	self.order[#self.order + 1] = owner
	return settings,
		function()
			if self.configs[owner] == settings then
				self.configs[owner] = nil
				for index, name in ipairs(self.order) do
					if name == owner then
						table.remove(self.order, index)
						break
					end
				end
			end
			settings.hooks = {}
			settings.released = true
		end
end

-- Reloads every package configuration; returns { [owner] = { changed, pending } or { error } }.
function PackageConfigs:ReloadAll()
	local results = {}
	for _, owner in ipairs(self.order) do
		local settings = self.configs[owner]
		local changed, pending = settings.config:Reload()
		if changed then
			results[owner] = { changed = changed, pending = pending, path = settings.config.spec.path }
			if #changed > 0 then
				local values = settings.config:Values()
				local info = { owner = owner, kind = "config_hook" }
				for _, hook in ipairs(settings.hooks) do
					self.invoker:Call(info, hook, copy(changed), copy(values))
				end
			end
		else
			results[owner] = { error = pending, path = settings.config.spec.path }
		end
	end
	return results
end

function PackageConfigs:Snapshot()
	local list = {}
	for _, owner in ipairs(self.order) do
		list[#list + 1] = self.configs[owner].config:Snapshot()
	end
	return list
end

function Settings:guard(api)
	if self.released then
		self.manager.errors:Raise("invalid_state", {
			api = api,
			reason = self.manager.messages:Format("reason.context_inactive", { id = self.owner, state = "disabled" }),
		}, 3)
	end
end

function Settings:Get(key)
	self:guard("settings:Get")
	self.manager.check:Argument("settings:Get", 1, "key", key, "string")
	local section, name = key:match("^([^.]+)%.([^.]+)$")
	local values = self.config.values
	local holder = values
	if section then
		holder = type(values[section]) == "table" and values[section] or {}
	end
	local value = holder[name or key]
	if value == nil then
		self.manager.errors:Raise("invalid_value", {
			api = "settings:Get",
			index = 1,
			name = "key",
			reason = self.manager.messages:Format("reason.config_unknown_key", { key = key }),
		})
	end
	return copy(value)
end

function Settings:Values()
	self:guard("settings:Values")
	return self.config:Values()
end

function Settings:GetPath()
	return self.config.spec.path
end

-- hook(changed_keys, values) runs after a reload changed at least one hot setting.
function Settings:OnChange(hook)
	self:guard("settings:OnChange")
	self.manager.check:Argument("settings:OnChange", 1, "hook", hook, "function")
	self.hooks[#self.hooks + 1] = hook
end

return PackageConfigs
