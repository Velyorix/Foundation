local Arguments = {}
Arguments.__index = Arguments

Arguments.MAX_SUGGESTIONS = 50
Arguments.TRUE_WORDS = { ["true"] = true, yes = true, on = true }
Arguments.FALSE_WORDS = { ["false"] = true, no = true, off = true }

local NAME_PATTERN = "^[a-z][a-z0-9_]*$"
local DECLARATION_FIELDS = {
	name = true,
	type = true,
	optional = true,
	default = true,
	description = true,
	min = true,
	max = true,
	values = true,
}
local TYPE_FIELDS = { parse = true, suggest = true }

-- Splits a command line into words. Double quotes group words; inside them \" and \\
-- are escapes. Returns a list of { text, start }, or nil and a reason key.
function Arguments.Split(line)
	local tokens, position, length = {}, 1, #line
	while true do
		position = line:find("%S", position)
		if not position then
			return tokens
		end
		if line:sub(position, position) == '"' then
			local parts, index = {}, position + 1
			while true do
				local char = line:sub(index, index)
				if char == "" then
					return nil, "command.unclosed_quote"
				elseif char == "\\" and index < length then
					parts[#parts + 1] = line:sub(index + 1, index + 1)
					index = index + 2
				elseif char == '"' then
					break
				else
					parts[#parts + 1] = char
					index = index + 1
				end
			end
			tokens[#tokens + 1] = { text = table.concat(parts), start = position }
			position = index + 1
		else
			local finish = (line:find("%s", position) or length + 1) - 1
			tokens[#tokens + 1] = { text = line:sub(position, finish), start = position }
			position = finish + 1
		end
	end
end

local function finite(value)
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function bounds(declaration, value)
	if declaration.min and value < declaration.min then
		return nil, "argument.min", { min = declaration.min }
	end
	if declaration.max and value > declaration.max then
		return nil, "argument.max", { max = declaration.max }
	end
	return value
end

-- Built-in types: parse(declaration, text) returns the value or nil, reason key, params;
-- check(declaration, value) validates a default.
local BUILTIN = {
	string = {
		parse = function(declaration, text)
			local length = utf8.len(text)
			if not length then
				return nil, "argument.utf8"
			end
			if declaration.min and length < declaration.min then
				return nil, "argument.too_short", { min = declaration.min }
			end
			if declaration.max and length > declaration.max then
				return nil, "argument.too_long", { max = declaration.max }
			end
			return text
		end,
		check = function(_, value)
			return type(value) == "string"
		end,
		lengths = true,
	},
	integer = {
		parse = function(declaration, text)
			local value = text:match("^[+-]?%d+$") and math.tointeger(tonumber(text))
			if not value then
				return nil, "argument.integer"
			end
			return bounds(declaration, value)
		end,
		check = function(_, value)
			return math.type(value) == "integer"
		end,
		bounded = true,
	},
	number = {
		parse = function(declaration, text)
			local value = (text:match("^[+-]?%d+%.?%d*$") or text:match("^[+-]?%.%d+$")) and tonumber(text)
			if not value or not finite(value) then
				return nil, "argument.number"
			end
			return bounds(declaration, value)
		end,
		check = function(_, value)
			return type(value) == "number" and finite(value)
		end,
		bounded = true,
	},
	boolean = {
		parse = function(_, text)
			local word = text:lower()
			if Arguments.TRUE_WORDS[word] then
				return true
			elseif Arguments.FALSE_WORDS[word] then
				return false
			end
			return nil, "argument.boolean"
		end,
		check = function(_, value)
			return type(value) == "boolean"
		end,
		suggestions = { "true", "false" },
	},
	enum = {
		parse = function(declaration, text)
			local word = text:lower()
			for _, allowed in ipairs(declaration.values) do
				if allowed == word then
					return allowed
				end
			end
			return nil, "argument.enum", { allowed = table.concat(declaration.values, ", ") }
		end,
		check = function(declaration, value)
			for _, allowed in ipairs(declaration.values) do
				if allowed == value then
					return true
				end
			end
			return false
		end,
	},
}
BUILTIN.greedy = { parse = BUILTIN.string.parse, check = BUILTIN.string.check, lengths = true, greedy = true }

-- options: check, keys, invoker, log
function Arguments.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		keys = options.keys,
		invoker = options.invoker,
		log = options.log,
		types = {},
	}, Arguments)
end

-- Returns the type key and a release function for the owner's resource tracking.
function Arguments:RegisterType(owner, name, definition, api, level)
	local key = self.keys:Check(api, 1, "name", name, { default_namespace = owner, owner = owner }, level)
	local check = self.check
	check:Argument(api, 2, "definition", definition, "table", level)
	for field in pairs(definition) do
		if not TYPE_FIELDS[field] then
			self.errors:Raise("invalid_value", {
				api = api,
				index = 2,
				name = "definition",
				reason = self.messages:Format("reason.manifest_unknown_field", { field = tostring(field) }),
			}, level)
		end
	end
	check:Argument(api, 2, "definition.parse", definition.parse, "function", level)
	check:Argument(api, 2, "definition.suggest", definition.suggest, "function?", level)
	if self.types[key] then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.messages:Format("reason.argument_type_exists", { name = key }),
		}, level)
	end
	local registered = {
		key = key,
		owner = owner,
		parse = definition.parse,
		suggest = definition.suggest,
		info = { owner = owner, kind = "argument_type", fields = { type = key } },
	}
	self.types[key] = registered
	return key, function()
		if self.types[key] == registered then
			self.types[key] = nil
		end
	end
end

-- Compiles argument declarations. Returns the list, or nil, the failing field, and a
-- reason key with its params (false as reason key means a wrong type: params has
-- expected and actual).
function Arguments:Compile(list, path)
	if type(list) ~= "table" then
		return nil, path, false, { expected = "table?", actual = type(list) }
	end
	local compiled, names, optional_seen = {}, {}, false
	for index, declaration in ipairs(list) do
		local where = path .. "[" .. index .. "]"
		if type(declaration) ~= "table" then
			return nil, where, false, { expected = "table", actual = type(declaration) }
		end
		for field in pairs(declaration) do
			if not DECLARATION_FIELDS[field] then
				return nil, where, "reason.manifest_unknown_field", { field = tostring(field) }
			end
		end
		local name = declaration.name
		if type(name) ~= "string" or not name:match(NAME_PATTERN) then
			return nil, where .. ".name", "reason.argument_name", nil
		end
		if names[name] then
			return nil, where .. ".name", "reason.argument_duplicate", { name = name }
		end
		names[name] = true
		local type_name = declaration.type or "string"
		local builtin = BUILTIN[type_name]
		if not builtin and not self.types[type_name] then
			return nil, where .. ".type", "reason.argument_type_unknown", { name = tostring(type_name) }
		end
		for _, field in ipairs({ "min", "max" }) do
			local value = declaration[field]
			if value ~= nil and not (builtin and (builtin.bounded or builtin.lengths)) then
				return nil, where .. "." .. field, "reason.argument_option", { option = field, type = type_name }
			end
			if value ~= nil and (type(value) ~= "number" or not finite(value)) then
				return nil, where .. "." .. field, false, { expected = "number?", actual = type(value) }
			end
		end
		if declaration.values ~= nil and type_name ~= "enum" then
			return nil, where .. ".values", "reason.argument_option", { option = "values", type = type_name }
		end
		if type_name == "enum" then
			if type(declaration.values) ~= "table" or #declaration.values == 0 then
				return nil, where .. ".values", "reason.empty_list", nil
			end
			for _, value in ipairs(declaration.values) do
				if type(value) ~= "string" or value ~= value:lower() then
					return nil, where .. ".values", "reason.argument_enum_value", nil
				end
			end
		end
		if declaration.description ~= nil and type(declaration.description) ~= "string" then
			return nil, where .. ".description", false, { expected = "string?", actual = type(declaration.description) }
		end
		if declaration.optional ~= nil and type(declaration.optional) ~= "boolean" then
			return nil, where .. ".optional", false, { expected = "boolean?", actual = type(declaration.optional) }
		end
		local optional = declaration.optional == true or declaration.default ~= nil
		if optional_seen and not optional then
			return nil, where, "reason.argument_order", nil
		end
		optional_seen = optional_seen or optional
		if builtin and builtin.greedy and index ~= #list then
			return nil, where, "reason.argument_greedy", nil
		end
		local entry = {
			name = name,
			type = type_name,
			builtin = builtin,
			optional = optional,
			default = declaration.default,
			description = declaration.description,
			min = declaration.min,
			max = declaration.max,
			values = declaration.values,
		}
		if declaration.default ~= nil and builtin then
			local accepted = builtin.check(entry, declaration.default)
			if accepted and builtin.bounded then
				accepted = bounds(entry, declaration.default) ~= nil
			end
			if not accepted then
				return nil, where .. ".default", "reason.argument_default", { type = type_name }
			end
		end
		compiled[index] = entry
	end
	return compiled
end

function Arguments:usage_error(reason_key, params)
	return nil,
		self.errors:New("command_usage", { reason = self.messages:Format(reason_key, params) }, {
			details = { reason = reason_key, params = params },
		})
end

-- Returns the value of one argument, or nil, a reason key and params.
function Arguments:parse_one(declaration, text)
	local builtin = declaration.builtin
	if builtin then
		local value, reason, params = builtin.parse(declaration, text)
		if value == nil then
			params = params or {}
			params.name, params.value = declaration.name, text
		end
		return value, reason, params
	end
	local custom = self.types[declaration.type]
	if not custom then
		return nil, "argument.failed", { name = declaration.name }
	end
	local ok, value, reason = self.invoker:Call(custom.info, custom.parse, text)
	if not ok then
		return nil, "argument.failed", { name = declaration.name }
	end
	if value == nil then
		if type(reason) == "string" then
			return nil, "argument.custom", { reason = reason, name = declaration.name, value = text }
		end
		return nil, "argument.invalid", { name = declaration.name, value = text }
	end
	return value
end

-- tokens from Split, `first` the index of the first argument word, `line` the typed text.
-- Returns a table of values by argument name, or nil and a `command_usage` error.
function Arguments:Parse(declarations, tokens, first, line)
	local values = {}
	local index = first
	for _, declaration in ipairs(declarations or {}) do
		local token = tokens[index]
		if not token then
			if not declaration.optional then
				return self:usage_error("command.missing_argument", { name = declaration.name })
			end
			values[declaration.name] = declaration.default
		else
			local text = token.text
			if declaration.builtin and declaration.builtin.greedy then
				text = line:sub(token.start):match("^(.-)%s*$")
				index = #tokens
			end
			local value, reason, params = self:parse_one(declaration, text)
			if value == nil then
				return self:usage_error(reason, params)
			end
			values[declaration.name] = value
			index = index + 1
		end
	end
	if tokens[index] then
		local extra = {}
		for position = index, #tokens do
			extra[#extra + 1] = tokens[position].text
		end
		return self:usage_error("command.too_many", { extra = table.concat(extra, " ") })
	end
	return values
end

local function add_matching(result, seen, candidates, prefix)
	for _, candidate in ipairs(candidates) do
		if type(candidate) == "string" and not seen[candidate] and candidate:sub(1, #prefix):lower() == prefix then
			seen[candidate] = true
			result[#result + 1] = candidate
		end
	end
end

-- Suggestions for the argument `declaration` starting with `prefix`.
function Arguments:Suggest(declaration, prefix, result, seen)
	prefix = prefix:lower()
	local builtin = declaration.builtin
	if builtin then
		add_matching(result, seen, declaration.values or builtin.suggestions or {}, prefix)
		return
	end
	local custom = self.types[declaration.type]
	if custom and custom.suggest then
		local ok, candidates = self.invoker:Call(custom.info, custom.suggest, prefix)
		if ok and type(candidates) == "table" then
			add_matching(result, seen, candidates, prefix)
		end
	end
end

function Arguments:Snapshot()
	local types = {}
	for key, registered in pairs(self.types) do
		types[key] = registered.owner
	end
	return { types = types }
end

return Arguments
