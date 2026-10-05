local SELF = "foundation-core-i18n-test"

local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
context:RegisterCatalog("en", {
	greeting = "Hello {name}",
	["homes.count"] = { one = "{count} home", other = "{count} homes" },
})
context:RegisterCatalog("fr", {
	greeting = "Bonjour {name}",
	["homes.count"] = { one = "{count} maison", other = "{count} maisons" },
})

local suite = FoundationTest.Suite("core-i18n")

suite:Test("translates with variables, locales and plurals", function()
	FoundationTest.Equal(context:Translate("greeting", { name = "Ana" }), "Hello Ana")
	FoundationTest.Equal(context:Translate("greeting", { name = "Ana" }, "fr_FR"), "Bonjour Ana")
	FoundationTest.Equal(context:Translate("homes.count", { count = 0 }, "fr"), "0 maison")
	FoundationTest.Equal(context:Translate("homes.count", { count = 0 }), "0 homes")
end)

suite:Test("returns the full key for missing translations", function()
	FoundationTest.Equal(context:Translate("missing.key"), SELF .. ":missing.key")
	FoundationTest.Equal(context:Translate("missing.key"), SELF .. ":missing.key")
end)

suite:Do(function()
	Server.ReloadPackage("foundation-core-i18n-test")
end)

suite:Run()
