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
-- Backend namespace holding the data version of each versioned store.
Stores.VERSIONS = "foundation/versions"

local NAME_PATTERN = "^[a-z0-9_-]+$"
local OPTION_FIELDS = { version = true, migrations = true }

local function valid_key(key)
	return type(key) == "string" and key ~= "" and #key <= Stores.MAX_KEY_LENGTH and not key:find("%c")
end

-- options: check, json, futures, invoker, backend (nil when storage is unavailable), log,
-- limits() returning { max_bytes, max_keys }, fail(owner, reason_key, params)
function Stores.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		json = options.json,
		futures = options.futures,
		invoker = options.invoker,
		fail = options.fail,
		backend = options.backend,
		log = options.log,
		limits = options.limits,
		stores = {},
	}, Stores)
end

-- Returns the store and, for a new one, a release function for the owner's tracking and a
-- start function that loads it (call it once the release function is tracked).
function Stores:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

-- Returns version and migrations from the store options.
function Stores:check_options(api, options, level)
	self.check:Argument(api, 2, "options", options, "table?", level + 1)
	if options == nil then
		return nil, nil
	end
	for field in pairs(options) do
		if not OPTION_FIELDS[field] then
			self:invalid(api, 2, "options", "reason.manifest_unknown_field", { field = tostring(field) }, level + 1)
		end
	end
	self.check:Argument(api, 2, "options.version", options.version, "integer", level + 1)
	if options.version < 1 then
		self:invalid(api, 2, "options.version", "reason.config_version", nil, level + 1)
	end
	self.check:Argument(api, 2, "options.migrations", options.migrations, "table?", level + 1)
	local migrations = options.migrations or {}
	for from = 1, options.version - 1 do
		if type(migrations[from]) ~= "function" then
			self:invalid(api, 2, "options.migrations", "reason.store_migration_missing", { from = from }, level + 1)
		end
	end
	return options.version, migrations
end

function Stores:Open(owner, name, options, api, level)
	self.check:Argument(api, 1, "name", name, "string?", level)
	if name ~= nil and not name:match(NAME_PATTERN) then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "name",
			reason = self.messages:Format("reason.store_name"),
		}, level)
	end
	local version, migrations = self:check_options(api, options, level)
	local namespace = name and (owner .. "/" .. name) or owner
	local existing = self.stores[namespace]
	if existing and existing.active then
		if options ~= nil and existing.version ~= version then
			self.errors:Raise("invalid_state", {
				api = api,
				reason = self.messages:Format("reason.store_reopened", { namespace = namespace }),
			}, level)
		end
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
		version = version,
		migrations = migrations,
	}, Store)
	self.stores[namespace] = store
	return store,
		function()
			store.active = false
			if self.stores[namespace] == store then
				self.stores[namespace] = nil
			end
		end,
		function()
			store:load()
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
	if not self.version then
		return self:load_sizes()
	end
	manager.backend:Get(Stores.VERSIONS, self.namespace, function(ok, text)
		if not ok then
			return self:fail_load("storage.load_failed", { namespace = self.namespace, reason = text })
		end
		local stored = text and tonumber(text)
		if stored and stored > self.version then
			return self:fail_load("storage.version_newer", {
				namespace = self.namespace,
				stored = stored,
				version = self.version,
			}, "reason.store_version_newer")
		end
		if stored == self.version then
			return self:load_sizes()
		end
		self:migrate(stored)
	end)
end

function Store:load_sizes()
	local manager = self.manager
	manager.backend:Sizes(self.namespace, function(ok, sizes)
		if not ok then
			return self:fail_load("storage.load_failed", { namespace = self.namespace, reason = sizes })
		end
		self:set_sizes(sizes)
		self.ready = true
		self:release_waiting()
	end)
end

function Store:set_sizes(sizes)
	self.sizes, self.count, self.bytes = {}, 0, 0
	for key, size in pairs(sizes) do
		self.sizes[key] = size
		self.count = self.count + 1
		self.bytes = self.bytes + size
	end
end

-- Logs, makes every operation fail and, with `fail_reason`, fails the owning package.
function Store:fail_load(log_key, params, fail_reason)
	local manager = self.manager
	self.unavailable = true
	manager.log:For(self.owner, "storage"):Error(log_key, params)
	if fail_reason and manager.fail then
		manager.fail(self.owner, fail_reason, params)
	end
	self:release_waiting()
end

-- Runs migrations from `stored` (nil means version 1 when data exists) up to self.version on
-- every decoded value, then writes the differences and the new version in one transaction.
function Store:migrate(stored)
	local manager = self.manager
	manager.backend:All(self.namespace, function(ok, texts)
		if not ok then
			return self:fail_load("storage.load_failed", { namespace = self.namespace, reason = texts })
		end
		local entries, empty = {}, next(texts) == nil
		for key, text in pairs(texts) do
			local decoded, value = manager.json.Decode(text)
			if not decoded then
				return self:fail_load("storage.migration_failed", {
					namespace = self.namespace,
					from = stored or 1,
					reason = manager.messages:Format(
						"error.storage_corrupt",
						{ namespace = self.namespace, key = key }
					),
				}, "reason.store_migration_failed")
			end
			entries[key] = value
		end
		local from = stored or (empty and self.version or 1)
		for version = from, self.version - 1 do
			local info = {
				owner = self.owner,
				kind = "store_migration",
				fields = { namespace = self.namespace, from = version },
			}
			local called, result = manager.invoker:Call(info, self.migrations[version], entries)
			local reason = not called and manager.messages:Format("reason.migration_raised")
				or self:check_entries(result)
			if reason then
				return self:fail_load("storage.migration_failed", {
					namespace = self.namespace,
					from = version,
					reason = reason,
				}, "reason.store_migration_failed")
			end
			entries = result
		end
		local operations, sizes = {}, {}
		for key, value in pairs(entries) do
			local text = manager.json.Encode(value)
			sizes[key] = #key + #text
			if texts[key] ~= text then
				operations[#operations + 1] = { namespace = self.namespace, op = "set", key = key, value = text }
			end
		end
		for key in pairs(texts) do
			if entries[key] == nil then
				operations[#operations + 1] = { namespace = self.namespace, op = "delete", key = key }
			end
		end
		operations[#operations + 1] =
			{ namespace = Stores.VERSIONS, op = "set", key = self.namespace, value = tostring(self.version) }
		manager.backend:Write(operations, function(written, reason)
			if not written then
				return self:fail_load("storage.migration_failed", {
					namespace = self.namespace,
					from = from,
					reason = tostring(reason),
				}, "reason.store_migration_failed")
			end
			if from < self.version then
				manager.log:For(self.owner, "storage"):Info("storage.migrated", {
					namespace = self.namespace,
					from = from,
					to = self.version,
					changes = #operations - 1,
				})
			end
			self:set_sizes(sizes)
			self.ready = true
			self:release_waiting()
		end)
	end)
end

-- Returns nil when a migration result can be stored, or a reason text.
function Store:check_entries(result)
	local manager = self.manager
	if type(result) ~= "table" then
		return manager.messages:Format("reason.migration_result", { type = type(result) })
	end
	for key, value in pairs(result) do
		if not valid_key(key) then
			return manager.messages:Format("reason.migration_key", { key = tostring(key) })
		end
		local text, reason, params = manager.json.Encode(value)
		if not text then
			return manager.messages:Format(reason, params)
		end
	end
	return nil
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
