local function load_messages()
	return Loader.new():require("foundation/core/messages.lua")
end

describe("Messages", function()
	local Messages
	local catalogs = {
		en = { greeting = "Hello {name}", only_en = "English only", raw = "{a}{b}{a}" },
		fr = { greeting = "Bonjour {name}" },
	}

	before_each(function()
		Messages = load_messages()
	end)

	it("renders the active locale and replaces placeholders", function()
		local messages = Messages.new(catalogs, "fr")
		expect.equal(messages:Format("greeting", { name = "Ana" }), "Bonjour Ana")
	end)

	it("falls back to the fallback locale, then to the key", function()
		local messages = Messages.new(catalogs, "fr", "en")
		expect.equal(messages:Format("only_en"), "English only")
		expect.equal(messages:Format("missing.key"), "missing.key")
	end)

	it("leaves unknown placeholders untouched", function()
		local messages = Messages.new(catalogs)
		expect.equal(messages:Format("greeting", {}), "Hello {name}")
	end)

	it("inserts values literally, without pattern or format interpretation", function()
		local messages = Messages.new(catalogs)
		expect.equal(messages:Format("greeting", { name = "%1 %s {x}" }), "Hello %1 %s {x}")
	end)

	it("converts non-string values with tostring", function()
		local messages = Messages.new(catalogs)
		expect.equal(messages:Format("raw", { a = 1, b = false }), "1false1")
	end)

	it("switches locale at runtime", function()
		local messages = Messages.new(catalogs, "en")
		messages:SetLocale("fr")
		expect.equal(messages:GetLocale(), "fr")
		expect.equal(messages:Format("greeting", { name = "Ana" }), "Bonjour Ana")
	end)

	it("chooses plural forms with the rules of the catalog's locale", function()
		local messages = Messages.new({
			en = { apples = { one = "{count} apple", other = "{count} apples" } },
			fr = { apples = { one = "{count} pomme", other = "{count} pommes" } },
		}, "fr")
		expect.equal(messages:Format("apples", { count = 0 }), "0 pomme")
		expect.equal(messages:Format("apples", { count = 3 }), "3 pommes")
		messages:SetLocale("en")
		expect.equal(messages:Format("apples", { count = 0 }), "0 apples")
		expect.equal(messages:Format("apples", { count = 1 }), "1 apple")
	end)

	it("lists placeholders of every plural form", function()
		expect.same(
			Messages.Placeholders({ other = "{count} {name}", one = "{count} {unit}" }),
			{ "count", "unit", "name" }
		)
	end)

	it("lists placeholders once in order of appearance", function()
		expect.same(Messages.Placeholders("{b} and {a} and {b}"), { "b", "a" })
	end)
end)
