-- Package key-value stores over a storage backend (core/storage_memory.lua contract).
-- A store loads the size of each of its keys once, which gives exact quotas, existence
-- without a query, and immediate answers for cached values.
local Stores = {}
Stores.__index = Stores

local Store = {}
Store.__index = Store

Stores.MAX_KEY_LENGTH = 256
Stores.MAX_CACHED_VALUE = 4096
Stores.MAX_CACHED_ENTRIES = 2000
Stores.MAX_LIST = 10000

local NAME_PATTERN = "^[a-z0-9_-]+$"

local function valid_key(key)
	return type(key) == "string" and key ~= "" and #key <= Stores.MAX_KEY_LENGTH and not key:find("%c")
end

-- options: check, json, futures, backend (nil when storage is unavailable), log,
-- limits() returning { max_bytes, max_keys }
function Stores.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		json = options.json,
		futures = options.futures,
		backend = options.backend,
		log = options.log,
		limits = options.limits,
		stores = {},
	}, Stores)
end

-- Returns the store and, for a new one, a release function for the owner's tracking.
function Stores:Open(owner, name, api, level)
	self.check:Argument(api, 1, "name", name, "string?", level)
	if name ~= nil and not name:match(NAME_PATTERN) then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "name",
			reason = self.messages:Format("reason.store_name"),
		}, level)
	end
	local namespace = name and (owner .. "/" .. name) or owner
	local existing = self.stores[namespace]
	if existing and existing.active then
		return existing
	end
	local store = setmetatable({
		manager = self,
		owner = owner,
		namespace = namespace,
		active = true,
		ready = false,
		waiting = {},
		sizes = {},
		count = 0,
		bytes = 0,
		cache = {},
		cached = 0,
	}, Store)
	self.stores[namespace] = store
	store:load()
	return store,
		function()
			store.active = false
			if self.stores[namespace] == store then
				self.stores[namespace] = nil
			end
		end
end

function Stores:failure(owner, code, params, cause)
	return self.errors:New(code, params, { owner = owner, cause = cause })
end

function Store:load()
	local manager = self.manager
	if not manager.backend then
		self.unavailable = true
		self:release_waiting()
		return
	end
	manager.backend:Sizes(self.namespace, function(ok, sizes)
		if not ok then
			self.unavailable = true
			manager.log
				:For(self.owner, "storage")
				:Error("storage.load_failed", { namespace = self.namespace, reason = sizes })
		else
			for key, size in pairs(sizes) do
				self.sizes[key] = size
				self.count = self.count + 1
				self.bytes = self.bytes + size
			end
		end
		self.ready = true
		self:release_waiting()
	end)
end

function Store:release_waiting()
	local waiting = self.waiting
	self.waiting = {}
	for _, run in ipairs(waiting) do
		run()
	end
end

-- Runs `fn(future)` once the store knows its keys; returns the future.
function Store:operation(api, fn)
	local manager = self.manager
	if not self.active then
		manager.errors:Raise("invalid_state", {
			api = api,
			reason = manager.messages:Format("reason.store_closed", { namespace = self.namespace }),
		}, 3)
	end
	local future = manager.futures:Create(self.owner)
	local function run()
		if self.unavailable then
			future:Reject(manager:failure(self.owner, "storage_unavailable", { namespace = self.namespace }))
			return
		end
		fn(future)
	end
	if self.ready or self.unavailable then
		run()
	else
		self.waiting[#self.waiting + 1] = run
	end
	return future
end

function Store:check_key(api, key)
	if not valid_key(key) then
		local manager = self.manager
		manager.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "key",
			reason = manager.messages:Format("reason.store_key", { max = Stores.MAX_KEY_LENGTH }),
		}, 3)
	end
end

function Store:remember(key, text)
	if self.cache[key] == nil then
		if #text > Stores.MAX_CACHED_VALUE then
			return
		end
		if self.cached >= Stores.MAX_CACHED_ENTRIES then
			local victim = next(self.cache)
			self.cache[victim] = nil
			self.cached = self.cached - 1
		end
		self.cached = self.cached + 1
	end
	self.cache[key] = text
end

function Store:forget(key)
	if self.cache[key] ~= nil then
		self.cache[key] = nil
		self.cached = self.cached - 1
	end
end

function Store:decode(future, key, text)
	local manager = self.manager
	local ok, value = manager.json.Decode(text)
	if not ok then
		future:Reject(manager:failure(self.owner, "storage_corrupt", { namespace = self.namespace, key = key }))
		return
	end
	future:Resolve(value)
end

function Store:Get(key)
	self:check_key("store:Get", key)
	return self:operation("store:Get", function(future)
		if self.sizes[key] == nil then
			return future:Resolve(nil)
		end
		local cached = self.cache[key]
		if cached then
			return self:decode(future, key, cached)
		end
		local manager = self.manager
		manager.backend:Get(self.namespace, key, function(ok, text)
			if not ok then
				return future:Reject(
					manager:failure(self.owner, "storage_failed", { namespace = self.namespace }, text)
				)
			end
			if text == nil then
				return future:Resolve(nil)
			end
			self:remember(key, text)
			self:decode(future, key, text)
		end)
	end)
end

function Store:encode(api, index, value)
	local manager = self.manager
	if value == nil then
		manager.errors:Raise("invalid_argument", {
			api = api,
			index = index,
			name = "value",
			expected = "value (use Delete to remove a key)",
			actual = "nil",
		}, 3)
	end
	local text, reason, params = manager.json.Encode(value)
	if not text then
		manager.errors:Raise("invalid_value", {
			api = api,
			index = index,
			name = "value",
			reason = manager.messages:Format(reason, params),
		}, 3)
	end
	return text
end

-- Applies `changes` ({ key, text or false }) to the counters and the cache, or returns the
-- quota error without changing anything. Returns the undo function.
function Store:apply(changes)
	local manager = self.manager
	local count, bytes = self.count, self.bytes
	for _, change in ipairs(changes) do
		local old = self.sizes[change.key]
		if old then
			count, bytes = count - 1, bytes - old
		end
		if change.text then
			count, bytes = count + 1, bytes + #change.key + #change.text
		end
	end
	local limits = manager.limits()
	if (count > self.count and count > limits.max_keys) or (bytes > self.bytes and bytes > limits.max_bytes) then
		return nil,
			manager:failure(self.owner, "storage_quota", {
				namespace = self.namespace,
				max_keys = limits.max_keys,
				max_bytes = limits.max_bytes,
			})
	end
	local previous = {}
	for index, change in ipairs(changes) do
		previous[index] = { key = change.key, size = self.sizes[change.key], text = self.cache[change.key] }
		if change.text then
			self.sizes[change.key] = #change.key + #change.text
			self:remember(change.key, change.text)
		else
			self.sizes[change.key] = nil
			self:forget(change.key)
		end
	end
	local before_count, before_bytes = self.count, self.bytes
	self.count, self.bytes = count, bytes
	return function()
		for index = #previous, 1, -1 do
			local item = previous[index]
			self.sizes[item.key] = item.size
			self:forget(item.key)
			if item.text then
				self:remember(item.key, item.text)
			end
		end
		self.count, self.bytes = before_count, before_bytes
	end
end

function Store:write(future, changes, operations)
	local manager = self.manager
	local undo, quota = self:apply(changes)
	if not undo then
		return future:Reject(quota)
	end
	local function done(ok, reason)
		if ok then
			return future:Resolve(true)
		end
		undo()
		future:Reject(manager:failure(self.owner, "storage_failed", { namespace = self.namespace }, reason))
	end
	if #operations == 1 and operations[1].op == "set" then
		manager.backend:Set(self.namespace, operations[1].key, operations[1].value, done)
	elseif #operations == 1 then
		manager.backend:Delete(self.namespace, operations[1].key, done)
	else
		manager.backend:Batch(self.namespace, operations, done)
	end
end

function Store:Set(key, value)
	self:check_key("store:Set", key)
	local text = self:encode("store:Set", 2, value)
	return self:operation("store:Set", function(future)
		self:write(future, { { key = key, text = text } }, { { op = "set", key = key, value = text } })
	end)
end

-- Resolves with whether the key existed.
function Store:Delete(key)
	self:check_key("store:Delete", key)
	return self:operation("store:Delete", function(future)
		if self.sizes[key] == nil then
			return future:Resolve(false)
		end
		local inner = self.manager.futures:Create(self.owner)
		inner:Then(function()
			future:Resolve(true)
		end, function(err)
			future:Reject(err)
		end)
		self:write(inner, { { key = key, text = false } }, { { op = "delete", key = key } })
	end)
end

-- operations: { { op = "set", key = ..., value = ... } | { op = "delete", key = ... } }.
function Store:Batch(operations)
	local manager = self.manager
	manager.check:Argument("store:Batch", 1, "operations", operations, "table", 2)
	local changes, encoded = {}, {}
	for index, operation in ipairs(operations) do
		local valid = type(operation) == "table" and (operation.op == "set" or operation.op == "delete")
		if not valid or not valid_key(operation.key) then
			manager.errors:Raise("invalid_value", {
				api = "store:Batch",
				index = 1,
				name = "operations[" .. index .. "]",
				reason = manager.messages:Format("reason.store_operation", { max = Stores.MAX_KEY_LENGTH }),
			}, 2)
		end
		if operation.op == "set" then
			local text = self:encode("store:Batch", 1, operation.value)
			changes[index] = { key = operation.key, text = text }
			encoded[index] = { op = "set", key = operation.key, value = text }
		else
			changes[index] = { key = operation.key, text = false }
			encoded[index] = { op = "delete", key = operation.key }
		end
	end
	return self:operation("store:Batch", function(future)
		if #encoded == 0 then
			return future:Resolve(true)
		end
		self:write(future, changes, encoded)
	end)
end

-- Keys starting with `prefix`, sorted, at most `limit` (default and maximum 10000).
function Store:Keys(prefix, limit)
	local manager = self.manager
	manager.check:Argument("store:Keys", 1, "prefix", prefix, "string?", 2)
	manager.check:Argument("store:Keys", 2, "limit", limit, "integer?", 2)
	prefix, limit = prefix or "", math.min(limit or Stores.MAX_LIST, Stores.MAX_LIST)
	return self:operation("store:Keys", function(future)
		local keys = {}
		for key in pairs(self.sizes) do
			if key:sub(1, #prefix) == prefix then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys)
		while #keys > limit do
			keys[#keys] = nil
		end
		future:Resolve(keys)
	end)
end

-- Immediate: { count, bytes, max_keys, max_bytes }.
function Store:Usage()
	local limits = self.manager.limits()
	return { count = self.count, bytes = self.bytes, max_keys = limits.max_keys, max_bytes = limits.max_bytes }
end

function Store:GetName()
	return self.namespace
end

function Stores:Snapshot()
	local stores = {}
	for namespace, store in pairs(self.stores) do
		stores[namespace] =
			{ count = store.count, bytes = store.bytes, ready = store.ready, unavailable = store.unavailable }
	end
	return { available = self.backend ~= nil, stores = stores }
end

return Stores
