local Services = {}
Services.__index = Services

local PROVIDE_OPTIONS = { priority = true, replace = true }
local MAX_PRIORITY = 1000000

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

-- options: check, keys, ownership, invoker, events (optional)
function Services.new(options)
	return setmetatable({
		invoker = options.invoker,
		events = options.events,
		watchers = {},
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		keys = options.keys,
		ownership = options.ownership,
		services = {},
		sequence = 0,
	}, Services)
end

-- `level` as for Check: 2 is the caller of the Services method.
function Services:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

function Services:state_error(api, reason_key, params, level)
	self.errors:Raise("invalid_state", { api = api, reason = self.messages:Format(reason_key, params) }, level + 1)
end

function Services:check_range(api, index, range, level)
	if range == nil then
		return nil
	end
	self.check:Argument(api, index, "version", range, "string", level + 1)
	local major, minor = parse_version(range)
	if not major then
		self:invalid(api, index, "version", "reason.service_version", nil, level + 1)
	end
	return { major = major, minor = minor }
end

local function accepts(range, provider)
	return range == nil or (provider.major == range.major and provider.minor >= range.minor)
end

-- A proxy stays bound to its provider and refuses every use once the provider is gone,
-- so consumers cannot keep calling a stopped package.
function Services:proxy(provider)
	local implementation = provider.implementation
	local wrappers = {}
	local proxy = {}
	local function guard(key)
		if not provider.active then
			self.errors:Raise("invalid_state", {
				api = "service:" .. tostring(key),
				reason = self.messages:Format("reason.service_gone", { name = provider.key, owner = provider.owner }),
			}, 3)
		end
	end
	return setmetatable(proxy, {
		__index = function(_, key)
			guard(key)
			local value = implementation[key]
			if type(value) ~= "function" then
				return value
			end
			local wrapper = wrappers[key]
			if not wrapper then
				wrapper = function(target, ...)
					guard(key)
					if target == proxy then
						target = implementation
					end
					return value(target, ...)
				end
				wrappers[key] = wrapper
			end
			return wrapper
		end,
		__newindex = function(_, key)
			self.errors:Raise("invalid_state", {
				api = "service:" .. tostring(key),
				reason = self.messages:Format("reason.service_read_only"),
			}, 2)
		end,
		__metatable = false,
	})
end

local function sort_providers(list)
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.sequence < b.sequence
	end)
end

function Services:remove(provider)
	if not provider.active then
		return
	end
	provider.active = false
	local list = self.services[provider.key]
	if not list then
		return
	end
	for index, other in ipairs(list) do
		if other == provider then
			table.remove(list, index)
			break
		end
	end
	if #list == 0 then
		self.services[provider.key] = nil
	end
	if not provider.replacing then
		self:announce("service_unavailable", provider)
		self:notify(provider.key)
	end
end

-- Returns the provider record (with its ownership handle in `handle`).
function Services:Provide(owner, name, version, implementation, options, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner }, level)
	local check = self.check
	check:Argument(api, 2, "version", version, "string", level)
	local major, minor, explicit = parse_version(version)
	if not major or not explicit then
		self:invalid(api, 2, "version", "reason.service_provided_version", nil, level)
	end
	check:Argument(api, 3, "implementation", implementation, "table", level)
	check:Argument(api, 4, "options", options, "table?", level)
	options = options or {}
	for field in pairs(options) do
		if not PROVIDE_OPTIONS[field] then
			self:invalid(api, 4, "options", "reason.manifest_unknown_field", { field = tostring(field) }, level)
		end
	end
	check:Argument(api, 4, "options.priority", options.priority, "integer?", level)
	check:Argument(api, 4, "options.replace", options.replace, "boolean?", level)
	local priority = options.priority or 0
	if priority < -MAX_PRIORITY or priority > MAX_PRIORITY then
		self:invalid(api, 4, "options.priority", "reason.service_priority", { max = MAX_PRIORITY }, level)
	end

	local previous
	for _, other in ipairs(self.services[key] or {}) do
		if other.owner == owner then
			previous = other
		elseif other.priority == priority and other.major == major then
			self:state_error(api, "reason.service_tie", {
				name = key,
				owner = other.owner,
				priority = priority,
			}, level)
		end
	end
	if previous and not options.replace then
		self:state_error(api, "reason.service_provided", { name = key }, level)
	end
	if previous then
		previous.replacing = true
		previous.handle:Release()
	end

	self.sequence = self.sequence + 1
	local provider = {
		key = key,
		owner = owner,
		version = version,
		major = major,
		minor = minor,
		priority = priority,
		sequence = self.sequence,
		implementation = implementation,
		active = true,
	}
	provider.proxy = self:proxy(provider)
	provider.handle = self.ownership:Track(owner, "service", function()
		self:remove(provider)
	end, { service = key, version = version })
	local list = self.services[key]
	if not list then
		list = {}
		self.services[key] = list
	end
	list[#list + 1] = provider
	sort_providers(list)
	if previous then
		self:announce("service_unavailable", previous)
	end
	self:announce("service_available", provider)
	self:notify(key)
	return provider
end

local function describe(provider)
	return {
		service = provider.proxy,
		provider = provider.owner,
		version = provider.version,
		priority = provider.priority,
	}
end

-- Providers of `name` that satisfy `range`, best first.
function Services:Find(owner, name, range, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner }, level)
	local parsed = self:check_range(api, 2, range, level)
	local result = {}
	for _, provider in ipairs(self.services[key] or {}) do
		if accepts(parsed, provider) then
			result[#result + 1] = provider
		end
	end
	return result
end

function Services:Get(owner, name, range, api, level)
	local best = self:Find(owner, name, range, api, level + 1)[1]
	if not best then
		return nil
	end
	return best.proxy, describe(best)
end

function Services:All(owner, name, range, api, level)
	local result = {}
	for index, provider in ipairs(self:Find(owner, name, range, api, level + 1)) do
		result[index] = describe(provider)
	end
	return result
end

function Services:announce(name, provider)
	if not self.events then
		return
	end
	self.invoker:Call({ owner = "foundation", kind = "service_event" }, function()
		self.events:Emit("foundation", name, {
			service = provider.key,
			provider = provider.owner,
			version = provider.version,
			priority = provider.priority,
		}, "Services", 2)
	end)
end

function Services:best(key, range)
	for _, provider in ipairs(self.services[key] or {}) do
		if accepts(range, provider) then
			return provider
		end
	end
	return nil
end

-- Calls the watchers of `key` whose best provider changed.
function Services:notify(key)
	local watchers = self.watchers[key]
	if not watchers then
		return
	end
	local snapshot = {}
	for index, watcher in ipairs(watchers) do
		snapshot[index] = watcher
	end
	for _, watcher in ipairs(snapshot) do
		if watcher.active then
			local best = self:best(key, watcher.range)
			if best ~= watcher.current then
				watcher.current = best
				self:call_watcher(watcher, best)
			end
		end
	end
end

function Services:call_watcher(watcher, provider)
	if provider then
		self.invoker:Call(watcher.info, watcher.fn, provider.proxy, describe(provider))
	else
		self.invoker:Call(watcher.info, watcher.fn, nil, nil)
	end
end

-- fn(service, info) runs now when a matching provider exists, then each time the best
-- matching provider changes; fn(nil) when none is left. Returns the ownership handle.
function Services:Watch(owner, name, range, fn, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner }, level)
	local parsed = self:check_range(api, 2, range, level)
	self.check:Argument(api, 3, "fn", fn, "function", level)
	local watcher = {
		owner = owner,
		range = parsed,
		fn = fn,
		active = true,
		info = { owner = owner, kind = "service_watcher", fields = { service = key } },
	}
	local list = self.watchers[key]
	if not list then
		list = {}
		self.watchers[key] = list
	end
	list[#list + 1] = watcher
	watcher.handle = self.ownership:Track(owner, "service_watcher", function()
		watcher.active = false
		local current = self.watchers[key]
		for index, other in ipairs(current or {}) do
			if other == watcher then
				table.remove(current, index)
				break
			end
		end
		if current and #current == 0 then
			self.watchers[key] = nil
		end
	end, { service = key })
	local best = self:best(key, parsed)
	if best then
		watcher.current = best
		self:call_watcher(watcher, best)
	end
	return watcher.handle
end

function Services:Snapshot()
	local services = {}
	for key, list in pairs(self.services) do
		local providers = {}
		for index, provider in ipairs(list) do
			providers[index] = { owner = provider.owner, version = provider.version, priority = provider.priority }
		end
		services[key] = providers
	end
	return { services = services }
end

return Services
