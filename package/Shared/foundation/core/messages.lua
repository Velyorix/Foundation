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

function Messages:Template(key)
	local active = self.catalogs[self.locale]
	local template = active and active[key]
	if template == nil then
		local fallback = self.catalogs[self.fallback]
		template = fallback and fallback[key]
	end
	return template
end

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
