-- Error model.
--
-- Programming errors (bad arguments, wrong state) are raised as strings formatted
-- "[foundation:<code>] <message>" so engine logs stay readable. Expected failures are
-- returned as structured error values (see Errors:New) and never raised.
--
-- Every code belongs to one category and has a message key "error.<code>" in the core
-- catalogs. Subsystems add their codes to CODES when they introduce them.

local Errors = {}
Errors.__index = Errors

Errors.CATEGORIES = {
	developer = true,
	user = true,
	configuration = true,
	infrastructure = true,
	security = true,
}

Errors.CODES = {
	invalid_argument = "developer",
	invalid_value = "developer",
	invalid_state = "developer",
}

local ErrorValue = {}
ErrorValue.__index = ErrorValue

function ErrorValue.__tostring(value)
	return "[foundation:" .. value.code .. "] " .. value.message
end

--- Creates an error factory rendering messages through `messages` (core/messages.lua).
function Errors.new(messages)
	return setmetatable({ messages = messages }, Errors)
end

--- Builds a structured error value.
-- code     a key of Errors.CODES
-- params   placeholder values for the message (copied, may be nil)
-- options  optional { cause = <error value or string>, owner = <package id>, details = <table> }
-- Returns a table with fields code, category, message, params, cause, owner, details.
function Errors:New(code, params, options)
	local category = Errors.CODES[code]
	if category == nil then
		error(self.messages:Format("error.unknown_code", { code = tostring(code) }), 2)
	end
	local copied = {}
	for key, value in pairs(params or {}) do
		copied[key] = value
	end
	options = options or {}
	return setmetatable({
		code = code,
		category = category,
		message = self.messages:Format("error." .. code, copied),
		params = copied,
		cause = options.cause,
		owner = options.owner,
		details = options.details,
	}, ErrorValue)
end

--- Raises a programming error. `level` follows Lua's `error` convention from the point
-- of view of the function calling Raise: 1 is that function, 2 its caller (default).
function Errors:Raise(code, params, level)
	error(tostring(self:New(code, params)), (level or 2) + 1)
end

--- True when `value` is a structured error value created by any Errors instance.
function Errors.Is(value)
	return type(value) == "table" and getmetatable(value) == ErrorValue
end

return Errors
