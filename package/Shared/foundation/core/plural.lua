-- CLDR cardinal rules for the locales Foundation ships; others use the English rule.
local Plural = {}

Plural.FORMS = { zero = true, one = true, two = true, few = true, many = true, other = true }

local RULES = {
	en = function(n)
		return n == 1 and "one" or "other"
	end,
	fr = function(n)
		return (n >= 0 and n < 2) and "one" or "other"
	end,
}

function Plural.Language(locale)
	return (tostring(locale):match("^(%a+)") or ""):lower()
end

function Plural.Category(locale, count)
	local rule = RULES[Plural.Language(locale)] or RULES.en
	return rule(math.abs(count))
end

return Plural
