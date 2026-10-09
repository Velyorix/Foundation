local Events = {}
Events.__index = Events

local Event = {}
Event.__index = Event

Events.PRIORITIES = { "lowest", "low", "normal", "high", "highest", "monitor" }
Events.MAX_DEPTH = 16

local PRIORITY_RANK = {}
for rank, name in ipairs(Events.PRIORITIES) do
	PRIORITY_RANK[name] = rank
end
local MONITOR = PRIORITY_RANK.monitor

local DEFINITION_FIELDS = { fields = true, mutable = true, cancellable = true }
local LISTEN_OPTIONS = { priority = true, ignore_cancelled = true }

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

local function copy_list(list)
	local result = {}
	for index, item in ipairs(list) do
		result[index] = item
	end
	return result
end

-- options: check, keys, schema, invoker, ownership
function Events.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		keys = options.keys,
		S = options.schema,
		invoker = options.invoker,
		ownership = options.ownership,
		definitions = {},
		sequence = 0,
		depth = 0,
		dispatched = 0,
	}, Events)
end

-- `level` as for Check: 2 is the caller of the Events method.
function Events:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

function Events:state_error(api, reason_key, params, level)
	self.errors:Raise("invalid_state", { api = api, reason = self.messages:Format(reason_key, params) }, level + 1)
end

function Events:unknown_options(api, index, name, value, allowed, level)
	for key in pairs(value) do
		if not allowed[key] then
			self:invalid(api, index, name, "reason.manifest_unknown_field", { field = tostring(key) }, level + 1)
		end
	end
end

function Events:definition_for(api, index, key, level)
	local definition = self.definitions[key]
	if not definition then
		self:invalid(api, index, "name", "reason.event_unknown", { name = key }, level + 1)
	end
	return definition
end

-- Returns the event key and a release function for the owner's resource tracking.
function Events:Define(owner, name, spec, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner, owner = owner }, level)
	local check = self.check
	check:Argument(api, 2, "definition", spec, "table?", level)
	spec = spec or {}
	self:unknown_options(api, 2, "definition", spec, DEFINITION_FIELDS, level)
	check:Argument(api, 2, "definition.fields", spec.fields, "table?", level)
	check:Argument(api, 2, "definition.mutable", spec.mutable, "table?", level)
	check:Argument(api, 2, "definition.cancellable", spec.cancellable, "boolean?", level)
	local fields = {}
	for field, schema in pairs(spec.fields or {}) do
		check:Argument(api, 2, "definition.fields key", field, "string", level)
		if not self.S.IsSchema(schema) then
			self.errors:Raise("invalid_argument", {
				api = api,
				index = 2,
				name = "definition.fields." .. field,
				expected = "schema",
				actual = type(schema),
			}, level + 1)
		end
		fields[field] = schema
	end
	local mutable = {}
	for _, field in ipairs(spec.mutable or {}) do
		if fields[field] == nil then
			self:invalid(
				api,
				2,
				"definition.mutable",
				"reason.event_mutable_unknown",
				{ field = tostring(field) },
				level
			)
		end
		mutable[field] = true
	end
	local existing = self.definitions[key]
	if existing then
		self:state_error(api, "reason.event_defined", { name = key, owner = existing.owner }, level)
	end

	local definition = {
		key = key,
		owner = owner,
		fields = fields,
		record = self.S:Record(fields),
		mutable = mutable,
		cancellable = spec.cancellable == true,
		listeners = {},
		dispatched = 0,
	}
	self.definitions[key] = definition
	return key,
		function()
			if self.definitions[key] == definition then
				self.definitions[key] = nil
			end
			for _, listener in ipairs(copy_list(definition.listeners)) do
				listener.handle:Release()
			end
		end
end

local function insert_sorted(listeners, listener)
	local position = #listeners + 1
	for index, other in ipairs(listeners) do
		if other.rank > listener.rank then
			position = index
			break
		end
	end
	table.insert(listeners, position, listener)
end

local function remove(listeners, listener)
	for index, other in ipairs(listeners) do
		if other == listener then
			table.remove(listeners, index)
			return
		end
	end
end

-- Returns the ownership handle of the listener.
function Events:Listen(owner, name, fn, options, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner }, level)
	local check = self.check
	check:Argument(api, 2, "fn", fn, "function", level)
	check:Argument(api, 3, "options", options, "table?", level)
	options = options or {}
	self:unknown_options(api, 3, "options", options, LISTEN_OPTIONS, level)
	local priority = options.priority or "normal"
	check:OneOf(api, 3, "options.priority", priority, Events.PRIORITIES, level)
	check:Argument(api, 3, "options.ignore_cancelled", options.ignore_cancelled, "boolean?", level)
	local definition = self:definition_for(api, 1, key, level)
	for _, other in ipairs(definition.listeners) do
		if other.owner == owner and other.fn == fn then
			self:state_error(api, "reason.event_duplicate", { name = key }, level)
		end
	end

	self.sequence = self.sequence + 1
	local listener = {
		owner = owner,
		fn = fn,
		rank = PRIORITY_RANK[priority],
		ignore_cancelled = options.ignore_cancelled == true,
		active = true,
		info = { owner = owner, kind = "event_listener", fields = { event = key, priority = priority } },
	}
	listener.handle = self.ownership:Track(owner, "event_listener", function()
		listener.active = false
		remove(definition.listeners, listener)
	end, { event = key, priority = priority })
	insert_sorted(definition.listeners, listener)
	return listener.handle
end

-- Runs the listeners and returns the event once they all ran.
function Events:Emit(owner, name, payload, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner, owner = owner }, level)
	self.check:Argument(api, 2, "payload", payload, "table?", level)
	local definition = self:definition_for(api, 1, key, level)
	local data, err = self.S:Validate(definition.record, payload or {})
	if not data then
		self:invalid(api, 2, "payload", "reason.event_payload", {
			name = key,
			problem = err.details.problems[1] and err.details.problems[1].message or err.message,
		}, level)
	end
	if self.depth >= Events.MAX_DEPTH then
		self:state_error(api, "reason.event_depth", { max = Events.MAX_DEPTH }, level)
	end

	local event = setmetatable({ manager = self, definition = definition, data = data, cancelled = false }, Event)
	definition.dispatched = definition.dispatched + 1
	self.dispatched = self.dispatched + 1
	self.depth = self.depth + 1
	for _, listener in ipairs(copy_list(definition.listeners)) do
		if listener.active and not (event.cancelled and listener.ignore_cancelled) then
			event.listener = listener
			self.invoker:Call(listener.info, listener.fn, event)
		end
	end
	event.listener = nil
	event.finished = true
	self.depth = self.depth - 1
	return event
end

function Events:Snapshot()
	local events, count = {}, 0
	for key, definition in pairs(self.definitions) do
		count = count + 1
		events[key] = {
			owner = definition.owner,
			cancellable = definition.cancellable,
			listeners = #definition.listeners,
			dispatched = definition.dispatched,
		}
	end
	return { defined = count, dispatched = self.dispatched, events = events }
end

function Event:GetName()
	return self.definition.key
end

function Event:IsCancellable()
	return self.definition.cancellable
end

function Event:IsCancelled()
	return self.cancelled
end

function Event:Get(field)
	local manager = self.manager
	manager.check:Argument("event:Get", 1, "field", field, "string")
	if self.definition.fields[field] == nil then
		manager:invalid("event:Get", 1, "field", "reason.event_field_unknown", {
			field = field,
			name = self.definition.key,
		}, 2)
	end
	return copy(self.data[field])
end

function Event:GetData()
	return copy(self.data)
end

-- Changes are only possible from a listener below the monitor priority.
function Event:writable(api)
	local listener = self.listener
	if self.finished or not listener then
		self.manager:state_error(api, "reason.event_finished", { name = self.definition.key }, 3)
	end
	if listener.rank == MONITOR then
		self.manager:state_error(api, "reason.event_monitor", nil, 3)
	end
end

function Event:Set(field, value)
	local manager = self.manager
	local definition = self.definition
	manager.check:Argument("event:Set", 1, "field", field, "string")
	self:writable("event:Set")
	if not definition.mutable[field] then
		manager:invalid("event:Set", 1, "field", "reason.event_field_immutable", {
			field = field,
			name = definition.key,
		}, 2)
	end
	local checked, err = manager.S:Validate(definition.fields[field], value)
	if checked == nil and err then
		manager:invalid("event:Set", 2, "value", "reason.event_payload", {
			name = definition.key,
			problem = err.details.problems[1] and err.details.problems[1].message or err.message,
		}, 2)
	end
	self.data[field] = checked
end

function Event:SetCancelled(cancelled)
	local manager = self.manager
	manager.check:Argument("event:SetCancelled", 1, "cancelled", cancelled, "boolean")
	self:writable("event:SetCancelled")
	if not self.definition.cancellable then
		manager:state_error("event:SetCancelled", "reason.event_not_cancellable", { name = self.definition.key }, 2)
	end
	self.cancelled = cancelled
end

function Event:Cancel()
	local manager = self.manager
	self:writable("event:Cancel")
	if not self.definition.cancellable then
		manager:state_error("event:Cancel", "reason.event_not_cancellable", { name = self.definition.key }, 2)
	end
	self.cancelled = true
end

return Events
