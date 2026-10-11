-- Persistent data bound to subjects (account ids or other identifiers). Each package writes
-- the keys it defines, in its own internal store; any package can read them.
local Data = {}
Data.__index = Data

local Key = {}
Key.__index = Key

local Reader = {}
Reader.__index = Reader

Data.MAX_SUBJECT_LENGTH = 128
Data.MAX_NAME_LENGTH = 64

local NAME_PATTERN = "^[a-z0-9_.-]+$"
local DEFINE_OPTIONS = { default = true }

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

-- options: check, keys, schema, stores, backend (nil when unavailable), futures, json
function Data.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		keys = options.keys,
		S = options.schema,
		stores = options.stores,
		backend = options.backend,
		futures = options.futures,
		json = options.json,
		defined = {},
	}, Data)
end

function Data.Namespace(owner)
	return "data:" .. owner
end

local function storage_key(name, subject)
	return name .. "|" .. subject
end

function Data:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

-- Subjects are strings or player senders (their account id). `level` as for Check.
function Data:subject(api, subject, level)
	if type(subject) == "table" and type(subject.GetKind) == "function" and subject:GetKind() == "player" then
		subject = tostring(subject:GetId())
	end
	if type(subject) ~= "string" or subject == "" or #subject > Data.MAX_SUBJECT_LENGTH or subject:find("%c") then
		self:invalid(api, 1, "subject", "reason.data_subject", { max = Data.MAX_SUBJECT_LENGTH }, level + 1)
	end
	return subject
end

-- Returns the key object, its release function, and the internal store's release and start
-- functions when the store was opened by this call.
function Data:Define(owner, name, schema, options, api, level)
	self.check:Argument(api, 1, "name", name, "string", level)
	if #name > Data.MAX_NAME_LENGTH or not name:match(NAME_PATTERN) then
		self:invalid(api, 1, "name", "reason.data_name", { max = Data.MAX_NAME_LENGTH }, level)
	end
	if not self.S.IsSchema(schema) then
		self.errors:Raise("invalid_argument", {
			api = api,
			index = 2,
			name = "schema",
			expected = "schema",
			actual = type(schema),
		}, level)
	end
	self.check:Argument(api, 3, "options", options, "table?", level)
	options = options or {}
	for field in pairs(options) do
		if not DEFINE_OPTIONS[field] then
			self:invalid(api, 3, "options", "reason.manifest_unknown_field", { field = tostring(field) }, level)
		end
	end
	if options.default ~= nil then
		local _, err = self.S:Validate(schema, options.default)
		if err then
			self:invalid(api, 3, "options.default", "reason.config_default", {
				problem = err.details.problems[1] and err.details.problems[1].message or err.message,
			}, level)
		end
	end
	local full = owner .. ":" .. name
	if self.defined[full] then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.messages:Format("reason.data_defined", { key = full }),
		}, level)
	end
	local store, store_release, start = self.stores:OpenNamespace(owner, Data.Namespace(owner))
	local key = setmetatable({
		manager = self,
		owner = owner,
		name = name,
		full = full,
		schema = schema,
		default = copy(options.default),
		store = store,
		active = true,
	}, Key)
	self.defined[full] = key
	return key,
		function()
			key.active = false
			if self.defined[full] == key then
				self.defined[full] = nil
			end
		end,
		store_release,
		start
end

function Key:guard(api)
	if not self.active then
		local manager = self.manager
		manager.errors:Raise("invalid_state", {
			api = api,
			reason = manager.messages:Format("reason.data_closed", { key = self.full }),
		}, 3)
	end
end

function Key:GetName()
	return self.full
end

-- Resolves with the value, or a copy of the default when the subject has none.
function Key:Get(subject)
	self:guard("data:Get")
	subject = self.manager:subject("data:Get", subject, 2)
	local default = self.default
	return self.store:Get(storage_key(self.name, subject)):Then(function(value)
		if value == nil then
			return copy(default)
		end
		return value
	end)
end

function Key:Set(subject, value)
	self:guard("data:Set")
	local manager = self.manager
	subject = manager:subject("data:Set", subject, 2)
	local checked, err = manager.S:Validate(self.schema, value)
	if err then
		manager:invalid("data:Set", 2, "value", "reason.data_value", {
			key = self.full,
			problem = err.details.problems[1] and err.details.problems[1].message or err.message,
		}, 2)
	end
	local text = self.store:encode("data:Set", 2, checked)
	return self.store:put("data:Set", storage_key(self.name, subject), text)
end

-- Resolves with whether the subject had a value.
function Key:Delete(subject)
	self:guard("data:Delete")
	subject = self.manager:subject("data:Delete", subject, 2)
	return self.store:Delete(storage_key(self.name, subject))
end

-- Read-only access to another package's (or one's own) data key. Futures belong to the reader.
function Data:Reader(reader_owner, key, api, level)
	local full = self.keys:Check(api, 1, "key", key, nil, level)
	local owner, name = self.keys.Split(full)
	return setmetatable({ manager = self, reader = reader_owner, owner = owner, name = name, full = full }, Reader)
end

function Reader:GetName()
	return self.full
end

-- Resolves with the stored value or nil; defaults are known only to the defining package.
function Reader:Get(subject)
	local manager = self.manager
	subject = manager:subject("reader:Get", subject, 2)
	local future = manager.futures:Create(self.reader)
	if not manager.backend then
		future:Reject(
			manager.errors:New(
				"storage_unavailable",
				{ namespace = Data.Namespace(self.owner) },
				{ owner = self.reader }
			)
		)
		return future
	end
	manager.backend:Get(Data.Namespace(self.owner), storage_key(self.name, subject), function(ok, text)
		if not ok then
			return future:Reject(manager.errors:New("storage_failed", { namespace = Data.Namespace(self.owner) }, {
				owner = self.reader,
				cause = text,
			}))
		end
		if text == nil then
			return future:Resolve(nil)
		end
		local decoded, value = manager.json.Decode(text)
		if not decoded then
			return future:Reject(manager.errors:New("storage_corrupt", {
				namespace = Data.Namespace(self.owner),
				key = storage_key(self.name, subject),
			}, { owner = self.reader }))
		end
		future:Resolve(value)
	end)
	return future
end

return Data
