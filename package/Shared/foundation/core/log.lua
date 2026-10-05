-- Structured logger.
--
-- Line format (stable, one record per line unless a trace is attached):
--   [foundation] <LEVEL> <owner>/<domain>: <message>[ <field>=<value> ...]
-- LEVEL is DEBUG, INFO, WARN or ERROR. Fields are sorted by name; values containing
-- spaces, quotes or '=' are quoted. A `trace` field is written on the following lines.
--
-- Messages are catalog keys rendered through core/messages.lua. Secrets are masked in
-- the final line: fields whose name looks sensitive, and any value registered with
-- RegisterSecret. Identical lines repeated within the suppression window are written
-- once; the number of suppressed repeats is reported when the line appears again after
-- the window, or on Flush.

local Log = {}

local LEVELS = { debug = 1, info = 2, warning = 3, error = 4 }
local LEVEL_TAGS = { debug = "DEBUG", info = "INFO ", warning = "WARN ", error = "ERROR" }
Log.LEVELS = { "debug", "info", "warning", "error" }

local MASK = "***"
local SENSITIVE_FIELD =
	{ "password", "passwd", "secret", "token", "credential", "authorization", "connection_string", "api_key", "apikey" }
local MIN_SECRET_LENGTH = 4
local DEFAULT_REPEAT_WINDOW = 10
local MAX_TRACKED_LINES = 256

local function is_sensitive_field(name)
	local lowered = name:lower()
	for _, fragment in ipairs(SENSITIVE_FIELD) do
		if lowered:find(fragment, 1, true) then
			return true
		end
	end
	return false
end

local function format_value(value)
	local text = tostring(value)
	if text == "" or text:find('[%s"=]') then
		return (string.format("%q", text):gsub("\\\n", "\\n"))
	end
	return text
end

local function replace_plain(text, needle, replacement)
	local result, position = {}, 1
	while true do
		local first, last = text:find(needle, position, true)
		if not first then
			break
		end
		result[#result + 1] = text:sub(position, first - 1)
		result[#result + 1] = replacement
		position = last + 1
	end
	result[#result + 1] = text:sub(position)
	return table.concat(result)
end

-- Shared state of a logger tree: configuration, secrets and repeat tracking.
local Core = {}
Core.__index = Core

local Logger = {}
Logger.__index = Logger

--- Creates the root logger.
-- options.sink            function(level, line) writing a finished line (required)
-- options.messages        core/messages.lua instance used to render keys (required)
-- options.clock           function() -> seconds, monotonic enough for repeat windows (required)
-- options.level           minimum level, one of Log.LEVELS (default "info")
-- options.repeat_window   seconds during which identical lines are suppressed (default 10, 0 disables)
-- options.owner, options.domain  context of the root logger (default "foundation", "core")
function Log.new(options)
	local core = setmetatable({
		sink = options.sink,
		messages = options.messages,
		clock = options.clock,
		level = options.level or "info",
		repeat_window = options.repeat_window or DEFAULT_REPEAT_WINDOW,
		categories = {},
		secrets = {},
		recent = {},
		recent_count = 0,
	}, Core)
	return setmetatable(
		{ core = core, owner = options.owner or "foundation", domain = options.domain or "core" },
		Logger
	)
end

--- Returns a logger writing with another owner and/or domain, sharing configuration.
function Logger:For(owner, domain)
	return setmetatable({ core = self.core, owner = owner or self.owner, domain = domain or self.domain }, Logger)
end

function Logger:GetOwner()
	return self.owner
end

function Logger:GetDomain()
	return self.domain
end

--- Sets the minimum level for the whole logger tree. Returns false, without changing
-- anything, when `level` is not one of Log.LEVELS.
function Logger:SetLevel(level)
	if not LEVELS[level] then
		return false
	end
	self.core.level = level
	return true
end

function Logger:GetLevel()
	return self.core.level
end

--- Enables debug output for one domain regardless of the minimum level.
function Logger:EnableDebugCategory(domain)
	self.core.categories[domain] = true
end

function Logger:DisableDebugCategory(domain)
	self.core.categories[domain] = nil
end

--- Masks every future occurrence of `value` in log lines. Values shorter than four
-- characters are ignored to avoid masking ordinary text.
function Logger:RegisterSecret(value)
	if type(value) == "string" and #value >= MIN_SECRET_LENGTH then
		self.core.secrets[value] = true
	end
end

function Logger:IsEnabled(level)
	local core = self.core
	if level == "debug" and core.categories[self.domain] then
		return true
	end
	return LEVELS[level] >= LEVELS[core.level]
end

function Core:mask(text)
	for secret in pairs(self.secrets) do
		text = replace_plain(text, secret, MASK)
	end
	return text
end

function Logger:render(level, key, params, fields)
	local parts = {
		"[foundation] ",
		LEVEL_TAGS[level],
		" ",
		self.owner,
		"/",
		self.domain,
		": ",
		self.core.messages:Format(key, params),
	}
	local trace
	if fields then
		local names = {}
		for name in pairs(fields) do
			if name == "trace" then
				trace = tostring(fields.trace)
			else
				names[#names + 1] = name
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local value = is_sensitive_field(name) and MASK or format_value(fields[name])
			parts[#parts + 1] = " " .. name .. "=" .. value
		end
	end
	local line = table.concat(parts)
	if trace then
		line = line .. "\n" .. trace
	end
	return self.core:mask(line)
end

function Core:emit_repeats(level, entry)
	if entry.suppressed > 0 then
		local summary = self.messages:Format("log.repeated", { count = entry.suppressed })
		self.sink(level, entry.prefix .. summary)
		entry.suppressed = 0
	end
end

function Core:track(level, line, prefix)
	if self.repeat_window <= 0 then
		return true
	end
	local now = self.clock()
	local entry = self.recent[line]
	if entry and now - entry.since < self.repeat_window then
		entry.suppressed = entry.suppressed + 1
		return false
	end
	if entry then
		self:emit_repeats(level, entry)
		entry.since = now
		return true
	end
	if self.recent_count >= MAX_TRACKED_LINES then
		self:flush_repeats()
	end
	self.recent[line] = { since = now, suppressed = 0, level = level, prefix = prefix }
	self.recent_count = self.recent_count + 1
	return true
end

function Core:flush_repeats()
	for _, entry in pairs(self.recent) do
		self:emit_repeats(entry.level, entry)
	end
	self.recent = {}
	self.recent_count = 0
end

--- Writes pending repeat summaries and forgets tracked lines. Called at shutdown.
function Logger:Flush()
	self.core:flush_repeats()
end

--- Writes a record. Prefer the level methods below.
function Logger:Write(level, key, params, fields)
	if not LEVELS[level] or not self:IsEnabled(level) then
		return
	end
	local line = self:render(level, key, params, fields)
	local prefix = "[foundation] " .. LEVEL_TAGS[level] .. " " .. self.owner .. "/" .. self.domain .. ": "
	if self.core:track(level, line, prefix) then
		self.core.sink(level, line)
	end
end

function Logger:Debug(key, params, fields)
	self:Write("debug", key, params, fields)
end

function Logger:Info(key, params, fields)
	self:Write("info", key, params, fields)
end

function Logger:Warning(key, params, fields)
	self:Write("warning", key, params, fields)
end

function Logger:Error(key, params, fields)
	self:Write("error", key, params, fields)
end

--- Sink writing to the nanos world console. Lines are passed as a "%s" argument
-- because Console functions format their first argument with string.format.
function Log.console_sink(console)
	local writers = {
		debug = console.Log,
		info = console.Log,
		warning = console.Warn,
		error = console.Error,
	}
	return function(level, line)
		writers[level]("%s", line)
	end
end

return Log
