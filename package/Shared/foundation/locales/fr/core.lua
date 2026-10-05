return {
	["error.invalid_argument"] = "{api} : l'argument n°{index} '{name}' doit être de type {expected} (reçu : {actual})",
	["error.invalid_value"] = "{api} : l'argument n°{index} '{name}' est invalide : {reason}",
	["error.invalid_state"] = "{api} : {reason}",
	["error.unknown_code"] = "code d'erreur inconnu '{code}'",

	["reason.not_one_of"] = "valeurs acceptées : {allowed}",
	["reason.unsupported_type"] = "type non pris en charge '{type}'",
	["reason.empty_string"] = "ne doit pas être vide",

	["log.repeated"] = "message précédent répété {count} fois de plus",

	["error.audit_write_failed"] = "impossible d'écrire l'enregistrement d'audit dans {path}",
	["audit.write_failed"] = "l'enregistrement d'audit n'a pas pu être écrit dans {path} ; il est conservé dans cette ligne de journal",
	["reason.audit_action"] = "doit être de la forme '<propriétaire>:<nom>' avec l'espace de noms '{owner}', en minuscules, chiffres, '_', '-', '.', '/'",
	["reason.json_non_finite"] = "{path} n'est pas un nombre fini",
	["reason.json_cycle"] = "{path} fait référence à lui-même",
	["reason.json_depth"] = "{path} est imbriqué sur plus de {max} niveaux",
	["reason.json_key_type"] = "{path} a une clé de type {type} ; seules les clés texte ou une séquence sont acceptées",
	["reason.json_unsupported_type"] = "{path} a un type non pris en charge : {type}",

	["reason.owner_closed"] = "'{owner}' est désactivé et ne peut plus enregistrer de ressources",
	["invoke.failed"] = "le callback {kind} de {owner} a échoué",
}
