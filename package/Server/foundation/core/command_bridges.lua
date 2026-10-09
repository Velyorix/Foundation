local Bridges = {}
Bridges.__index = Bridges

-- options: commands, senders (core/senders.lua), console (Console), chat (Chat),
-- messages, invoker, setting(name) returning a value of the [commands] settings.
function Bridges.new(options)
	return setmetatable({
		commands = options.commands,
		senders = options.senders,
		console = options.console,
		chat = options.chat,
		messages = options.messages,
		invoker = options.invoker,
		setting = options.setting,
		registered = {},
	}, Bridges)
end

function Bridges:Start()
	self.console_sender = self.senders.new({
		kind = "console",
		name = "console",
		reply = function(text)
			self.console.Log("%s", text)
		end,
	})
	self.chat_handler = function(message, player)
		local _, suppress =
			self.invoker:Call({ owner = "foundation", kind = "chat_command" }, self.on_chat, self, message, player)
		if suppress then
			return false
		end
	end
	self.chat.Subscribe("PlayerSubmit", self.chat_handler)
	self:Sync()
end

local function first_word(line)
	return line:match("^%s*(%S*)")
end

function Bridges:run(sender, line)
	local result = self.commands:Execute(sender, line)
	if result.status == "unknown" then
		sender:Reply(self.messages:Format("command.unknown", { label = first_word(line) }))
	end
	return result
end

-- The engine has no unregister: a label stays registered and answers "unknown command"
-- once its command is gone.
function Bridges:Sync()
	for label in pairs(self.commands:Labels()) do
		if not self.registered[label] then
			self.registered[label] = true
			self.console.RegisterCommand(label, function(...)
				local count = select("#", ...)
				local line = label
				if count > 0 then
					line = label .. " " .. table.concat({ ... }, " ", 1, count)
				end
				self.invoker:Call(
					{ owner = "foundation", kind = "console_command" },
					self.run,
					self,
					self.console_sender,
					line
				)
			end, self:description(label))
		end
	end
end

function Bridges:description(label)
	local resolved = self.commands:Resolve({ label })
	return resolved and self.commands:Describe(resolved.root, resolved.node) or nil
end

local function call_method(object, name)
	local method = object and object[name]
	if type(method) == "function" then
		local ok, value = pcall(method, object)
		if ok then
			return value
		end
	end
	return nil
end

function Bridges:player_sender(player)
	local id = call_method(player, "GetAccountID") or call_method(player, "GetID")
	return self.senders.new({
		kind = "player",
		id = tostring(id),
		name = tostring(call_method(player, "GetAccountName") or call_method(player, "GetName") or id),
		player = player,
		reply = function(text)
			self.chat.SendMessage(player, text)
		end,
	})
end

-- Returns true when the message was handled and must not reach the chat.
function Bridges:on_chat(message, player)
	if type(message) ~= "string" or message:sub(1, 1) ~= "/" then
		return false
	end
	local sender = self:player_sender(player)
	local line = message:sub(2)
	local result = self.commands:Execute(sender, line)
	if result.status ~= "unknown" then
		return true
	end
	if self.setting("unknown_in_chat") == "pass" then
		return false
	end
	sender:Reply(self.messages:Format("command.unknown", { label = "/" .. first_word(line) }))
	return true
end

function Bridges:Snapshot()
	local labels = {}
	for label in pairs(self.registered) do
		labels[#labels + 1] = label
	end
	table.sort(labels)
	return { console_labels = labels }
end

return Bridges
