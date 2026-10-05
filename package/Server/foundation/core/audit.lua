local Json = Package.Require("../../../Shared/foundation/core/json.lua")
local Sensitive = Package.Require("../../../Shared/foundation/core/sensitive.lua")

local Audit = {}
Audit.__index = Audit

Audit.OUTCOMES = { "success", "denied", "failure" }

local ACTION_PATTERN = "^([a-z0-9][a-z0-9_-]*):[a-z0-9][a-z0-9_./-]*$"

-- files: { Open(path, truncate) -> File, Exists(path), CreateDirectory(path), IsDirectory(path) }
function Audit.new(options)
	return setmetatable({
		files = options.files,
		now = options.now,
		check = options.check,
		errors = options.check.errors,
		log = options.log,
		directory = options.directory or "foundation/audit",
		written = 0,
		failed = 0,
		last_failure = nil,
	}, Audit)
end

function Audit:PathFor(seconds)
	return self.directory .. "/audit-" .. os.date("!%Y-%m-%d", seconds) .. ".log"
end

function Audit:ensure_directory()
	if self.files.IsDirectory(self.directory) then
		return true
	end
	-- Raises when a file already occupies the path (server 1.156).
	local ok, err = pcall(self.files.CreateDirectory, self.directory)
	if self.files.IsDirectory(self.directory) then
		return true
	end
	return false, ok and self.directory or tostring(err)
end

function Audit:append(path, line)
	local ready, reason = self:ensure_directory()
	if not ready then
		return false, reason
	end
	local ok, result = pcall(function()
		local file = self.files.Open(path, false)
		if not file:IsGood() then
			file:Close()
			return false
		end
		file:Seek(file:Size())
		file:Write(line .. "\n")
		file:Flush()
		local good = not file:HasFailed()
		file:Close()
		return good
	end)
	if not ok then
		return false, tostring(result)
	end
	if not result then
		return false, path
	end
	return true
end

function Audit:Record(owner, action, entry)
	local check = self.check
	check:NonEmptyString("Audit:Record", 1, "owner", owner)
	check:NonEmptyString("Audit:Record", 2, "action", action)
	check:Argument("Audit:Record", 3, "entry", entry, "table?")
	local namespace = action:match(ACTION_PATTERN)
	if namespace ~= owner then
		self.errors:Raise("invalid_value", {
			api = "Audit:Record",
			index = 2,
			name = "action",
			reason = self.errors.messages:Format("reason.audit_action", { owner = owner }),
		})
	end
	entry = entry or {}
	check:Argument("Audit:Record", 3, "entry.actor", entry.actor, "string?")
	check:Argument("Audit:Record", 3, "entry.target", entry.target, "string?")
	check:Argument("Audit:Record", 3, "entry.details", entry.details, "table?")
	if entry.outcome ~= nil then
		check:OneOf("Audit:Record", 3, "entry.outcome", entry.outcome, Audit.OUTCOMES)
	end

	local seconds = self.now()
	local record = {
		time = os.date("!%Y-%m-%dT%H:%M:%SZ", seconds),
		owner = owner,
		action = action,
		actor = entry.actor,
		target = entry.target,
		outcome = entry.outcome or "success",
		details = Sensitive.MaskFields(entry.details),
	}
	local line, reason, params = Json.Encode(record)
	if not line then
		self.errors:Raise("invalid_value", {
			api = "Audit:Record",
			index = 3,
			name = "entry.details",
			reason = self.errors.messages:Format(reason, params),
		})
	end

	local path = self:PathFor(seconds)
	local ok, failure = self:append(path, line)
	if ok then
		self.written = self.written + 1
		return true
	end
	self.failed = self.failed + 1
	self.last_failure = { path = path, reason = failure, time = record.time }
	self.log:Error("audit.write_failed", { path = path }, { reason = failure, record = line })
	return nil,
		self.errors:New("audit_write_failed", { path = path }, { owner = owner, details = { reason = failure } })
end

function Audit:Snapshot()
	return {
		directory = self.directory,
		written = self.written,
		failed = self.failed,
		last_failure = self.last_failure,
	}
end

return Audit
