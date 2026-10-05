-- Textes français des messages du runtime.
return {
	["error.invalid_argument"] = "{api} : l'argument n°{index} '{name}' doit être de type {expected} (reçu : {actual})",
	["error.invalid_value"] = "{api} : l'argument n°{index} '{name}' est invalide : {reason}",
	["error.invalid_state"] = "{api} : {reason}",
	["error.unknown_code"] = "code d'erreur inconnu '{code}'",

	["reason.not_one_of"] = "valeurs acceptées : {allowed}",
	["reason.unsupported_type"] = "type non pris en charge '{type}'",
	["reason.empty_string"] = "ne doit pas être vide",

	["log.repeated"] = "message précédent répété {count} fois de plus",
}
