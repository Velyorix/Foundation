-- Deterministic encoder: object keys are sorted, empty tables encode as {}.
-- Failures return nil plus a message key and its params.

local Json = {}

local MAX_DEPTH = 32

local ESCAPES = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function encode_string(text)
	return '"'
		.. text:gsub('[%c"\\]', function(char)
			return ESCAPES[char] or string.format("\\u%04x", char:byte())
		end)
		.. '"'
end

local function encode_number(value, path)
	if math.type(value) == "integer" then
		return string.format("%d", value)
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil, "reason.json_non_finite", { path = path }
	end
	local short = string.format("%.14g", value)
	if tonumber(short) ~= value then
		short = string.format("%.17g", value)
	end
	if not short:find("[%.eE]") then
		short = short .. ".0"
	end
	return short
end

local function array_length(value)
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	for index = 1, count do
		if value[index] == nil then
			return nil
		end
	end
	return count
end

local encode_value

local function encode_table(value, path, depth, active)
	if active[value] then
		return nil, "reason.json_cycle", { path = path }
	end
	if depth > MAX_DEPTH then
		return nil, "reason.json_depth", { path = path, max = MAX_DEPTH }
	end
	active[value] = true
	local parts = {}
	local length = next(value) ~= nil and array_length(value)
	if length then
		for index = 1, length do
			local encoded, reason, params = encode_value(value[index], path .. "[" .. index .. "]", depth + 1, active)
			if not encoded then
				return nil, reason, params
			end
			parts[index] = encoded
		end
		active[value] = nil
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for key in pairs(value) do
		if type(key) ~= "string" then
			return nil, "reason.json_key_type", { path = path, type = type(key) }
		end
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for index, key in ipairs(keys) do
		local encoded, reason, params = encode_value(value[key], path .. "." .. key, depth + 1, active)
		if not encoded then
			return nil, reason, params
		end
		parts[index] = encode_string(key) .. ":" .. encoded
	end
	active[value] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(value, path, depth, active)
	local kind = type(value)
	if kind == "string" then
		return encode_string(value)
	elseif kind == "number" then
		return encode_number(value, path)
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "nil" then
		return "null"
	elseif kind == "table" then
		return encode_table(value, path, depth, active)
	end
	return nil, "reason.json_unsupported_type", { path = path, type = kind }
end

function Json.Encode(value)
	return encode_value(value, "$", 1, {})
end

return Json
