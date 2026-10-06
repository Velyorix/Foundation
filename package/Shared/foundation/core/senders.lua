local Senders = {}

local Sender = {}
Sender.__index = Sender

Senders.KINDS = { "console", "player" }

-- fields: kind ("console" or "player"), id (stable per sender, used for cooldowns), name,
-- reply(text), and for players the native player object and its locale.
function Senders.new(fields)
	return setmetatable({
		kind = fields.kind,
		id = fields.id or fields.kind,
		name = fields.name or fields.kind,
		reply = fields.reply,
		player = fields.player,
		locale = fields.locale,
	}, Sender)
end

function Senders.IsSender(value)
	return type(value) == "table" and getmetatable(value) == Sender
end

function Sender:GetKind()
	return self.kind
end

function Sender:IsConsole()
	return self.kind == "console"
end

function Sender:IsPlayer()
	return self.kind == "player"
end

function Sender:GetId()
	return self.id
end

function Sender:GetName()
	return self.name
end

function Sender:GetPlayer()
	return self.player
end

-- nil means the server language.
function Sender:GetLocale()
	return self.locale
end

function Sender:Reply(text)
	self.reply(tostring(text))
end

return Senders
