local function fake_console()
	local console = { commands = {}, logged = {}, registrations = 0 }
	function console.RegisterCommand(label, callback, description)
		console.registrations = console.registrations + 1
		console.commands[label] = { callback = callback, description = description }
	end
	function console.Log(format, ...)
		console.logged[#console.logged + 1] = string.format(format, ...)
	end
	-- Like the engine: words split on every single space.
	function console.Run(text)
		local words = {}
		for word in (text .. " "):gmatch("(.-) ") do
			words[#words + 1] = word
		end
		local label = table.remove(words, 1)
		console.commands[label].callback(table.unpack(words))
	end
	return console
end

local function fake_chat()
	local chat = { sent = {} }
	function chat.Subscribe(event, handler)
		chat[event] = handler
		return handler
	end
	function chat.SendMessage(player, text)
		chat.sent[#chat.sent + 1] = player:GetAccountName() .. ": " .. text
	end
	return chat
end

local function fake_player(name)
	return {
		GetAccountID = function()
			return "id-" .. name
		end,
		GetAccountName = function()
			return name
		end,
	}
end

local function setup()
	local loader = Loader.new({ side = "Server" })
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Bridges = loader:require("foundation/core/command_bridges.lua")
	local Senders = loader:require("foundation/core/senders.lua")
	local console, chat = fake_console(), fake_chat()
	local settings = { unknown_in_chat = "reply" }
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
		create_command_bridges = function(rt)
			return Bridges.new({
				commands = rt.commands,
				senders = Senders,
				console = console,
				chat = chat,
				messages = rt.messages,
				invoker = rt.invoker,
				setting = function(name)
					return settings[name]
				end,
			})
		end,
	})
	runtime:Start()
	local native = {
		GetName = function()
			return "shop"
		end,
		Subscribe = function() end,
	}
	local context = runtime.packages:Register(native, { api = "0.1" })
	return runtime, context, console, chat, settings
end

describe("Command bridges", function()
	local runtime, shop, console, chat, settings, received

	before_each(function()
		runtime, shop, console, chat, settings = setup()
		received = {}
		shop:RegisterCommand({
			name = "give",
			aliases = { "g" },
			description = "Give an item",
			arguments = { { name = "item" }, { name = "amount", type = "integer", default = 1 } },
			run = function(sender, args)
				received[#received + 1] = sender:GetKind()
					.. ":"
					.. sender:GetName()
					.. ":"
					.. args.item
					.. "x"
					.. args.amount
				sender:Reply("done")
			end,
		})
	end)

	describe("console", function()
		it("registers every label with the command description", function()
			expect.same(console.commands.give.description, "Give an item")
			expect.truthy(console.commands.g)
			expect.truthy(console.commands["shop:give"])
			expect.truthy(console.commands["shop:g"])
		end)

		it("rebuilds the typed line, quotes included", function()
			console.Run('give "golden  apple" 3')
			console.Run("g pear")
			expect.same(received, { "console:console:golden  applex3", "console:console:pearx1" })
			expect.same(console.logged, { "done", "done" })
		end)

		it("answers wrong input with the problem and the usage", function()
			console.Run("give apple many")
			expect.same(console.logged, { "<amount>: 'many' is not a whole number", "Usage: give <item> [amount]" })
		end)

		it("keeps the label but answers unknown command once the command is gone", function()
			runtime.packages:Disable("shop", "unload")
			console.Run("give apple")
			expect.same(console.logged, { "unknown command: give" })
			expect.same(received, {})
		end)

		it("registers labels added later, once", function()
			local before = console.registrations
			shop:RegisterCommand({ name = "sell", run = function() end })
			expect.equal(console.registrations, before + 2)
			shop:RegisterCommand({ name = "trade", run = function() end })
			expect.equal(console.registrations, before + 4)
		end)
	end)

	describe("chat", function()
		local alex

		before_each(function()
			alex = fake_player("alex")
		end)

		it("runs commands for the player and hides the message", function()
			expect.equal(chat.PlayerSubmit("/give apple 2", alex), false)
			expect.same(received, { "player:alex:applex2" })
			expect.same(chat.sent, { "alex: done" })
		end)

		it("leaves ordinary messages alone", function()
			expect.is_nil(chat.PlayerSubmit("hello /give", alex))
			expect.same(received, {})
		end)

		it("answers unknown commands by default", function()
			expect.equal(chat.PlayerSubmit("/fly", alex), false)
			expect.same(chat.sent, { "alex: unknown command: /fly" })
		end)

		it("passes unknown commands on when configured", function()
			settings.unknown_in_chat = "pass"
			expect.is_nil(chat.PlayerSubmit("/fly", alex))
			expect.same(chat.sent, {})
			expect.equal(chat.PlayerSubmit("/give apple", alex), false)
		end)

		it("uses the player's account id for cooldowns", function()
			shop:RegisterCommand({ name = "daily", cooldown = 60000, run = function() end })
			chat.PlayerSubmit("/daily", alex)
			chat.PlayerSubmit("/daily", alex)
			chat.PlayerSubmit("/daily", fake_player("sam"))
			expect.same(chat.sent, { "alex: wait 60 s before using this command again" })
		end)
	end)
end)
