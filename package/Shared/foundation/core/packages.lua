local Registry = {}
Registry.__index = Registry

local Context = {}
Context.__index = Context

local ID_PATTERN = "^[a-z0-9][a-z0-9-]*$"
local MAX_ID_LENGTH = 64
local MANIFEST_FIELDS = {
	id = true,
	name = true,
	version = true,
	author = true,
	api = true,
	depends = true,
	soft_depends = true,
}
local ACTIVE = { initializing = true, ready = true }

local function parse_api(text)
	local major, minor = text:match("^(%d+)%.(%d+)$")
	if not major then
		major = text:match("^(%d+)$")
	end
	if not major then
		return nil
	end
	return tonumber(major), tonumber(minor or 0), minor ~= nil
end

function Registry.new(options)
	local current_major, current_minor = parse_api(options.api_version)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		log = options.log,
		ownership = options.ownership,
		invoker = options.invoker,
		api_version = options.api_version,
		api_major = current_major,
		api_minor = current_minor,
		entries = {},
		order = {},
		sequence = 0,
		alive = true,
	}, Registry)
end

function Registry:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, (level or 2) + 1)
end

-- `level`: 3 when called directly from the public function.
function Registry:check_id(api, index, name, value, level)
	level = level or 3
	self.check:NonEmptyString(api, index, name, value, level)
	if #value > MAX_ID_LENGTH or not value:match(ID_PATTERN) then
		self:invalid(api, index, name, "reason.package_id_format", { max = MAX_ID_LENGTH }, level)
	end
end

function Registry:check_id_list(api, name, list)
	self.check:Argument(api, 2, name, list, "table?", 3)
	for position, value in ipairs(list or {}) do
		self:check_id(api, 2, name .. "[" .. position .. "]", value, 4)
	end
end

function Registry:is_compatible(required)
	local major, minor, has_minor = parse_api(required)
	if major ~= self.api_major then
		return false
	end
	if major == 0 then
		return has_minor and minor == self.api_minor
	end
	return minor <= self.api_minor
end

function Registry:Register(native, manifest)
	local api = "Foundation.Register"
	local check = self.check
	check:Argument(api, 1, "package", native, "table")
	check:Argument(api, 1, "package.GetName", native.GetName, "function")
	check:Argument(api, 1, "package.Subscribe", native.Subscribe, "function")
	check:Argument(api, 2, "manifest", manifest, "table")

	local id = native.GetName()
	self:check_id(api, 1, "package.GetName()", id)
	for field in pairs(manifest) do
		if not MANIFEST_FIELDS[field] then
			self:invalid(api, 2, "manifest", "reason.manifest_unknown_field", { field = tostring(field) })
		end
	end
	if manifest.id ~= nil and manifest.id ~= id then
		self:invalid(
			api,
			2,
			"manifest.id",
			"reason.manifest_id_mismatch",
			{ manifest_id = tostring(manifest.id), id = id }
		)
	end
	check:NonEmptyString(api, 2, "manifest.api", manifest.api)
	if not parse_api(manifest.api) then
		self:invalid(api, 2, "manifest.api", "reason.api_format")
	end
	if not self:is_compatible(manifest.api) then
		self.errors:Raise("incompatible_api", { id = id, required = manifest.api, current = self.api_version })
	end
	check:Argument(api, 2, "manifest.name", manifest.name, "string?")
	check:Argument(api, 2, "manifest.version", manifest.version, "string?")
	check:Argument(api, 2, "manifest.author", manifest.author, "string?")
	self:check_id_list(api, "manifest.depends", manifest.depends)
	self:check_id_list(api, "manifest.soft_depends", manifest.soft_depends)

	local existing = self.entries[id]
	if existing and existing.state ~= "disabled" then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.messages:Format("reason.package_already_registered", { id = id, state = existing.state }),
		})
	end
	for _, dependency in ipairs(manifest.depends or {}) do
		local entry = self.entries[dependency]
		if not entry or not ACTIVE[entry.state] then
			self.errors:Raise("invalid_state", {
				api = api,
				reason = self.messages:Format("reason.missing_dependency", { id = id, dependency = dependency }),
			})
		end
	end

	self.sequence = self.sequence + 1
	local entry = {
		id = id,
		name = manifest.name or (type(native.GetTitle) == "function" and native.GetTitle()) or id,
		version = manifest.version or (type(native.GetVersion) == "function" and native.GetVersion()) or nil,
		author = manifest.author,
		api = manifest.api,
		depends = manifest.depends or {},
		soft_depends = manifest.soft_depends or {},
		state = "initializing",
		sequence = self.sequence,
		native = native,
		ready_hooks = {},
		disable_hooks = {},
	}
	entry.context = setmetatable({ entry = entry, registry = self }, Context)
	self.entries[id] = entry
	self.order[#self.order + 1] = entry
	self.ownership:Open(id)

	entry.on_load = function()
		if self.alive and self.entries[id] == entry then
			self:mark_ready(entry)
		end
	end
	entry.on_unload = function()
		if self.alive and self.entries[id] == entry then
			self:Disable(id, "unload")
		end
	end
	native.Subscribe("Load", entry.on_load)
	native.Subscribe("Unload", entry.on_unload)

	self.log:Info("package.registered", { id = id, version = entry.version or "?", api = entry.api })
	return entry.context
end

function Registry:dependents_of(id)
	local dependents = {}
	for index = #self.order, 1, -1 do
		local entry = self.order[index]
		if self.entries[entry.id] == entry and ACTIVE[entry.state] then
			for _, dependency in ipairs(entry.depends) do
				if dependency == id then
					dependents[#dependents + 1] = entry
					break
				end
			end
		end
	end
	return dependents
end

function Registry:shut_down(entry, cascade_reason)
	entry.stopping = true
	for _, dependent in ipairs(self:dependents_of(entry.id)) do
		self:Disable(dependent.id, cascade_reason)
	end
	local info = { owner = entry.id, kind = "disable_hook" }
	for index = #entry.disable_hooks, 1, -1 do
		self.invoker:Call(info, entry.disable_hooks[index], entry.context)
	end
	self.ownership:ReleaseOwner(entry.id, true)
end

function Registry:fail(entry, reason_key, params)
	if not ACTIVE[entry.state] or entry.stopping then
		return
	end
	local reason = self.messages:Format(reason_key, params)
	self:shut_down(entry, "dependency_failed")
	entry.state = "failed"
	entry.failure = reason
	self.log:Error("package.failed", { id = entry.id, reason = reason })
end

function Registry:mark_ready(entry)
	if entry.state ~= "initializing" or entry.stopping then
		return
	end
	for _, dependency in ipairs(entry.depends) do
		local required = self.entries[dependency]
		if not required or not ACTIVE[required.state] then
			self:fail(entry, "reason.missing_dependency", { id = entry.id, dependency = dependency })
			return
		end
	end
	local info = { owner = entry.id, kind = "ready_hook" }
	for _, hook in ipairs(entry.ready_hooks) do
		if not self.invoker:Call(info, hook, entry.context) then
			self:fail(entry, "reason.ready_hook_failed", { id = entry.id })
			return
		end
	end
	entry.state = "ready"
	self.log:Info("package.ready", { id = entry.id })
end

-- Returns true when the package was active and is now disabled.
function Registry:Disable(id, reason)
	local entry = self.entries[id]
	if not entry or entry.state == "disabled" then
		return false
	end
	if entry.state ~= "failed" then
		if entry.stopping then
			return false
		end
		self:shut_down(entry, "dependency_disabled")
	end
	entry.state = "disabled"
	self.log:Info("package.disabled", { id = id, reason = self.messages:Format("disable_reason." .. reason) })
	return true
end

function Registry:DisableAll(reason)
	for index = #self.order, 1, -1 do
		local entry = self.order[index]
		if self.entries[entry.id] == entry then
			self:Disable(entry.id, reason)
		end
	end
end

-- Disables every package and detaches the native hooks installed on them.
function Registry:Shutdown()
	if not self.alive then
		return
	end
	self:DisableAll("foundation_stopping")
	for _, entry in pairs(self.entries) do
		if type(entry.native.Unsubscribe) == "function" then
			pcall(entry.native.Unsubscribe, "Load", entry.on_load)
			pcall(entry.native.Unsubscribe, "Unload", entry.on_unload)
		end
	end
	self.alive = false
end

function Registry:State(id)
	local entry = self.entries[id]
	return entry and entry.state or nil
end

function Registry:Snapshot()
	local packages = {}
	for _, entry in ipairs(self.order) do
		if self.entries[entry.id] == entry then
			packages[#packages + 1] = {
				id = entry.id,
				name = entry.name,
				version = entry.version,
				author = entry.author,
				api = entry.api,
				state = entry.state,
				failure = entry.failure,
				depends = { table.unpack(entry.depends) },
				resources = self.ownership:Count(entry.id),
				errors = self.invoker:Errors(entry.id),
			}
		end
	end
	return { api_version = self.api_version, packages = packages }
end

function Context:guard(api)
	local entry = self.entry
	if entry.stopping or not ACTIVE[entry.state] or self.registry.entries[entry.id] ~= entry then
		local registry = self.registry
		registry.errors:Raise("invalid_state", {
			api = api,
			reason = registry.messages:Format("reason.context_inactive", { id = entry.id, state = entry.state }),
		}, 3)
	end
	return entry
end

function Context:GetId()
	return self.entry.id
end

function Context:GetName()
	return self.entry.name
end

function Context:GetVersion()
	return self.entry.version
end

function Context:GetState()
	return self.entry.state
end

function Context:IsActive()
	local entry = self.entry
	return not entry.stopping and ACTIVE[entry.state] == true and self.registry.entries[entry.id] == entry
end

function Context:OnReady(hook)
	local entry = self:guard("context:OnReady")
	self.registry.check:Argument("context:OnReady", 1, "hook", hook, "function")
	if entry.state ~= "initializing" then
		self.registry.errors:Raise("invalid_state", {
			api = "context:OnReady",
			reason = self.registry.messages:Format("reason.already_ready", { id = entry.id }),
		})
	end
	entry.ready_hooks[#entry.ready_hooks + 1] = hook
end

function Context:OnDisable(hook)
	local entry = self:guard("context:OnDisable")
	self.registry.check:Argument("context:OnDisable", 1, "hook", hook, "function")
	entry.disable_hooks[#entry.disable_hooks + 1] = hook
end

function Context:Track(kind, release, info)
	local entry = self:guard("context:Track")
	return self.registry.ownership:Track(entry.id, kind, release, info)
end

return Registry
