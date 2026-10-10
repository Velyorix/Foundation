local Operators = {}
Operators.__index = Operators

Operators.FILE_VERSION = 1
Operators.MAX_ID_LENGTH = 128

local ENTRY_FIELDS = { name = true, added_by = true, added_at = true }

local function valid_id(id)
	return type(id) == "string" and id ~= "" and #id <= Operators.MAX_ID_LENGTH and not id:find("%c")
end

-- options: files (core/files.lua), json, messages, log, now (seconds), path,
-- audit() returning the audit sink or nil, announce(event, payload) (optional)
function Operators.new(options)
	return setmetatable({
		files = options.files,
		json = options.json,
		messages = options.messages,
		log = options.log,
		now = options.now,
		path = options.path or "foundation/operators.json",
		audit = options.audit,
		announce = options.announce,
		entries = {},
		writable = true,
	}, Operators)
end

-- Returns nil when the content is a valid operator file, or a reason text.
function Operators:parse(text)
	local ok, data, params = self.json.Decode(text)
	if not ok then
		return nil, self.messages:Format(data, params)
	end
	if type(data) ~= "table" or data.version ~= Operators.FILE_VERSION or type(data.operators) ~= "table" then
		return nil, self.messages:Format("operators.bad_format", { version = Operators.FILE_VERSION })
	end
	local entries = {}
	for id, entry in pairs(data.operators) do
		local valid = valid_id(id) and type(entry) == "table"
		for field in pairs(valid and entry or {}) do
			valid = valid and ENTRY_FIELDS[field] == true
		end
		valid = valid
			and (entry.name == nil or type(entry.name) == "string")
			and type(entry.added_by) == "string"
			and math.type(entry.added_at) == "integer"
		if not valid then
			return nil, self.messages:Format("operators.bad_entry", { id = tostring(id) })
		end
		entries[id] = { name = entry.name, added_by = entry.added_by, added_at = entry.added_at }
	end
	return entries
end

-- A file that cannot be read is never overwritten: changes are refused until it is fixed,
-- so a typo made by hand cannot erase the list.
function Operators:Load()
	local text, read_error = self.files:ReadText(self.path)
	if text == nil then
		self.entries, self.writable = {}, true
		return true
	end
	local entries, reason
	if text == false then
		reason = read_error
	else
		entries, reason = self:parse(text)
	end
	if not entries then
		self.entries, self.writable = {}, false
		self.log:Error("operators.unreadable", { path = self.path, reason = reason })
		return false
	end
	self.entries, self.writable = entries, true
	local count = 0
	for _ in pairs(entries) do
		count = count + 1
	end
	self.log:Info("operators.loaded", { path = self.path, count = count })
	return true
end

function Operators:IsOperator(id)
	return self.entries[id] ~= nil
end

function Operators:List()
	local result = {}
	for id, entry in pairs(self.entries) do
		result[#result + 1] = { id = id, name = entry.name, added_by = entry.added_by, added_at = entry.added_at }
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

function Operators:save(entries)
	local text = self.json.Encode({ version = Operators.FILE_VERSION, operators = entries })
	local ok, reason = self.files:WriteAtomic(self.path, text .. "\n")
	if not ok then
		self.log:Error("operators.write_failed", { path = self.path, reason = reason })
		return false
	end
	return true
end

function Operators:record(action, id, by, name)
	local audit = self.audit and self.audit()
	if audit then
		audit:Record("foundation", "foundation:operators/" .. action, {
			actor = by,
			target = id,
			details = name and { name = name } or nil,
		})
	end
	if self.announce then
		self.announce(
			action == "add" and "operator_added" or "operator_removed",
			{ account = id, name = name, by = by }
		)
	end
end

-- Returns true, or false and a reason message key: "operators.invalid_id", "operators.exists",
-- "operators.missing", "operators.locked" or "operators.write_failed_short".
function Operators:Add(id, name, by)
	if not valid_id(id) then
		return false, "operators.invalid_id"
	end
	if not self.writable then
		return false, "operators.locked"
	end
	if self.entries[id] then
		return false, "operators.exists"
	end
	local entries = {}
	for key, entry in pairs(self.entries) do
		entries[key] = entry
	end
	entries[id] = { name = name, added_by = by, added_at = self.now() }
	if not self:save(entries) then
		return false, "operators.write_failed_short"
	end
	self.entries = entries
	self.log:Info("operators.added", { id = id, by = by })
	self:record("add", id, by, name)
	return true
end

function Operators:Remove(id, by)
	if not self.writable then
		return false, "operators.locked"
	end
	local existing = self.entries[id]
	if not existing then
		return false, "operators.missing"
	end
	local entries = {}
	for key, entry in pairs(self.entries) do
		if key ~= id then
			entries[key] = entry
		end
	end
	if not self:save(entries) then
		return false, "operators.write_failed_short"
	end
	self.entries = entries
	self.log:Info("operators.removed", { id = id, by = by })
	self:record("remove", id, by, existing.name)
	return true
end

function Operators:Snapshot()
	local count = 0
	for _ in pairs(self.entries) do
		count = count + 1
	end
	return { path = self.path, count = count, writable = self.writable }
end

return Operators
