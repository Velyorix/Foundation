-- English text for core runtime messages.
return {
	["error.invalid_argument"] = "{api}: argument #{index} '{name}' must be {expected} (got {actual})",
	["error.invalid_value"] = "{api}: argument #{index} '{name}' is invalid: {reason}",
	["error.invalid_state"] = "{api}: {reason}",
	["error.unknown_code"] = "unknown error code '{code}'",

	["reason.not_one_of"] = "expected one of {allowed}",
	["reason.unsupported_type"] = "unsupported type '{type}'",
	["reason.empty_string"] = "must not be empty",

	["log.repeated"] = "previous message repeated {count} more time(s)",
}
