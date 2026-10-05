-- Message catalogs for Foundation's own text. A catalog maps stable keys to templates;
-- `{name}` placeholders are replaced with the string form of the matching parameter.
-- Lookup falls back from the active locale to the fallback locale, then to the key
-- itself, so a missing translation never raises.

local Messages = {}
Messages.__index = Messages

local PLACEHOLDER = "{([%a_][%w_]*)}"

--- Creates a message set.
-- catalogs  table locale -> { key -> template }
-- locale    active locale (default "en")
-- fallback  locale used when a key is missing in the active locale (default "en")
function Messages.new(catalogs, locale, fallback)
	return setmetatable({
		catalogs = catalogs,
		locale = locale or "en",
		fallback = fallback or "en",
	}, Messages)
end

function Messages:SetLocale(locale)
	self.locale = locale
end

function Messages:GetLocale()
	return self.locale
end

--- Returns the raw template for `key`, or nil when no catalog defines it.
function Messages:Template(key)
	local active = self.catalogs[self.locale]
	local template = active and active[key]
	if template == nil then
		local fallback = self.catalogs[self.fallback]
		template = fallback and fallback[key]
	end
	return template
end

--- Renders `key` with `params`. Unknown placeholders are left as written; values are
-- inserted literally (no pattern or format interpretation).
function Messages:Format(key, params)
	local template = self:Template(key)
	if template == nil then
		return key
	end
	return (
		template:gsub(PLACEHOLDER, function(name)
			local value = params and params[name]
			if value == nil then
				return nil
			end
			return tostring(value)
		end)
	)
end

--- Placeholder names used by a template, in order of first appearance.
function Messages.Placeholders(template)
	local names, seen = {}, {}
	for name in template:gmatch(PLACEHOLDER) do
		if not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	return names
end

return Messages
