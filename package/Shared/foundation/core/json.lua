-- Encode: deterministic (sorted keys, {} for empty tables); returns text or nil, reason, params.
-- Decode: strict RFC 8259; returns true, value or false, reason, params.

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

Json.DECODE_LIMITS = { max_bytes = 1048576, max_depth = 32 }

local DECODE_ESCAPES = {
	['"'] = '"',
	["\\"] = "\\",
	["/"] = "/",
	["b"] = "\b",
	["f"] = "\f",
	["n"] = "\n",
	["r"] = "\r",
	["t"] = "\t",
}

local Decoder = {}
Decoder.__index = Decoder

function Decoder:fail(position, reason, params)
	params = params or {}
	params.position = position
	error({ reason = reason, params = params }, 0)
end

function Decoder:skip(position)
	local _, finish = self.text:find("^[ \t\r\n]*", position)
	return finish + 1
end

function Decoder:number(position)
	local text = self.text
	local _, finish = text:find("^-?%d+", position)
	if not finish then
		self:fail(position, "reason.json_syntax")
	end
	local digits = text:sub(position, finish):gsub("^-", "")
	if #digits > 1 and digits:sub(1, 1) == "0" then
		self:fail(position, "reason.json_syntax")
	end
	local is_float = false
	local _, fraction_end = text:find("^%.%d+", finish + 1)
	if fraction_end then
		finish, is_float = fraction_end, true
	end
	local _, exponent_end = text:find("^[eE][+-]?%d+", finish + 1)
	if exponent_end then
		finish, is_float = exponent_end, true
	end
	local value = tonumber(text:sub(position, finish))
	if is_float then
		value = value + 0.0
	end
	return value, finish + 1
end

function Decoder:codepoint(position)
	local hex = self.text:match("^%x%x%x%x", position)
	if not hex then
		self:fail(position, "reason.json_syntax")
	end
	return tonumber(hex, 16)
end

function Decoder:string(position)
	local text = self.text
	local parts = {}
	local cursor = position + 1
	while true do
		local stop = text:find('["\\\0-\31]', cursor)
		if not stop then
			self:fail(position, "reason.json_syntax")
		end
		parts[#parts + 1] = text:sub(cursor, stop - 1)
		local char = text:sub(stop, stop)
		if char == '"' then
			return table.concat(parts), stop + 1
		elseif char ~= "\\" then
			self:fail(stop, "reason.json_syntax")
		end
		local escape = text:sub(stop + 1, stop + 1)
		if DECODE_ESCAPES[escape] then
			parts[#parts + 1] = DECODE_ESCAPES[escape]
			cursor = stop + 2
		elseif escape == "u" then
			local code = self:codepoint(stop + 2)
			cursor = stop + 6
			if code >= 0xD800 and code <= 0xDBFF then
				if text:sub(cursor, cursor + 1) ~= "\\u" then
					self:fail(stop, "reason.json_syntax")
				end
				local low = self:codepoint(cursor + 2)
				if low < 0xDC00 or low > 0xDFFF then
					self:fail(stop, "reason.json_syntax")
				end
				code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
				cursor = cursor + 6
			elseif code >= 0xDC00 and code <= 0xDFFF then
				self:fail(stop, "reason.json_syntax")
			end
			parts[#parts + 1] = utf8.char(code)
		else
			self:fail(stop, "reason.json_syntax")
		end
	end
end

function Decoder:enter(position, depth)
	if depth > self.limits.max_depth then
		self:fail(position, "reason.json_decode_depth", { max = self.limits.max_depth })
	end
end

function Decoder:array(position, depth)
	self:enter(position, depth)
	local result = {}
	local cursor = self:skip(position + 1)
	if self.text:sub(cursor, cursor) == "]" then
		return result, cursor + 1
	end
	while true do
		local item_position = cursor
		local value
		value, cursor = self:value(cursor, depth)
		if value == nil then
			self:fail(item_position, "reason.json_null_in_array")
		end
		result[#result + 1] = value
		cursor = self:skip(cursor)
		local char = self.text:sub(cursor, cursor)
		if char == "]" then
			return result, cursor + 1
		elseif char ~= "," then
			self:fail(cursor, "reason.json_syntax")
		end
		cursor = self:skip(cursor + 1)
	end
end

function Decoder:object(position, depth)
	self:enter(position, depth)
	local result, seen = {}, {}
	local cursor = self:skip(position + 1)
	if self.text:sub(cursor, cursor) == "}" then
		return result, cursor + 1
	end
	while true do
		if self.text:sub(cursor, cursor) ~= '"' then
			self:fail(cursor, "reason.json_syntax")
		end
		local key_position = cursor
		local key
		key, cursor = self:string(cursor)
		if seen[key] then
			self:fail(key_position, "reason.json_duplicate_key", { key = key })
		end
		seen[key] = true
		cursor = self:skip(cursor)
		if self.text:sub(cursor, cursor) ~= ":" then
			self:fail(cursor, "reason.json_syntax")
		end
		local value
		value, cursor = self:value(self:skip(cursor + 1), depth)
		result[key] = value
		cursor = self:skip(cursor)
		local char = self.text:sub(cursor, cursor)
		if char == "}" then
			return result, cursor + 1
		elseif char ~= "," then
			self:fail(cursor, "reason.json_syntax")
		end
		cursor = self:skip(cursor + 1)
	end
end

function Decoder:value(position, depth)
	local text = self.text
	local char = text:sub(position, position)
	if char == "{" then
		return self:object(position, depth + 1)
	elseif char == "[" then
		return self:array(position, depth + 1)
	elseif char == '"' then
		return self:string(position)
	elseif char == "-" or char:match("%d") then
		return self:number(position)
	elseif text:sub(position, position + 3) == "true" then
		return true, position + 4
	elseif text:sub(position, position + 4) == "false" then
		return false, position + 5
	elseif text:sub(position, position + 3) == "null" then
		return nil, position + 4
	end
	self:fail(position, "reason.json_syntax")
end

function Json.Decode(text, limits)
	local merged = {}
	for key, default in pairs(Json.DECODE_LIMITS) do
		merged[key] = (limits and limits[key]) or default
	end
	if type(text) ~= "string" then
		return false, "reason.json_syntax", { position = 0 }
	end
	if #text > merged.max_bytes then
		return false, "reason.json_too_large", { max = merged.max_bytes }
	end
	if not utf8.len(text) then
		return false, "reason.json_utf8"
	end
	local decoder = setmetatable({ text = text, limits = merged }, Decoder)
	local ok, value, finish = pcall(function()
		local result, next_position = decoder:value(decoder:skip(1), 0)
		return result, decoder:skip(next_position)
	end)
	if not ok then
		if type(value) == "table" and value.reason then
			return false, value.reason, value.params
		end
		error(value, 0)
	end
	if finish <= #text then
		return false, "reason.json_syntax", { position = finish }
	end
	return true, value
end

return Json
