local Sensitive = {}

Sensitive.MASK = "***"

local FRAGMENTS =
	{ "password", "passwd", "secret", "token", "credential", "authorization", "connection_string", "api_key", "apikey" }

function Sensitive.IsSensitiveName(name)
	local lowered = tostring(name):lower()
	for _, fragment in ipairs(FRAGMENTS) do
		if lowered:find(fragment, 1, true) then
			return true
		end
	end
	return false
end

function Sensitive.MaskFields(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, item in pairs(value) do
		if type(key) == "string" and Sensitive.IsSensitiveName(key) then
			copy[key] = Sensitive.MASK
		else
			copy[key] = Sensitive.MaskFields(item, seen)
		end
	end
	return copy
end

return Sensitive
