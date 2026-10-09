local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local lines = {}
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
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
	local function register(id)
		local native = {
			GetName = function()
				return id
			end,
			Subscribe = function() end,
		}
		return runtime.packages:Register(native, { api = "0.1" })
	end
	return runtime, register, lines, loader:require("foundation/core/arguments.lua")
end

local function noop() end

local function texts(tokens)
	local result = {}
	for index, token in ipairs(tokens) do
		result[index] = token.text
	end
	return result
end

describe("Command arguments", function()
	local runtime, register, lines, Arguments, shop

	before_each(function()
		runtime, register, lines, Arguments = setup()
		shop = register("shop")
	end)

	local function parse(line)
		return runtime.commands:Parse(line)
	end

	local function usage(line)
		local result, err = parse(line)
		expect.is_nil(result)
		expect.equal(err.code, "command_usage")
		expect.equal(err.category, "user")
		return err.message
	end

	describe("Split", function()
		it("splits on spaces and keeps quoted words together", function()
			expect.same(texts(Arguments.Split('  give  "Big Sword" 2 ')), { "give", "Big Sword", "2" })
			expect.same(texts(Arguments.Split([[say "a \"quoted\" word" \n]])), { "say", 'a "quoted" word', "\\n" })
			expect.same(texts(Arguments.Split('""')), { "" })
			expect.same(Arguments.Split(""), {})
		end)

		it("records where each word starts", function()
			local tokens = Arguments.Split('msg  alex "hi there"')
			expect.equal(tokens[2].start, 6)
			expect.equal(tokens[3].start, 11)
		end)

		it("refuses an unclosed quote", function()
			local tokens, reason = Arguments.Split('say "hello')
			expect.is_nil(tokens)
			expect.equal(reason, "command.unclosed_quote")
		end)
	end)

	describe("built-in types", function()
		before_each(function()
			shop:RegisterCommand({
				name = "give",
				run = noop,
				arguments = {
					{ name = "item", min = 2, max = 16 },
					{ name = "amount", type = "integer", min = 1, max = 64, default = 1 },
					{ name = "price", type = "number", min = 0, optional = true },
					{ name = "gift", type = "boolean", default = false },
					{ name = "rarity", type = "enum", values = { "common", "rare" }, default = "common" },
					{ name = "note", type = "greedy", optional = true },
				},
			})
		end)

		it("converts each argument and applies defaults", function()
			expect.same(parse("give apple").values, { item = "apple", amount = 1, gift = false, rarity = "common" })
			expect.same(parse('give "golden apple" 5 2.5 YES Rare  for  you  ').values, {
				item = "golden apple",
				amount = 5,
				price = 2.5,
				gift = true,
				rarity = "rare",
				note = "for  you",
			})
			expect.equal(math.type(parse("give apple 5").values.amount), "integer")
		end)

		it("explains what is wrong", function()
			expect.equal(usage("give"), "missing <item>")
			expect.equal(usage("give a"), "<item> must have at least 2 characters")
			expect.equal(usage("give apple 1.5"), "<amount>: '1.5' is not a whole number")
			expect.equal(usage("give apple 0x10"), "<amount>: '0x10' is not a whole number")
			expect.equal(usage("give apple 65"), "<amount> must be at most 64")
			expect.equal(usage("give apple 1 -1"), "<price> must be at least 0")
			expect.equal(usage("give apple 1 1e9"), "<price>: '1e9' is not a number")
			expect.equal(usage("give apple 1 1 maybe"), "<gift>: 'maybe' is not true or false")
			expect.equal(usage("give apple 1 1 no epic"), "<rarity> must be one of common, rare")
			expect.equal(usage('give "apple'), "a quote is not closed")
		end)

		it("refuses extra words when nothing is greedy", function()
			shop:RegisterCommand({ name = "price", run = noop, arguments = { { name = "item" } } })
			expect.equal(usage("price apple pear plum"), "too many arguments: pear plum")
		end)

		it("asks for a subcommand when the command only groups others", function()
			shop:RegisterCommand({
				name = "admin",
				subcommands = { { name = "open", run = noop }, { name = "close", run = noop } },
			})
			expect.equal(usage("admin"), "choose one of: open, close")
			expect.same(parse("admin close").path, { "admin", "close" })
		end)

		it("ignores lines that are not commands", function()
			local result, err = parse("hello there")
			expect.is_nil(result)
			expect.is_nil(err)
		end)
	end)

	describe("declarations", function()
		local function rejects(arguments, fragment)
			expect.raises(function()
				shop:RegisterCommand({ name = "test", run = noop, arguments = arguments })
			end, fragment)
		end

		it("rejects malformed declarations", function()
			rejects({ { name = "Item" } }, "'spec.arguments[1].name' is invalid")
			rejects({ { name = "a" }, { name = "a" } }, "'a' is declared twice")
			rejects({ { name = "a", type = "colour" } }, "'colour' is not an argument type")
			rejects({ { name = "a", type = "boolean", min = 1 } }, "'min' does not apply to the type 'boolean'")
			rejects({ { name = "a", values = { "x" } } }, "'values' does not apply to the type 'string'")
			rejects({ { name = "a", type = "enum", values = {} } }, "must not be empty")
			rejects({ { name = "a", type = "enum", values = { "Big" } } }, "values must be lowercase strings")
			rejects({ { name = "a", optional = true }, { name = "b" } }, "a required argument cannot follow")
			rejects({ { name = "a", type = "greedy" }, { name = "b", optional = true } }, "must be the last one")
			rejects({ { name = "a", type = "integer", default = 1.5 } }, "the default value is not a valid integer")
			rejects({ { name = "a", type = "integer", max = 3, default = 4 } }, "not a valid integer")
			rejects({ { name = "a", required = true } }, "unknown field 'required'")
			rejects({ { name = "a", min = "1" } }, "'spec.arguments[1].min' must be number? (got string)")
			rejects("item", "'spec.arguments' must be table? (got string)")
		end)
	end)

	describe("package types", function()
		local colours

		before_each(function()
			colours = { red = "#f00", green = "#0f0", grey = "#888" }
			shop:RegisterArgumentType("colour", {
				parse = function(text)
					local value = colours[text:lower()]
					if not value then
						return nil, "unknown colour '" .. text .. "'"
					end
					return value
				end,
				suggest = function(prefix)
					local result = {}
					for name in pairs(colours) do
						if name:sub(1, #prefix) == prefix then
							result[#result + 1] = name
						end
					end
					return result
				end,
			})
		end)

		it("parses with the package's function", function()
			shop:RegisterCommand({
				name = "paint",
				run = noop,
				arguments = { { name = "colour", type = "shop:colour" } },
			})
			expect.equal(parse("paint RED").values.colour, "#f00")
			expect.equal(usage("paint blue"), "<colour>: unknown colour 'blue'")
		end)

		it("can be used by other packages", function()
			local garage = register("garage")
			garage:RegisterCommand({ name = "spray", run = noop, arguments = { { name = "c", type = "shop:colour" } } })
			expect.equal(parse("spray green").values.c, "#0f0")
		end)

		it("isolates a failing parser", function()
			shop:RegisterArgumentType("broken", {
				parse = function()
					error("parser exploded")
				end,
			})
			shop:RegisterCommand({ name = "fix", run = noop, arguments = { { name = "thing", type = "shop:broken" } } })
			expect.equal(usage("fix x"), "<thing> could not be read")
			local logged = {}
			for _, entry in ipairs(lines) do
				logged[#logged + 1] = entry.line
			end
			expect.contains(table.concat(logged, "\n"), "argument_type callback of shop failed")
		end)

		it("validates the type definition and its name", function()
			expect.raises(function()
				shop:RegisterArgumentType("colour", { parse = noop })
			end, "the argument type 'shop:colour' is already registered")
			expect.raises(function()
				shop:RegisterArgumentType("garage:tool", { parse = noop })
			end, "must be in the 'shop' namespace")
			expect.raises(function()
				shop:RegisterArgumentType("tool", { parse = noop, check = noop })
			end, "unknown field 'check'")
			expect.raises(function()
				shop:RegisterArgumentType("tool", {})
			end, "'definition.parse' must be function (got nil)")
		end)

		it("goes away with its package", function()
			local garage = register("garage")
			garage:RegisterCommand({ name = "spray", run = noop, arguments = { { name = "c", type = "shop:colour" } } })
			runtime.packages:Disable("shop", "unload")
			expect.equal(usage("spray red"), "<c> could not be read")
			expect.raises(function()
				garage:RegisterCommand({
					name = "wash",
					run = noop,
					arguments = { { name = "c", type = "shop:colour" } },
				})
			end, "'shop:colour' is not an argument type")
		end)
	end)

	describe("suggestions", function()
		local function suggest(line)
			return runtime.commands:Suggest(line)
		end

		before_each(function()
			shop:RegisterArgumentType("colour", {
				parse = noop,
				suggest = function()
					return { "red", "green", 42 }
				end,
			})
			shop:RegisterCommand({
				name = "shop",
				aliases = { "store" },
				subcommands = {
					{
						name = "buy",
						run = noop,
						arguments = {
							{ name = "rarity", type = "enum", values = { "common", "rare" } },
							{ name = "gift", type = "boolean" },
						},
					},
					{
						name = "paint",
						run = noop,
						arguments = {
							{ name = "colour", type = "enum", values = { "blue" } },
							{ name = "note", type = "greedy" },
						},
					},
					{ name = "spray", run = noop, arguments = { { name = "colour", type = "shop:colour" } } },
				},
			})
			register("garage"):RegisterCommand({ name = "spawn", run = noop })
		end)

		it("completes command labels, without namespaced ones unless asked", function()
			expect.same(suggest("s"), { "shop", "spawn", "store" })
			expect.same(suggest("shop:"), { "shop:shop", "shop:store" })
			expect.same(suggest("ZZ"), {})
		end)

		it("completes subcommands and argument values", function()
			expect.same(suggest("shop "), { "buy", "paint", "spray" })
			expect.same(suggest("Store b"), { "buy" })
			expect.same(suggest("shop buy r"), { "rare" })
			expect.same(suggest("shop buy rare "), { "false", "true" })
			expect.same(suggest("shop spray "), { "green", "red" })
		end)

		it("stops after a greedy argument or past the last one", function()
			expect.same(suggest("shop paint b"), { "blue" })
			expect.same(suggest("shop paint blue some words "), {})
			expect.same(suggest("shop buy rare true "), {})
			expect.same(suggest('shop buy "unclosed'), {})
		end)
	end)
end)
