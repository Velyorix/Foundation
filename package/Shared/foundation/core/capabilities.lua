local Capabilities = {}
Capabilities.__index = Capabilities

local DECLARATION_FIELDS = { name = true, version = true }

local function parse_version(text)
	if type(text) ~= "string" then
		return nil
	end
	local major, minor = text:match("^(%d+)%.(%d+)$")
	if major then
		return tonumber(major), tonumber(minor), true
	end
	major = text:match("^(%d+)$")
	if major then
		return tonumber(major), 0, false
	end
	return nil
end

-- options: check, keys, log, events (optional), services (optional, for name clashes)
function Capabilities.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		keys = options.keys,
		log = options.log,
		events = options.events,
		services = options.services,
		active = {},
	}, Capabilities)
end

function Capabilities:invalid(api, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = 2,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

-- Validates `manifest.capabilities`: names, or { name, version = "<major>.<minor>" }.
-- Returns the list of { key, version, major, minor }.
function Capabilities:CheckManifest(value, api, level)
	if value == nil then
		return {}
	end
	self.check:Argument(api, 2, "manifest.capabilities", value, "table", level)
	local declarations, seen = {}, {}
	for index, item in ipairs(value) do
		local name = "manifest.capabilities[" .. index .. "]"
		local text, version = item, nil
		local valid = type(item) == "string"
		if type(item) == "table" then
			valid = true
			for field in pairs(item) do
				valid = valid and DECLARATION_FIELDS[field] == true
			end
			text, version = item.name, item.version
		end
		local key = valid and type(text) == "string" and self.keys:Parse(text)
		local major, minor, explicit = parse_version(version)
		if not key or (version ~= nil and not explicit) then
			self:invalid(api, name, "reason.manifest_capability", nil, level)
		end
		if self.keys.IsReserved((self.keys.Split(key))) then
			self:invalid(api, name, "reason.capability_reserved", { name = key }, level)
		end
		if seen[key] then
			self:invalid(api, name, "reason.manifest_capability_duplicate", { name = key }, level)
		end
		seen[key] = true
		declarations[#declarations + 1] = { key = key, version = version, major = major, minor = minor }
	end
	return declarations
end

function Capabilities:announce(name, owner, declaration)
	if self.events then
		self.events:Emit("foundation", name, {
			capability = declaration.key,
			package = owner,
			version = declaration.version,
		}, "Capabilities", 2)
	end
end

-- Registry observer: capabilities are available while their package is ready.
function Capabilities:Observe(kind, entry)
	local declarations = entry.extensions.capabilities or {}
	if kind == "ready" then
		for _, declaration in ipairs(declarations) do
			local list = self.active[declaration.key]
			if not list then
				list = {}
				self.active[declaration.key] = list
			end
			list[#list + 1] = { owner = entry.id, declaration = declaration }
			if self.services and self.services.services[declaration.key] then
				self.log
					:For(entry.id, "capabilities")
					:Warning("capabilities.service_clash", { name = declaration.key, id = entry.id })
			end
			self:announce("capability_available", entry.id, declaration)
		end
		return
	end
	for _, declaration in ipairs(declarations) do
		local list = self.active[declaration.key]
		for index, item in ipairs(list or {}) do
			if item.owner == entry.id then
				table.remove(list, index)
				if #list == 0 then
					self.active[declaration.key] = nil
				end
				self:announce("capability_unavailable", entry.id, declaration)
				break
			end
		end
	end
end

-- `level` as for Check, seen from the public function.
function Capabilities:query(api, name, range, level)
	local key = self.keys:Check(api, 1, "name", name, nil, level + 1)
	self.check:Argument(api, 2, "version", range, "string?", level + 1)
	local major, minor
	if range ~= nil then
		major, minor = parse_version(range)
		if not major then
			self.errors:Raise("invalid_value", {
				api = api,
				index = 2,
				name = "version",
				reason = self.messages:Format("reason.service_version"),
			}, level + 1)
		end
	end
	local result = {}
	for _, item in ipairs(self.active[key] or {}) do
		local declaration = item.declaration
		local accepted = major == nil
			or (declaration.major ~= nil and declaration.major == major and declaration.minor >= minor)
		if accepted then
			result[#result + 1] = { package = item.owner, version = declaration.version }
		end
	end
	return result
end

function Capabilities:Has(name, range, level)
	return #self:query("Foundation.Capabilities.Has", name, range, level or 2) > 0
end

function Capabilities:Providers(name, range, level)
	local result = self:query("Foundation.Capabilities.Providers", name, range, level or 2)
	return result
end

function Capabilities:Snapshot()
	local capabilities = {}
	for key, list in pairs(self.active) do
		local providers = {}
		for index, item in ipairs(list) do
			providers[index] = { package = item.owner, version = item.declaration.version }
		end
		capabilities[key] = providers
	end
	return { capabilities = capabilities }
end

return Capabilities
