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
	audit_write_failed = "infrastructure",
	incompatible_api = "developer",
	invalid_key = "user",
}

local ErrorValue = {}
ErrorValue.__index = ErrorValue

function ErrorValue.__tostring(value)
	return "[foundation:" .. value.code .. "] " .. value.message
end

function Errors.new(messages)
	return setmetatable({ messages = messages }, Errors)
end

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

-- `level` as for error(), seen from the function calling Raise (default 2: its caller).
function Errors:Raise(code, params, level)
	error(tostring(self:New(code, params)), (level or 2) + 1)
end

function Errors.Is(value)
	return type(value) == "table" and getmetatable(value) == ErrorValue
end

return Errors
