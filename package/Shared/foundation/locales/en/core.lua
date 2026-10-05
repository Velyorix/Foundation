return {
	["error.invalid_argument"] = "{api}: argument #{index} '{name}' must be {expected} (got {actual})",
	["error.invalid_value"] = "{api}: argument #{index} '{name}' is invalid: {reason}",
	["error.invalid_state"] = "{api}: {reason}",
	["error.unknown_code"] = "unknown error code '{code}'",

	["reason.not_one_of"] = "expected one of {allowed}",
	["reason.unsupported_type"] = "unsupported type '{type}'",
	["reason.empty_string"] = "must not be empty",

	["log.repeated"] = "previous message repeated {count} more time(s)",

	["error.audit_write_failed"] = "could not write audit record to {path}",
	["audit.write_failed"] = "audit record could not be written to {path}; record kept in this log line",
	["reason.audit_action"] = "must be '<owner>:<name>' with the namespace '{owner}', lowercase letters, digits, '_', '-', '.', '/'",
	["reason.json_non_finite"] = "{path} is not a finite number",
	["reason.json_cycle"] = "{path} refers to itself",
	["reason.json_depth"] = "{path} is nested deeper than {max} levels",
	["reason.json_key_type"] = "{path} has a {type} key; only string keys or a sequence are supported",
	["reason.json_unsupported_type"] = "{path} has unsupported type {type}",

	["reason.owner_closed"] = "'{owner}' is disabled and cannot register new resources",
	["invoke.failed"] = "{kind} callback of {owner} failed",
}
