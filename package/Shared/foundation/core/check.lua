-- `level` as for error(), seen from the public function doing the check (default 2).

local Check = {}
Check.__index = Check

local TYPE_NAMES = {
	["any"] = true,
	["nil"] = true,
	["string"] = true,
	["number"] = true,
	["integer"] = true,
	["boolean"] = true,
	["table"] = true,
	["function"] = true,
	["userdata"] = true,
}

local function is_integral(value)
	return math.type(value) == "integer"
		or (
			math.type(value) == "float"
			and value == math.floor(value)
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
		)
end

local function matches(value, type_name)
	if type_name == "any" then
		return value ~= nil
	elseif type_name == "integer" then
		return is_integral(value)
	end
	return type(value) == type_name
end

function Check.new(errors)
	return setmetatable({ errors = errors }, Check)
end

function Check:Argument(api, index, name, value, expected, level)
	local optional = expected:sub(-1) == "?"
	local type_name = optional and expected:sub(1, -2) or expected
	if not TYPE_NAMES[type_name] then
		self.errors:Raise("invalid_value", {
			api = "Check:Argument",
			index = 5,
			name = "expected",
			reason = self.errors.messages:Format("reason.unsupported_type", { type = tostring(expected) }),
		})
	end
	if (optional and value == nil) or matches(value, type_name) then
		return value
	end
	self.errors:Raise("invalid_argument", {
		api = api,
		index = index,
		name = name,
		expected = expected,
		actual = type(value),
	}, (level or 2) + 1)
end

function Check:NonEmptyString(api, index, name, value, level)
	self:Argument(api, index, name, value, "string", (level or 2) + 1)
	if value == "" then
		self.errors:Raise("invalid_value", {
			api = api,
			index = index,
			name = name,
			reason = self.errors.messages:Format("reason.empty_string"),
		}, (level or 2) + 1)
	end
	return value
end

function Check:OneOf(api, index, name, value, allowed, level)
	for _, candidate in ipairs(allowed) do
		if value == candidate then
			return value
		end
	end
	local listed = {}
	for position, candidate in ipairs(allowed) do
		listed[position] = tostring(candidate)
	end
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.errors.messages:Format("reason.not_one_of", { allowed = table.concat(listed, ", ") }),
	}, (level or 2) + 1)
end

return Check
