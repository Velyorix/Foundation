local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Senders = loader:require("foundation/core/senders.lua")
	local state = { now = 0, lines = {}, audited = {} }
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(level, line)
			state.lines[#state.lines + 1] = { level = level, line = line }
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
		now_ms = function()
			return state.now
		end,
		create_audit = function()
			return {
				Record = function(_, owner, action, entry)
					state.audited[#state.audited + 1] = { owner = owner, action = action, entry = entry }
					return true
				end,
			}
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
	local function sender(kind, id)
		local replies = {}
		local value = Senders.new({
			kind = kind,
			id = id,
			name = id or kind,
			reply = function(text)
				replies[#replies + 1] = text
			end,
		})
		return value, replies
	end
	return runtime, register, sender, state
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.line
	end
	return table.concat(parts, "\n")
end

describe("Command execution", function()
	local runtime, register, sender, state, homes, calls

	before_each(function()
		runtime, register, sender, state = setup()
		homes = register("homes")
		calls = {}
		homes:RegisterCommand({
			name = "home",
			description = "Teleport to a home",
			arguments = { { name = "name", default = "home" } },
			run = function(from, args, info)
				calls[#calls + 1] = { sender = from:GetName(), name = args.name, path = table.concat(info.path, " ") }
				from:Reply("welcome to " .. args.name)
			end,
			subcommands = {
				{
					name = "set",
					arguments = { { name = "name" }, { name = "note", type = "greedy", optional = true } },
					senders = { "player" },
					cooldown = 5000,
					audit = true,
					run = function(_, args)
						calls[#calls + 1] = { name = args.name }
					end,
				},
				{
					name = "purge",
					senders = { "console" },
					run = function()
						error("purge exploded")
					end,
				},
			},
		})
	end)

	local function execute(from, line)
		return runtime.commands:Execute(from, line).status
	end

	it("runs the command with the sender, the values and the path", function()
		local alex, replies = sender("player", "alex")
		expect.equal(execute(alex, "home base"), "ok")
		expect.same(calls, { { sender = "alex", name = "base", path = "home" } })
		expect.same(replies, { "welcome to base" })
	end)

	it("ignores lines that are not commands", function()
		local alex, replies = sender("player", "alex")
		expect.equal(execute(alex, "hello"), "unknown")
		expect.same(replies, {})
	end)

	it("answers wrong input with the problem and the usage line", function()
		local alex, replies = sender("player", "alex")
		expect.equal(execute(alex, "home set"), "usage")
		expect.same(replies, { "missing <name>", "Usage: /home set <name> [note...]" })
		local console, console_replies = sender("console")
		expect.equal(execute(console, "home a b"), "usage")
		expect.same(console_replies, { "too many arguments: b", "Usage: home [name]" })
	end)

	it("restricts commands to the declared senders", function()
		local console, replies = sender("console")
		expect.equal(execute(console, "home set base"), "denied")
		expect.same(replies, { "this command can only be used by players" })
		local alex, player_replies = sender("player", "alex")
		expect.equal(execute(alex, "home purge"), "denied")
		expect.same(player_replies, { "this command can only be used from the server console" })
		expect.equal(#calls, 0)
	end)

	it("applies cooldowns per player after a successful run", function()
		local alex, replies = sender("player", "alex")
		local sam = sender("player", "sam")
		expect.equal(execute(alex, "home set a"), "ok")
		state.now = 3000
		expect.equal(execute(alex, "home set b"), "cooldown")
		expect.same(replies, { "wait 2 s before using this command again" })
		expect.equal(execute(sam, "home set c"), "ok")
		state.now = 5000
		expect.equal(execute(alex, "home set d"), "ok")
	end)

	it("does not start the cooldown when the command fails", function()
		local attempts = 0
		homes:RegisterCommand({
			name = "claim",
			cooldown = 10000,
			run = function()
				attempts = attempts + 1
				if attempts == 1 then
					error("not this time")
				end
			end,
		})
		local alex = sender("player", "alex")
		expect.equal(execute(alex, "claim"), "failed")
		expect.equal(execute(alex, "claim"), "ok")
		expect.equal(execute(alex, "claim"), "cooldown")
	end)

	it("reports a failing command to the sender and logs it", function()
		local console, replies = sender("console")
		expect.equal(execute(console, "home purge"), "failed")
		expect.same(replies, { "the command failed; the error was logged" })
		expect.contains(text(state.lines), "command callback of homes failed")
		expect.contains(text(state.lines), "purge exploded")
	end)

	it("records audited commands with their outcome", function()
		local alex = sender("player", "alex")
		execute(alex, "home set base my main base")
		expect.same(state.audited, {
			{
				owner = "homes",
				action = "homes:command/home/set",
				entry = {
					actor = "player:alex",
					outcome = "success",
					details = { arguments = { name = "base", note = "my main base" } },
				},
			},
		})
		execute(alex, "home base")
		expect.equal(#state.audited, 1)
	end)

	describe("events", function()
		local watcher, seen

		before_each(function()
			watcher = register("watcher")
			seen = {}
			watcher:Listen("foundation:command", function(event)
				seen[#seen + 1] = "command:" .. event:Get("command") .. ":" .. event:Get("sender")
				if event:Get("arguments").name == "secret" then
					event:Cancel()
				end
			end)
			watcher:Listen("foundation:command_completed", function(event)
				seen[#seen + 1] = "completed:" .. event:Get("command") .. ":" .. event:Get("outcome")
			end)
		end)

		it("announces the command before and after it runs", function()
			execute(sender("player", "alex"), "home base")
			execute(sender("console"), "home purge")
			expect.same(seen, {
				"command:home:player",
				"completed:home:success",
				"command:home purge:console",
				"completed:home purge:failure",
			})
		end)

		it("lets a listener cancel the command", function()
			local alex, replies = sender("player", "alex")
			expect.equal(execute(alex, "home secret"), "cancelled")
			expect.same(seen, { "command:home:player" })
			expect.equal(#calls, 0)
			expect.same(replies, {})
		end)
	end)

	describe("usage and descriptions", function()
		it("writes usage lines from the declarations", function()
			homes:RegisterCommand({
				name = "admin",
				subcommands = { { name = "open", run = function() end }, { name = "close", run = function() end } },
			})
			local commands = runtime.commands
			local resolved = commands:Resolve({ "admin" })
			expect.equal(commands:Usage(resolved.node, "/"), "/admin <open|close>")
			resolved = commands:Resolve({ "home", "set" })
			expect.equal(commands:Usage(resolved.node, ""), "home set <name> [note...]")
		end)

		it("translates descriptions given as catalog keys", function()
			homes:RegisterCatalog("en", { ["help.warp"] = "Teleport to a warp" })
			homes:RegisterCatalog("fr", { ["help.warp"] = "Se téléporter à un warp" })
			homes:RegisterCommand({ name = "warp", description_key = "help.warp", run = function() end })
			local resolved = runtime.commands:Resolve({ "warp" })
			expect.equal(runtime.commands:Describe(resolved.root, resolved.node), "Teleport to a warp")
			expect.equal(runtime.commands:Describe(resolved.root, resolved.node, "fr"), "Se téléporter à un warp")
			resolved = runtime.commands:Resolve({ "home" })
			expect.equal(runtime.commands:Describe(resolved.root, resolved.node), "Teleport to a home")
		end)
	end)

	it("rejects malformed sender lists and cooldowns", function()
		expect.raises(function()
			homes:RegisterCommand({ name = "a", run = function() end, senders = { "rcon" } })
		end, "must list 'console', 'player' or both")
		expect.raises(function()
			homes:RegisterCommand({ name = "a", run = function() end, senders = {} })
		end, "must list 'console', 'player' or both")
		expect.raises(function()
			homes:RegisterCommand({ name = "a", run = function() end, cooldown = 1.5 })
		end, "must be a whole number of milliseconds")
		expect.raises(function()
			homes:RegisterCommand({ name = "a", run = function() end, audit = "yes" })
		end, "'spec.audit' must be boolean? (got string)")
	end)
end)
