local files = require("tests.support.files")

local LOCALES_ROOT = "package/Shared/foundation/locales"

local function catalog_names(locale)
	local names = {}
	for _, path in ipairs(files.list(LOCALES_ROOT .. "/" .. locale, "*.lua")) do
		names[#names + 1] = path:sub(#LOCALES_ROOT + #locale + 3)
	end
	return names
end

describe("core locale catalogs", function()
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")

	it("ship the same catalog files in English and French", function()
		local en = catalog_names("en")
		expect.truthy(#en > 0, "no English catalogs found")
		expect.same(catalog_names("fr"), en)
	end)

	for _, name in ipairs(catalog_names("en")) do
		it(name .. " has the same keys and placeholders in both languages", function()
			local en = loader:require("foundation/locales/en/" .. name)
			local fr = loader:require("foundation/locales/fr/" .. name)
			for key, template in pairs(en) do
				expect.type(fr[key], "string", "French translation of " .. key)
				local en_placeholders = Messages.Placeholders(template)
				local fr_placeholders = Messages.Placeholders(fr[key])
				table.sort(en_placeholders)
				table.sort(fr_placeholders)
				expect.same(fr_placeholders, en_placeholders, "placeholders of " .. key)
			end
			for key in pairs(fr) do
				expect.type(en[key], "string", "English source of " .. key)
			end
		end)
	end
end)
