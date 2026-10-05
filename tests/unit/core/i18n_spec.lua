local function fake_package(name)
	local package = { subscriptions = {} }
	function package.GetName()
		return name
	end
	function package.Subscribe(event, callback)
		package.subscriptions[event] = callback
	end
	return package
end

local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local lines = {}
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = {
			en = loader:require("foundation/locales/en/core.lua"),
			fr = loader:require("foundation/locales/fr/core.lua"),
		},
		sink = function(level, line)
			lines[#lines + 1] = { level = level, line = line }
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
	})
	runtime:Start()
	return runtime, lines, loader
end

local function register(runtime, name)
	local native = fake_package(name)
	local context = runtime.packages:Register(native, { api = "0.1" })
	return context, native
end

describe("localization", function()
	local runtime, lines, context

	before_each(function()
		runtime, lines = setup()
		context = register(runtime, "shop")
		context:RegisterCatalog("en", {
			welcome = "Welcome, {name}!",
			["items.count"] = { one = "{count} item", other = "{count} items" },
			only_english = "English only",
		})
		context:RegisterCatalog("fr", {
			welcome = "Bienvenue, {name} !",
			["items.count"] = { one = "{count} objet", other = "{count} objets" },
		})
	end)

	it("translates with variables in the server locale", function()
		expect.equal(context:Translate("welcome", { name = "Ana" }), "Welcome, Ana!")
		runtime.i18n:SetServerLocale("fr")
		expect.equal(context:Translate("welcome", { name = "Ana" }), "Bienvenue, Ana !")
	end)

	it("translates in an explicit locale", function()
		expect.equal(context:Translate("welcome", { name = "Ana" }, "fr"), "Bienvenue, Ana !")
	end)

	it("falls back from a regional locale to its language, then to the server locale and English", function()
		expect.equal(context:Translate("welcome", { name = "Ana" }, "fr_CA"), "Bienvenue, Ana !")
		expect.equal(context:Translate("only_english", nil, "fr"), "English only")
		expect.equal(context:Translate("welcome", { name = "Ana" }, "de"), "Welcome, Ana!")
	end)

	it("chooses plural forms with the rules of the language actually used", function()
		expect.equal(context:Translate("items.count", { count = 1 }), "1 item")
		expect.equal(context:Translate("items.count", { count = 0 }), "0 items")
		expect.equal(context:Translate("items.count", { count = 2 }), "2 items")
		expect.equal(context:Translate("items.count", { count = 0 }, "fr"), "0 objet")
		expect.equal(context:Translate("items.count", { count = 1.5 }, "fr"), "1.5 objet")
		expect.equal(context:Translate("items.count", { count = 2 }, "fr"), "2 objets")
		expect.equal(context:Translate("items.count", {}), "{count} items", "missing count uses 'other'")
	end)

	it("inserts values literally", function()
		expect.equal(context:Translate("welcome", { name = "%s {other}" }), "Welcome, %s {other}!")
	end)

	it("returns the full key and reports a missing translation once", function()
		expect.equal(context:Translate("nope"), "shop:nope")
		expect.equal(context:Translate("nope"), "shop:nope")
		local warnings = {}
		for _, entry in ipairs(lines) do
			if entry.line:find("missing translation", 1, true) then
				warnings[#warnings + 1] = entry.line
			end
		end
		expect.same(warnings, { "[foundation] WARN  shop/i18n: missing translation for 'shop:nope'" })
		local snapshot = runtime.i18n:Snapshot()
		expect.equal(snapshot.missing, 2)
		expect.same(snapshot.missing_keys, { "shop:nope" })
	end)

	it("reads another package's catalog with a namespaced key", function()
		local other = register(runtime, "hud")
		expect.equal(other:Translate("shop:welcome", { name = "Bo" }), "Welcome, Bo!")
	end)

	it("follows the server locale for Foundation's own messages", function()
		runtime.i18n:SetServerLocale("fr")
		expect.equal(runtime.messages:Format("package.ready", { id = "x" }), "x est prêt")
		expect.falsy(runtime.i18n:SetServerLocale("not a locale"))
		expect.equal(runtime.i18n:GetServerLocale(), "fr")
	end)

	it("removes catalogs when the package is disabled", function()
		runtime.packages:Disable("shop", "unload")
		expect.is_nil(runtime.i18n:Snapshot().catalogs.shop)
		local again = register(runtime, "shop")
		expect.no_error(function()
			again:RegisterCatalog("en", { welcome = "Hi" })
		end)
		expect.equal(again:Translate("welcome"), "Hi")
	end)

	describe("catalog validation", function()
		local function rejects(locale, entries, fragment)
			expect.raises(function()
				context:RegisterCatalog(locale, entries)
			end, fragment)
		end

		it("rejects bad locales, keys and values", function()
			rejects("French", { a = "x" }, "must be a locale code such as 'en', 'fr' or 'fr_CA'")
			rejects("de", "x", "'entries' must be table (got string)")
			rejects("de", { ["bad key"] = "x" }, "keys may only contain letters")
			rejects("de", { a = 5 }, "must be a string or a table of plural forms")
			rejects("de", { a = { one = "x" } }, "plural forms need an 'other' form")
			rejects("de", { a = { other = "x", several = "y" } }, "'several' is not a plural form")
		end)

		it("refuses a second catalog for the same locale", function()
			rejects("en", { a = "x" }, "'shop' already registered a catalog for 'en'")
		end)

		it("reports catalog errors at the package's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				context:RegisterCatalog("de", { a = 5 })
			end)
			expect.falsy(ok)
			expect.equal(tonumber(message:match("i18n_spec%.lua:(%d+):")), expected_line)
		end)

		it("reports translation misuse at the package's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				context:Translate(42)
			end)
			expect.falsy(ok)
			expect.contains(message, "context:Translate: argument #1 'key' must be string")
			expect.equal(tonumber(message:match("i18n_spec%.lua:(%d+):")), expected_line)
		end)
	end)
end)

describe("plural rules", function()
	local Plural = Loader.new():require("foundation/core/plural.lua")

	it("implements the English and French cardinal rules", function()
		expect.equal(Plural.Category("en", 1), "one")
		expect.equal(Plural.Category("en", 0), "other")
		expect.equal(Plural.Category("en_GB", 1), "one")
		expect.equal(Plural.Category("fr", 0), "one")
		expect.equal(Plural.Category("fr", 1.99), "one")
		expect.equal(Plural.Category("fr", 2), "other")
		expect.equal(Plural.Category("fr", -1), "one")
		expect.equal(Plural.Category("de", 1), "one", "unknown languages use the English rule")
	end)
end)
