local Keys = {}
Keys.__index = Keys

Keys.MAX_LENGTH = 128
Keys.MAX_NAMESPACE_LENGTH = 64
Keys.RESERVED = { foundation = true }

local NAMESPACE_PATTERN = "^[a-z0-9_.-]+$"
local PATH_PATTERN = "^[a-z0-9_./-]+$"

function Keys.new(errors)
	return setmetatable({ errors = errors, messages = errors.messages }, Keys)
end

function Keys.IsReserved(namespace)
	return Keys.RESERVED[namespace] == true
end

-- For keys already produced by Parse or Check.
function Keys.Split(key)
	return key:match("^([^:]+):(.+)$")
end

-- Returns key, namespace, path; or nil and a reason message key.
local function normalize(text, default_namespace)
	if type(text) ~= "string" or text == "" then
		return nil, "reason.key_format"
	end
	text = text:lower()
	local namespace, path = text:match("^([^:]*):(.*)$")
	if not namespace then
		if default_namespace == nil then
			return nil, "reason.key_missing_namespace"
		end
		namespace, path = default_namespace:lower(), text
	end
	if #namespace > Keys.MAX_NAMESPACE_LENGTH or not namespace:match(NAMESPACE_PATTERN) then
		return nil, "reason.key_format"
	end
	if not path:match(PATH_PATTERN) or path:sub(1, 1) == "/" or path:sub(-1) == "/" or path:find("//", 1, true) then
		return nil, "reason.key_format"
	end
	local key = namespace .. ":" .. path
	if #key > Keys.MAX_LENGTH then
		return nil, "reason.key_length"
	end
	return key, namespace, path
end

function Keys:Parse(text, default_namespace)
	if default_namespace ~= nil and type(default_namespace) ~= "string" then
		self.errors:Raise("invalid_argument", {
			api = "Foundation.Keys.Parse",
			index = 2,
			name = "default_namespace",
			expected = "string?",
			actual = type(default_namespace),
		})
	end
	local key, namespace_or_reason, path = normalize(text, default_namespace)
	if not key then
		return nil,
			self.errors:New("invalid_key", {
				key = tostring(text),
				reason = self.messages:Format(namespace_or_reason, { max = Keys.MAX_LENGTH }),
			})
	end
	return key, namespace_or_reason, path
end

-- options: default_namespace, owner (the key's namespace must then be the owner's).
-- `level` as for error(), seen from the public function doing the check (default 2).
-- Do not tail-call Check: that removes the public function's frame and shifts the level.
function Keys:Check(api, index, name, value, options, level)
	options = options or {}
	local key, namespace_or_reason = normalize(value, options.default_namespace)
	local reason
	if not key then
		reason = self.messages:Format(namespace_or_reason, { max = Keys.MAX_LENGTH })
	elseif options.owner and namespace_or_reason ~= options.owner then
		reason = self.messages:Format("reason.key_owner", { owner = options.owner })
	end
	if reason then
		self.errors:Raise("invalid_value", { api = api, index = index, name = name, reason = reason }, (level or 2) + 1)
	end
	return key
end

return Keys
