local Permissions = {}
Permissions.__index = Permissions

Permissions.DEFAULTS = { "everyone", "nobody", "operators", "non_operators" }
Permissions.UNDECLARED_DEFAULT = "operators"
Permissions.MAX_LENGTH = 128

local SEGMENT = "^[a-z0-9_-]+$"
local DECLARATION_FIELDS = { description = true, default = true, deprecated = true }
local DEFAULT_SET = {}
for _, name in ipairs(Permissions.DEFAULTS) do
	DEFAULT_SET[name] = true
end

local function valid_node(node)
	if type(node) ~= "string" or node == "" or #node > Permissions.MAX_LENGTH then
		return false
	end
	for segment in (node .. "."):gmatch("([^.]*)%.") do
		if not segment:match(SEGMENT) then
			return false
		end
	end
	return node:find(".", 1, true) ~= nil
end

-- options: check, log, is_operator(subject_id) (optional; nobody is an operator without it)
function Permissions.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		log = options.log,
		is_operator = options.is_operator or function()
			return false
		end,
		declarations = {},
		warned = {},
	}, Permissions)
end

function Permissions:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.messages:Format(reason_key, params),
	}, level + 1)
end

-- Returns the declaration and a release function for the owner's resource tracking.
function Permissions:Declare(owner, node, definition, api, level)
	self.check:Argument(api, 1, "node", node, "string", level)
	node = node:lower()
	if not valid_node(node) then
		self:invalid(api, 1, "node", "reason.permission_node", { max = Permissions.MAX_LENGTH }, level)
	end
	if node:sub(1, #owner + 1) ~= owner .. "." then
		self:invalid(api, 1, "node", "reason.permission_owner", { owner = owner }, level)
	end
	self.check:Argument(api, 2, "definition", definition, "table?", level)
	definition = definition or {}
	for field in pairs(definition) do
		if not DECLARATION_FIELDS[field] then
			self:invalid(api, 2, "definition", "reason.manifest_unknown_field", { field = tostring(field) }, level)
		end
	end
	self.check:Argument(api, 2, "definition.description", definition.description, "string?", level)
	local default = definition.default or Permissions.UNDECLARED_DEFAULT
	self.check:OneOf(api, 2, "definition.default", default, Permissions.DEFAULTS, level)
	local deprecated = definition.deprecated
	if deprecated ~= nil and type(deprecated) ~= "string" and deprecated ~= true then
		self.errors:Raise("invalid_argument", {
			api = api,
			index = 2,
			name = "definition.deprecated",
			expected = "string|true|nil",
			actual = type(deprecated),
		}, level)
	end
	local existing = self.declarations[node]
	if existing then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.messages:Format("reason.permission_declared", { node = node, owner = existing.owner }),
		}, level)
	end
	local declaration = {
		node = node,
		owner = owner,
		description = definition.description,
		default = default,
		deprecated = deprecated,
	}
	self.declarations[node] = declaration
	return declaration,
		function()
			if self.declarations[node] == declaration then
				self.declarations[node] = nil
			end
		end
end

-- Subjects are commands senders (core/senders.lua) or account id strings. The console has
-- every permission.
function Permissions:subject_id(api, subject, level)
	if type(subject) == "string" and subject ~= "" then
		return subject, false
	end
	if type(subject) == "table" and type(subject.GetKind) == "function" then
		if subject:GetKind() == "console" then
			return "console", true
		end
		return tostring(subject:GetId()), false
	end
	self.errors:Raise("invalid_argument", {
		api = api,
		index = 1,
		name = "subject",
		expected = "sender or account id",
		actual = type(subject),
	}, level + 1)
end

local function from_default(default, operator)
	if default == "everyone" then
		return true
	elseif default == "nobody" then
		return false
	elseif default == "operators" then
		return operator
	end
	return not operator
end

-- Returns allowed (boolean) and the source of the decision: "console" or "default".
function Permissions:Resolve(subject, node, api, level)
	local id, console = self:subject_id(api, subject, level + 1)
	self.check:Argument(api, 2, "node", node, "string", level + 1)
	node = node:lower()
	if not valid_node(node) then
		self:invalid(api, 2, "node", "reason.permission_node", { max = Permissions.MAX_LENGTH }, level + 1)
	end
	local declaration = self.declarations[node]
	if declaration and declaration.deprecated and not self.warned[node] then
		self.warned[node] = true
		self.log:For(declaration.owner, "permissions"):Warning("permissions.deprecated", {
			node = node,
			note = declaration.deprecated == true and "" or declaration.deprecated,
		})
	end
	if console then
		return true, "console"
	end
	local default = declaration and declaration.default or Permissions.UNDECLARED_DEFAULT
	return from_default(default, self.is_operator(id) == true), "default"
end

function Permissions:Has(subject, node, level)
	local allowed = self:Resolve(subject, node, "Foundation.Permissions.Has", level or 2)
	return allowed
end

function Permissions:Get(node)
	local declaration = self.declarations[node]
	if not declaration then
		return nil
	end
	return {
		node = declaration.node,
		owner = declaration.owner,
		description = declaration.description,
		default = declaration.default,
		deprecated = declaration.deprecated,
	}
end

function Permissions:List(owner)
	local result = {}
	for _, declaration in pairs(self.declarations) do
		if owner == nil or declaration.owner == owner then
			result[#result + 1] = self:Get(declaration.node)
		end
	end
	table.sort(result, function(a, b)
		return a.node < b.node
	end)
	return result
end

return Permissions
