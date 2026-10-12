-- Registries: named collections of entries that packages share (item definitions, handlers,
-- recipes...). A registry belongs to the package that defines it; entries belong to the
-- package that registers them. Everything is runtime only.
local Registries = {}
Registries.__index = Registries

local View = {}
View.__index = View

local DEFINE_OPTIONS = { schema = true, contributions = true, enumerable = true }
local REGISTER_OPTIONS = { replace = true }
local CONTRIBUTIONS = { owner = true, open = true }

-- options: check, keys, schema, ownership, invoker
function Registries.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		keys = options.keys,
		S = options.schema,
		ownership = options.ownership,
		invoker = options.invoker,
		registries = {},
		watchers = {},
	}, Registries)
end

function Registries:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

function Registries:state_error(api, reason_key, params, level)
	self.errors:Raise("invalid_state", { api = api, reason = self.messages:Format(reason_key, params) }, level + 1)
end

function Registries:check_options(api, index, options, allowed, level)
	self.check:Argument(api, index, "options", options, "table?", level + 1)
	for field in pairs(options or {}) do
		if not allowed[field] then
			self:invalid(api, index, "options", "reason.manifest_unknown_field", { field = tostring(field) }, level + 1)
		end
	end
	return options or {}
end

function Registries:view(registry, viewer)
	return setmetatable({ manager = self, registry = registry, viewer = viewer }, View)
end

function Registries:notify_watchers(key)
	local registry = self.registries[key]
	for _, watcher in ipairs(self.watchers[key] or {}) do
		if watcher.active then
			self.invoker:Call(watcher.info, watcher.fn, registry and self:view(registry, watcher.owner) or nil)
		end
	end
end

function Registries:Define(owner, name, options, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner, owner = owner }, level)
	options = self:check_options(api, 2, options, DEFINE_OPTIONS, level)
	if options.schema ~= nil and not self.S.IsSchema(options.schema) then
		self.errors:Raise("invalid_argument", {
			api = api,
			index = 2,
			name = "options.schema",
			expected = "schema",
			actual = type(options.schema),
		}, level)
	end
	self.check:Argument(api, 2, "options.contributions", options.contributions, "string?", level)
	if options.contributions ~= nil and not CONTRIBUTIONS[options.contributions] then
		self:invalid(api, 2, "options.contributions", "reason.registry_contributions", nil, level)
	end
	self.check:Argument(api, 2, "options.enumerable", options.enumerable, "boolean?", level)
	if self.registries[key] then
		self:state_error(api, "reason.registry_defined", { registry = key }, level)
	end
	local registry = {
		key = key,
		owner = owner,
		schema = options.schema,
		open = options.contributions == "open",
		enumerable = options.enumerable ~= false,
		entries = {},
		count = 0,
		listeners = {},
		active = true,
	}
	self.registries[key] = registry
	registry.handle = self.ownership:Track(owner, "registry", function()
		self:remove_registry(registry)
	end, { registry = key })
	self:notify_watchers(key)
	return self:view(registry, owner)
end

function Registries:remove_registry(registry)
	registry.active = false
	if self.registries[registry.key] == registry then
		self.registries[registry.key] = nil
	end
	local listeners, entries = registry.listeners, registry.entries
	registry.entries, registry.count, registry.listeners = {}, 0, {}
	for _, listener in ipairs(listeners) do
		listener.handle:Release()
	end
	for _, entry in pairs(entries) do
		entry.handle:Release()
	end
	self:notify_watchers(registry.key)
end

-- Returns a view for `owner`, or nil when the registry is not defined.
function Registries:Find(owner, name, api, level)
	local key = self.keys:Check(api, 1, "key", name, nil, level)
	local registry = self.registries[key]
	return registry and self:view(registry, owner) or nil
end

-- fn(view) now when the registry exists and each time it is defined again; fn(nil) when its
-- package stops. Returns the ownership handle.
function Registries:Watch(owner, name, fn, api, level)
	local key = self.keys:Check(api, 1, "key", name, nil, level)
	self.check:Argument(api, 2, "fn", fn, "function", level)
	local watcher = {
		owner = owner,
		fn = fn,
		active = true,
		info = { owner = owner, kind = "registry_watcher", fields = { registry = key } },
	}
	local list = self.watchers[key] or {}
	self.watchers[key] = list
	list[#list + 1] = watcher
	watcher.handle = self.ownership:Track(owner, "registry_watcher", function()
		watcher.active = false
		for index, other in ipairs(list) do
			if other == watcher then
				table.remove(list, index)
				break
			end
		end
		if #list == 0 and self.watchers[key] == list then
			self.watchers[key] = nil
		end
	end, { registry = key })
	local registry = self.registries[key]
	if registry then
		self.invoker:Call(watcher.info, fn, self:view(registry, owner))
	end
	return watcher.handle
end

function Registries:changed(registry, action, key, value)
	for _, listener in ipairs(registry.listeners) do
		if listener.active then
			self.invoker:Call(listener.info, listener.fn, action, key, value)
		end
	end
end

-- `level` as for Check: 2 is the caller of the View method that calls this.
function View:guard(api, level)
	local registry = self.registry
	if not registry.active then
		self.manager:state_error(api, "reason.registry_removed", { registry = registry.key }, level + 1)
	end
	return registry
end

function View:GetName()
	return self.registry.key
end

function View:Register(key, value, options)
	local manager, viewer = self.manager, self.viewer
	local registry = self:guard("registry:Register", 2)
	if not registry.open and viewer ~= registry.owner then
		manager:state_error("registry:Register", "reason.registry_closed", {
			registry = registry.key,
			owner = registry.owner,
		}, 2)
	end
	key = manager.keys:Check("registry:Register", 1, "key", key, { default_namespace = viewer, owner = viewer }, 2)
	if value == nil then
		manager.errors:Raise("invalid_argument", {
			api = "registry:Register",
			index = 2,
			name = "value",
			expected = "value",
			actual = "nil",
		}, 2)
	end
	options = manager:check_options("registry:Register", 3, options, REGISTER_OPTIONS, 2)
	manager.check:Argument("registry:Register", 3, "options.replace", options.replace, "boolean?", 2)
	if registry.schema then
		local checked, err = manager.S:Validate(registry.schema, value)
		if err then
			manager:invalid("registry:Register", 2, "value", "reason.registry_value", {
				registry = registry.key,
				problem = err.details.problems[1] and err.details.problems[1].message or err.message,
			}, 2)
		end
		value = checked
	end
	local previous = registry.entries[key]
	if previous and not options.replace then
		manager:state_error("registry:Register", "reason.registry_taken", { key = key, registry = registry.key }, 2)
	end
	if previous then
		previous.replaced = true
		previous.handle:Release()
	end
	local entry = { key = key, value = value, owner = viewer, active = true }
	entry.handle = manager.ownership:Track(viewer, "registry_entry", function()
		if not entry.active then
			return
		end
		entry.active = false
		if registry.entries[key] == entry then
			registry.entries[key] = nil
			registry.count = registry.count - 1
		end
		if not entry.replaced then
			manager:changed(registry, "removed", key, entry.value)
		end
	end, { registry = registry.key, key = key })
	registry.entries[key] = entry
	registry.count = registry.count + 1
	manager:changed(registry, previous and "replaced" or "added", key, value)
	return entry.handle
end

-- Direct lookup first: only unknown keys are parsed, so hot paths stay one table access.
function View:lookup(api, key)
	local registry = self:guard(api, 3)
	local entry = registry.entries[key]
	if entry then
		return entry
	end
	local parsed = self.manager.keys:Check(api, 1, "key", key, nil, 3)
	return registry.entries[parsed]
end

function View:Get(key)
	local entry = self:lookup("registry:Get", key)
	return entry and entry.value
end

function View:Has(key)
	return self:lookup("registry:Has", key) ~= nil
end

function View:GetEntry(key)
	local entry = self:lookup("registry:GetEntry", key)
	return entry and { key = entry.key, value = entry.value, owner = entry.owner }
end

function View:Count()
	return self:guard("registry:Count", 2).count
end

-- Sorted keys, all of them or those of one namespace.
function View:Keys(namespace)
	local manager = self.manager
	local registry = self:guard("registry:Keys", 2)
	manager.check:Argument("registry:Keys", 1, "namespace", namespace, "string?", 2)
	if not registry.enumerable and self.viewer ~= registry.owner then
		manager:state_error("registry:Keys", "reason.registry_not_enumerable", { registry = registry.key }, 2)
	end
	local prefix = namespace and (namespace:lower() .. ":")
	local keys = {}
	for key in pairs(registry.entries) do
		if not prefix or key:sub(1, #prefix) == prefix then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	return keys
end

-- fn(action, key, value) after each change: "added", "replaced" or "removed". Owned by the
-- viewing package; stops when the registry is removed.
function View:OnChange(fn)
	local manager = self.manager
	local registry = self:guard("registry:OnChange", 2)
	manager.check:Argument("registry:OnChange", 1, "fn", fn, "function", 2)
	local listener = {
		fn = fn,
		active = true,
		info = { owner = self.viewer, kind = "registry_listener", fields = { registry = registry.key } },
	}
	registry.listeners[#registry.listeners + 1] = listener
	listener.handle = manager.ownership:Track(self.viewer, "registry_listener", function()
		listener.active = false
		for index, other in ipairs(registry.listeners) do
			if other == listener then
				table.remove(registry.listeners, index)
				break
			end
		end
	end, { registry = registry.key })
	return listener.handle
end

function Registries:Snapshot()
	local list = {}
	for key, registry in pairs(self.registries) do
		list[#list + 1] = { key = key, owner = registry.owner, count = registry.count, open = registry.open }
	end
	table.sort(list, function(a, b)
		return a.key < b.key
	end)
	return list
end

return Registries
