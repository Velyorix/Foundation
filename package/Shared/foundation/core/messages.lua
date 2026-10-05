local Plural = Package.Require("plural.lua")

local Messages = {}
Messages.__index = Messages

local PLACEHOLDER = "{([%a_][%w_]*)}"

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

-- Returns the template and the locale it was found in.
function Messages:Template(key)
	for _, locale in ipairs({ self.locale, self.fallback }) do
		local catalog = self.catalogs[locale]
		local template = catalog and catalog[key]
		if template ~= nil then
			return template, locale
		end
	end
	return nil
end

-- A template is a string or a table of plural forms chosen with params.count.
function Messages.Render(template, params, locale)
	if type(template) == "table" then
		local count = params and params.count
		local form = type(count) == "number" and template[Plural.Category(locale, count)]
		template = form or template.other
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

function Messages:Format(key, params)
	local template, locale = self:Template(key)
	if template == nil then
		return key
	end
	return Messages.Render(template, params, locale)
end

-- Names used by a template (all plural forms for a table), in order of first appearance.
function Messages.Placeholders(template)
	local forms = {}
	if type(template) == "table" then
		for form in pairs(template) do
			forms[#forms + 1] = form
		end
		table.sort(forms)
	end
	local names, seen = {}, {}
	local function collect(text)
		for name in text:gmatch(PLACEHOLDER) do
			if not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	if type(template) == "table" then
		for _, form in ipairs(forms) do
			collect(template[form])
		end
	else
		collect(template)
	end
	return names
end

return Messages
