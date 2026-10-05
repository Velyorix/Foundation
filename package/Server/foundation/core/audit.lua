local Audit = {}
Audit.__index = Audit

Audit.OUTCOMES = { "success", "denied", "failure" }

local ACTION_PATTERN = "^([a-z0-9][a-z0-9_-]*):[a-z0-9][a-z0-9_./-]*$"

-- files: core/files.lua instance; json and sensitive: the shared core modules.
function Audit.new(options)
	return setmetatable({
		files = options.files,
		json = options.json,
		sensitive = options.sensitive,
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
		details = self.sensitive.MaskFields(entry.details),
	}
	local line, reason, params = self.json.Encode(record)
	if not line then
		self.errors:Raise("invalid_value", {
			api = "Audit:Record",
			index = 3,
			name = "entry.details",
			reason = self.errors.messages:Format(reason, params),
		})
	end

	local path = self:PathFor(seconds)
	local ok, failure = self.files:Append(path, line .. "\n")
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
