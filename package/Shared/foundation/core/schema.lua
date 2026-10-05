local Schema = {}
Schema.__index = Schema

local Node = {}
Node.__index = Node

Schema.DEFAULT_LIMITS = { max_depth = 16, max_items = 10000, max_problems = 20 }

local IDENTIFIER = "^[%a_][%w_]*$"

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

local function is_integral(value)
	return math.type(value) == "integer" or value == math.floor(value)
end

local function describe_type(value)
	if math.type(value) == "integer" then
		return "integer"
	end
	return type(value)
end

local function child_path(path, key)
	if type(key) == "number" then
		return path .. "[" .. key .. "]"
	elseif type(key) == "string" and key:match(IDENTIFIER) then
		return path .. "." .. key
	end
	return path .. "[" .. string.format("%q", tostring(key)) .. "]"
end

-- options: errors, check, keys, invoker (for custom validators).
function Schema.new(options)
	return setmetatable({
		errors = options.errors,
		messages = options.errors.messages,
		check = options.check,
		keys = options.keys,
		invoker = options.invoker,
	}, Schema)
end

function Schema.IsSchema(value)
	return type(value) == "table" and getmetatable(value) == Node
end

function Schema:node(fields)
	return setmetatable(fields, Node)
end

-- Helpers below take `level` like Check: 3 when called directly from a public builder.
function Schema:options(api, index, value, allowed, level)
	level = level or 3
	self.check:Argument(api, index, "options", value, "table?", level)
	for key in pairs(value or {}) do
		if not allowed[key] then
			self.errors:Raise("invalid_value", {
				api = api,
				index = index,
				name = "options",
				reason = self.messages:Format("reason.manifest_unknown_field", { field = tostring(key) }),
			}, level)
		end
	end
	return value or {}
end

function Schema:bound(api, name, value, type_name, level)
	level = level or 3
	self.check:Argument(api, 1, "options." .. name, value, type_name .. "?", level)
	if value ~= nil and (value ~= value or value == math.huge or value == -math.huge) then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "options." .. name,
			reason = self.messages:Format("validation.finite"),
		}, level)
	end
	return value
end

function Schema:require_schema(api, index, name, value)
	if not Schema.IsSchema(value) then
		self.errors:Raise("invalid_argument", {
			api = api,
			index = index,
			name = name,
			expected = "schema",
			actual = type(value),
		}, 3)
	end
	return value
end

function Schema:String(options)
	local api = "Foundation.Schema.String"
	options = self:options(api, 1, options, { min = true, max = true, pattern = true })
	local min = self:bound(api, "min", options.min, "integer")
	local max = self:bound(api, "max", options.max, "integer")
	self.check:Argument(api, 1, "options.pattern", options.pattern, "string?", 2)
	if (min and min < 0) or (max and max < (min or 0)) then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "options",
			reason = self.messages:Format("reason.schema_bounds"),
		})
	end
	return self:node({ kind = "string", min = min, max = max, pattern = options.pattern })
end

function Schema:number_node(api, kind, options)
	options = self:options(api, 1, options, { min = true, max = true }, 4)
	local min = self:bound(api, "min", options.min, "number", 4)
	local max = self:bound(api, "max", options.max, "number", 4)
	if min and max and max < min then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "options",
			reason = self.messages:Format("reason.schema_bounds"),
		}, 3)
	end
	return self:node({ kind = kind, min = min, max = max })
end

function Schema:Number(options)
	local node = self:number_node("Foundation.Schema.Number", "number", options)
	return node
end

function Schema:Integer(options)
	local node = self:number_node("Foundation.Schema.Integer", "integer", options)
	return node
end

function Schema:Boolean()
	return self:node({ kind = "boolean" })
end

function Schema:Any()
	return self:node({ kind = "any" })
end

function Schema:Enum(values)
	local api = "Foundation.Schema.Enum"
	self.check:Argument(api, 1, "values", values, "table")
	if #values == 0 then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = "values",
			reason = self.messages:Format("reason.empty_list"),
		})
	end
	local allowed, listed = {}, {}
	for index, value in ipairs(values) do
		allowed[value] = true
		listed[index] = tostring(value)
	end
	return self:node({ kind = "enum", allowed = allowed, listed = table.concat(listed, ", ") })
end

function Schema:Optional(schema, default)
	self:require_schema("Foundation.Schema.Optional", 1, "schema", schema)
	local node = {}
	for key, value in pairs(schema) do
		node[key] = value
	end
	node.optional = true
	node.default = copy(default)
	return self:node(node)
end

function Schema:Record(fields, options)
	local api = "Foundation.Schema.Record"
	self.check:Argument(api, 1, "fields", fields, "table")
	options = self:options(api, 2, options, { extra = true })
	local extra = options.extra or "reject"
	self.check:OneOf(api, 2, "options.extra", extra, { "reject", "allow", "strip" })
	local names = {}
	for name, field in pairs(fields) do
		self.check:Argument(api, 1, "fields key", name, "string")
		self:require_schema(api, 1, "fields." .. name, field)
		names[#names + 1] = name
	end
	table.sort(names)
	return self:node({ kind = "record", fields = fields, names = names, extra = extra })
end

function Schema:List(schema, options)
	local api = "Foundation.Schema.List"
	self:require_schema(api, 1, "schema", schema)
	options = self:options(api, 2, options, { min = true, max = true })
	return self:node({
		kind = "list",
		item = schema,
		min = self:bound(api, "min", options.min, "integer"),
		max = self:bound(api, "max", options.max, "integer"),
	})
end

function Schema:Map(key_schema, value_schema, options)
	local api = "Foundation.Schema.Map"
	self:require_schema(api, 1, "key_schema", key_schema)
	self:require_schema(api, 2, "value_schema", value_schema)
	options = self:options(api, 3, options, { max = true })
	return self:node({
		kind = "map",
		key = key_schema,
		value = value_schema,
		max = self:bound(api, "max", options.max, "integer"),
	})
end

-- fn(value) returns true, or false and an already localized reason.
function Schema:Custom(key, fn)
	local api = "Foundation.Schema.Custom"
	local checked = self.keys:Check(api, 1, "key", key)
	self.check:Argument(api, 2, "fn", fn, "function")
	local owner = self.keys.Split(checked)
	return self:node({
		kind = "custom",
		key = checked,
		fn = fn,
		info = { owner = owner, kind = "validator", fields = { validator = checked } },
	})
end

local Run = {}
Run.__index = Run

function Run:problem(path, reason, params)
	self.count = self.count + 1
	if #self.problems < self.limits.max_problems then
		self.problems[#self.problems + 1] = {
			path = path,
			reason = reason,
			params = params,
			message = self.messages:Format("validation.problem", {
				path = path,
				reason = self.messages:Format(reason, params),
			}),
		}
	end
	return nil
end

function Run:check(node, value, path, depth)
	self.items = self.items + 1
	if self.items > self.limits.max_items then
		self.aborted = true
		return self:problem(path, "validation.too_many_items", { max = self.limits.max_items })
	end
	if depth > self.limits.max_depth then
		return self:problem(path, "validation.depth", { max = self.limits.max_depth })
	end
	if value == nil then
		if node.optional then
			return copy(node.default), true
		end
		return self:problem(path, "validation.required")
	end
	local handler = self[node.kind]
	return handler(self, node, value, path, depth)
end

function Run:type_problem(path, expected, value)
	return self:problem(path, "validation.type", { expected = expected, actual = describe_type(value) })
end

function Run:any(_, value)
	return value, true
end

function Run:boolean(_, value, path)
	if type(value) ~= "boolean" then
		return self:type_problem(path, "boolean", value)
	end
	return value, true
end

function Run:number(node, value, path)
	if type(value) ~= "number" then
		return self:type_problem(path, node.kind, value)
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return self:problem(path, "validation.finite")
	end
	if node.kind == "integer" and not is_integral(value) then
		return self:problem(path, "validation.integer")
	end
	if node.min and value < node.min then
		return self:problem(path, "validation.number_min", { min = node.min })
	end
	if node.max and value > node.max then
		return self:problem(path, "validation.number_max", { max = node.max })
	end
	return value, true
end

Run.integer = Run.number

function Run:string(node, value, path)
	if type(value) ~= "string" then
		return self:type_problem(path, "string", value)
	end
	local length = utf8.len(value)
	if not length then
		return self:problem(path, "validation.utf8")
	end
	if node.min and length < node.min then
		return self:problem(path, "validation.string_min", { min = node.min })
	end
	if node.max and length > node.max then
		return self:problem(path, "validation.string_max", { max = node.max })
	end
	if node.pattern and not value:find(node.pattern) then
		return self:problem(path, "validation.pattern")
	end
	return value, true
end

function Run:enum(node, value, path)
	if not node.allowed[value] then
		return self:problem(path, "validation.enum", { allowed = node.listed })
	end
	return value, true
end

function Run:record(node, value, path, depth)
	if type(value) ~= "table" then
		return self:type_problem(path, "table", value)
	end
	local result, ok = {}, true
	for _, name in ipairs(node.names) do
		local checked, valid = self:check(node.fields[name], value[name], child_path(path, name), depth + 1)
		if valid then
			result[name] = checked
		else
			ok = false
		end
		if self.aborted then
			return nil
		end
	end
	for key, item in pairs(value) do
		if node.fields[key] == nil then
			if node.extra == "reject" then
				ok = self:problem(child_path(path, key), "validation.unknown_field") or false
			elseif node.extra == "allow" then
				result[key] = copy(item)
			end
		end
	end
	if not ok then
		return nil
	end
	return result, true
end

function Run:list(node, value, path, depth)
	if type(value) ~= "table" then
		return self:type_problem(path, "list", value)
	end
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	for index = 1, count do
		if value[index] == nil then
			return self:problem(path, "validation.not_list")
		end
	end
	if node.min and count < node.min then
		return self:problem(path, "validation.list_min", { min = node.min })
	end
	if node.max and count > node.max then
		return self:problem(path, "validation.list_max", { max = node.max })
	end
	local result, ok = {}, true
	for index = 1, count do
		local checked, valid = self:check(node.item, value[index], child_path(path, index), depth + 1)
		if valid then
			result[index] = checked
		else
			ok = false
		end
		if self.aborted then
			return nil
		end
	end
	if not ok then
		return nil
	end
	return result, true
end

function Run:map(node, value, path, depth)
	if type(value) ~= "table" then
		return self:type_problem(path, "table", value)
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	if node.max and #keys > node.max then
		return self:problem(path, "validation.map_max", { max = node.max })
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local result, ok = {}, true
	for _, key in ipairs(keys) do
		local item_path = child_path(path, key)
		local checked_key, key_valid = self:check(node.key, key, item_path, depth + 1)
		local checked_value, value_valid = self:check(node.value, value[key], item_path, depth + 1)
		if key_valid and value_valid then
			result[checked_key] = checked_value
		else
			ok = false
		end
		if self.aborted then
			return nil
		end
	end
	if not ok then
		return nil
	end
	return result, true
end

function Run:custom(node, value, path)
	local called, valid, reason = self.invoker:Call(node.info, node.fn, value)
	if not called then
		return self:problem(path, "validation.custom_failed", { name = node.key })
	end
	if valid ~= true then
		return self:problem(path, "validation.custom", { reason = tostring(reason or node.key) })
	end
	return value, true
end

-- Returns the validated copy (defaults applied), or nil and a `validation_failed` error.
function Schema:Validate(schema, value, limits)
	local api = "Foundation.Schema.Validate"
	self:require_schema(api, 1, "schema", schema)
	self.check:Argument(api, 3, "limits", limits, "table?")
	local merged = {}
	for key, default in pairs(Schema.DEFAULT_LIMITS) do
		merged[key] = default
	end
	for key, limit in pairs(limits or {}) do
		if Schema.DEFAULT_LIMITS[key] == nil then
			self.errors:Raise("invalid_value", {
				api = api,
				index = 3,
				name = "limits",
				reason = self.messages:Format("reason.manifest_unknown_field", { field = tostring(key) }),
			})
		end
		self.check:Argument(api, 3, "limits." .. key, limit, "integer")
		merged[key] = limit
	end
	local run = setmetatable({
		messages = self.messages,
		invoker = self.invoker,
		limits = merged,
		items = 0,
		count = 0,
		problems = {},
	}, Run)
	local result, valid = run:check(schema, value, "$", 1)
	if valid then
		return result
	end
	return nil,
		self.errors:New("validation_failed", {
			count = run.count,
			first = run.problems[1] and run.problems[1].message or "$",
		}, { details = { problems = run.problems, count = run.count } })
end

return Schema
