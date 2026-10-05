local Messages = Package.Require("messages.lua")
local Plural = Package.Require("plural.lua")

local I18n = {}
I18n.__index = I18n

I18n.FALLBACK = "en"

local LOCALE_PATTERN = "^%l%l%l?$"
local REGIONAL_LOCALE_PATTERN = "^%l%l%l?[_-]%w+$"
local CATALOG_KEY_PATTERN = "^[%w_.-]+$"

function I18n.IsLocale(value)
	return type(value) == "string" and (value:match(LOCALE_PATTERN) or value:match(REGIONAL_LOCALE_PATTERN)) ~= nil
end

-- options: check, log, messages (Foundation's own messages, kept on the server locale).
function I18n.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		log = options.log,
		core_messages = options.messages,
		server_locale = I18n.FALLBACK,
		catalogs = {},
		reported = {},
		missing = 0,
	}, I18n)
end

function I18n:invalid(api, index, name, reason_key, params, level)
	self.errors:Raise("invalid_value", {
		api = api,
		index = index,
		name = name,
		reason = self.errors.messages:Format(reason_key, params),
	}, level + 1)
end

-- Returns false for an unusable locale code.
function I18n:SetServerLocale(locale)
	if not I18n.IsLocale(locale) then
		return false
	end
	self.server_locale = locale
	self.core_messages:SetLocale(locale)
	return true
end

function I18n:GetServerLocale()
	return self.server_locale
end

-- `level` as for Check: 2 is the caller of Register/Translate, 3 the caller of that caller.
function I18n:Register(owner, locale, entries, api, level)
	if not I18n.IsLocale(locale) then
		self:invalid(api, 1, "locale", "reason.locale_format", nil, level)
	end
	self.check:Argument(api, 2, "entries", entries, "table", level)
	local catalog = {}
	for key, template in pairs(entries) do
		local name = "entries[" .. string.format("%q", tostring(key)) .. "]"
		if type(key) ~= "string" or not key:match(CATALOG_KEY_PATTERN) then
			self:invalid(api, 2, name, "reason.catalog_key", nil, level)
		end
		if type(template) == "table" then
			if type(template.other) ~= "string" then
				self:invalid(api, 2, name, "reason.plural_other", nil, level)
			end
			local forms = {}
			for form, text in pairs(template) do
				if not Plural.FORMS[form] or type(text) ~= "string" then
					self:invalid(api, 2, name, "reason.plural_form", { form = tostring(form) }, level)
				end
				forms[form] = text
			end
			catalog[key] = forms
		elseif type(template) == "string" then
			catalog[key] = template
		else
			self:invalid(api, 2, name, "reason.catalog_value", nil, level)
		end
	end
	local owned = self.catalogs[owner]
	if not owned then
		owned = {}
		self.catalogs[owner] = owned
	end
	if owned[locale] then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.errors.messages:Format("reason.catalog_exists", { owner = owner, locale = locale }),
		}, level)
	end
	owned[locale] = catalog
	return function()
		if self.catalogs[owner] and self.catalogs[owner][locale] == catalog then
			self.catalogs[owner][locale] = nil
			if next(self.catalogs[owner]) == nil then
				self.catalogs[owner] = nil
			end
		end
	end
end

function I18n:chain(locale)
	local chain, seen = {}, {}
	local function add(code)
		if code and not seen[code] then
			seen[code] = true
			chain[#chain + 1] = code
		end
	end
	add(locale)
	add(locale and Plural.Language(locale))
	add(self.server_locale)
	add(Plural.Language(self.server_locale))
	add(I18n.FALLBACK)
	return chain
end

-- `key` is local to `owner`, or "<other-owner>:<key>" to use another package's catalog.
function I18n:Translate(owner, key, params, locale, api, level)
	self.check:NonEmptyString(api, 1, "key", key, level)
	self.check:Argument(api, 2, "params", params, "table?", level)
	if locale ~= nil and not I18n.IsLocale(locale) then
		self:invalid(api, 3, "locale", "reason.locale_format", nil, level)
	end
	local catalog_owner, local_key = key:match("^([^:]+):(.+)$")
	if not catalog_owner then
		catalog_owner, local_key = owner, key
	end
	local owned = self.catalogs[catalog_owner]
	if owned then
		for _, code in ipairs(self:chain(locale)) do
			local template = owned[code] and owned[code][local_key]
			if template ~= nil then
				return Messages.Render(template, params, code)
			end
		end
	end
	local full_key = catalog_owner .. ":" .. local_key
	if not self.reported[full_key] then
		self.reported[full_key] = true
		self.log:For(catalog_owner, "i18n"):Warning("i18n.missing_key", { key = full_key })
	end
	self.missing = self.missing + 1
	return full_key
end

function I18n:Snapshot()
	local owners = {}
	for owner, locales in pairs(self.catalogs) do
		local list = {}
		for code in pairs(locales) do
			list[#list + 1] = code
		end
		table.sort(list)
		owners[owner] = list
	end
	local reported = {}
	for key in pairs(self.reported) do
		reported[#reported + 1] = key
	end
	table.sort(reported)
	return { server_locale = self.server_locale, catalogs = owners, missing = self.missing, missing_keys = reported }
end

return I18n
