local Arguments = Package.Require("arguments.lua")

local Commands = {}
Commands.__index = Commands

Commands.MAX_LABEL_LENGTH = 32
Commands.MAX_DEPTH = 8
Commands.RESERVED = { foundation = true }

local LABEL_PATTERN = "^[a-z][a-z0-9_-]*$"
local SPEC_FIELDS = {
	name = true,
	aliases = true,
	description = true,
	run = true,
	subcommands = true,
	arguments = true,
	description_key = true,
	senders = true,
	cooldown = true,
	audit = true,
}
local FIELD_TYPES = {
	{ "aliases", "table" },
	{ "description", "string" },
	{ "description_key", "string" },
	{ "run", "function" },
	{ "subcommands", "table" },
	{ "senders", "table" },
	{ "cooldown", "number" },
	{ "audit", "boolean" },
}
local SENDER_KINDS = { console = true, player = true }

-- options: check, log, arguments (core/arguments.lua instance), invoker, events, i18n,
-- now_ms, audit (function returning the audit sink or nil)
function Commands.new(options)
	return setmetatable({
		arguments = options.arguments,
		invoker = options.invoker,
		events = options.events,
		i18n = options.i18n,
		now_ms = options.now_ms,
		audit = options.audit,
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		log = options.log,
		roots = {},
		labels = {},
		sequence = 0,
		observers = {},
	}, Commands)
end

-- observer() runs after the set of labels changed (registration or removal).
function Commands:OnLabelsChanged(observer)
	self.observers[#self.observers + 1] = observer
end

function Commands:notify()
	local info = { owner = "foundation", kind = "command_observer" }
	for _, observer in ipairs(self.observers) do
		self.invoker:Call(info, observer)
	end
end

local function is_label(value)
	return type(value) == "string" and #value <= Commands.MAX_LABEL_LENGTH and value:match(LABEL_PATTERN) ~= nil
end

-- Returns the node, or nil and the failing field with a reason key and its params.
function Commands:build(spec, path, depth, owner)
	if type(spec) ~= "table" then
		return nil, path, false, { expected = "table", actual = type(spec) }
	end
	for key in pairs(spec) do
		if not SPEC_FIELDS[key] then
			return nil, path, "reason.manifest_unknown_field", { field = tostring(key) }
		end
	end
	if not is_label(spec.name) then
		return nil, path .. ".name", "reason.command_label", { max = Commands.MAX_LABEL_LENGTH }
	end
	if depth == 1 and owner ~= "foundation" and Commands.RESERVED[spec.name] then
		return nil, path .. ".name", "reason.command_reserved", { label = spec.name }
	end
	for _, pair in ipairs(FIELD_TYPES) do
		local field, expected = pair[1], pair[2]
		if spec[field] ~= nil and type(spec[field]) ~= expected then
			return nil, path .. "." .. field, false, { expected = expected .. "?", actual = type(spec[field]) }
		end
	end
	if depth > Commands.MAX_DEPTH then
		return nil, path, "reason.command_depth", { max = Commands.MAX_DEPTH }
	end

	local arguments = {}
	if spec.arguments ~= nil then
		local compiled, where, reason, params = self.arguments:Compile(spec.arguments, path .. ".arguments")
		if not compiled then
			return nil, where, reason, params
		end
		arguments = compiled
	end
	local senders
	if spec.senders ~= nil then
		senders = {}
		for _, kind in ipairs(spec.senders) do
			if not SENDER_KINDS[kind] then
				return nil, path .. ".senders", "reason.command_senders", nil
			end
			senders[kind] = true
		end
		if next(senders) == nil then
			return nil, path .. ".senders", "reason.command_senders", nil
		end
	end
	if spec.cooldown ~= nil and (math.type(spec.cooldown) ~= "integer" or spec.cooldown < 0) then
		return nil, path .. ".cooldown", "reason.command_cooldown", nil
	end
	local node = {
		name = spec.name,
		aliases = {},
		description = spec.description,
		description_key = spec.description_key,
		run = spec.run,
		arguments = arguments,
		senders = senders,
		cooldown = spec.cooldown,
		audit = spec.audit == true,
		cooldowns = {},
		children = {},
		lookup = {},
	}
	local seen = { [spec.name] = true }
	for index, alias in ipairs(spec.aliases or {}) do
		local where = path .. ".aliases[" .. index .. "]"
		if not is_label(alias) then
			return nil, where, "reason.command_label", { max = Commands.MAX_LABEL_LENGTH }
		end
		if depth == 1 and owner ~= "foundation" and Commands.RESERVED[alias] then
			return nil, where, "reason.command_reserved", { label = alias }
		end
		if seen[alias] then
			return nil, where, "reason.command_duplicate_label", { label = alias, parent = spec.name }
		end
		seen[alias] = true
		node.aliases[#node.aliases + 1] = alias
	end
	for index, child_spec in ipairs(spec.subcommands or {}) do
		local child_path = path .. ".subcommands[" .. index .. "]"
		local child, where, reason, params = self:build(child_spec, child_path, depth + 1)
		if not child then
			return nil, where, reason, params
		end
		for _, label in ipairs({ child.name, table.unpack(child.aliases) }) do
			if node.lookup[label] then
				return nil, child_path, "reason.command_duplicate_label", { label = label, parent = spec.name }
			end
			node.lookup[label] = child
		end
		child.parent = node
		node.children[#node.children + 1] = child
	end
	if not node.run and #node.children == 0 then
		return nil, path, "reason.command_empty", nil
	end
	return node
end

-- Plain labels: names first, in registration order, then aliases where still free.
-- "<owner>:<label>" always reaches the command.
function Commands:rebuild()
	local labels = {}
	for _, root in ipairs(self.roots) do
		if not labels[root.name] then
			labels[root.name] = { root = root, kind = "name" }
		end
	end
	for _, root in ipairs(self.roots) do
		for _, alias in ipairs(root.aliases) do
			if not labels[alias] then
				labels[alias] = { root = root, kind = "alias" }
			end
		end
	end
	for _, root in ipairs(self.roots) do
		for _, label in ipairs({ root.name, table.unpack(root.aliases) }) do
			labels[root.owner .. ":" .. label] = { root = root, kind = "namespaced" }
		end
	end
	local previous = self.labels
	self.labels = labels
	return previous
end

function Commands:report_conflicts(root, previous)
	local log = self.log:For(root.owner, "commands")
	local holder = self.labels[root.name].root
	if holder ~= root then
		log:Warning("commands.label_taken", {
			label = root.name,
			owner = root.owner,
			holder = holder.owner,
			fallback = root.owner .. ":" .. root.name,
		})
	end
	for _, alias in ipairs(root.aliases) do
		local entry = self.labels[alias]
		if entry.root ~= root then
			log:Warning("commands.alias_taken", { label = alias, owner = root.owner, holder = entry.root.owner })
		end
	end
	for label, entry in pairs(previous) do
		local now = self.labels[label]
		if entry.kind == "alias" and now and now.root == root and entry.root ~= root then
			self.log
				:For(entry.root.owner, "commands")
				:Warning("commands.alias_lost", { label = label, holder = entry.root.owner, owner = root.owner })
		end
	end
end

-- Returns the root node and a release function for the owner's resource tracking.
function Commands:Register(owner, spec, api, level)
	self.check:Argument(api, 1, "spec", spec, "table", level)
	local root, where, reason_key, params = self:build(spec, "spec", 1, owner)
	if not root and reason_key == false then
		self.errors:Raise("invalid_argument", {
			api = api,
			index = 1,
			name = where,
			expected = params.expected,
			actual = params.actual,
		}, level)
	elseif not root then
		self.errors:Raise("invalid_value", {
			api = api,
			index = 1,
			name = where,
			reason = self.messages:Format(reason_key, params),
		}, level)
	end
	for _, other in ipairs(self.roots) do
		if other.owner == owner then
			for _, label in ipairs({ root.name, table.unpack(root.aliases) }) do
				if other.lookup_labels[label] then
					self.errors:Raise("invalid_state", {
						api = api,
						reason = self.messages:Format("reason.command_exists", { label = label, name = other.name }),
					}, level)
				end
			end
		end
	end

	self.sequence = self.sequence + 1
	root.owner = owner
	root.id = self.sequence
	root.lookup_labels = { [root.name] = true }
	for _, alias in ipairs(root.aliases) do
		root.lookup_labels[alias] = true
	end
	self.roots[#self.roots + 1] = root
	self:report_conflicts(root, self:rebuild())
	self:notify()
	return root,
		function()
			for index, other in ipairs(self.roots) do
				if other == root then
					table.remove(self.roots, index)
					break
				end
			end
			root.removed = true
			self:rebuild()
			self:notify()
		end
end

-- tokens: words typed after the command prefix. Returns { root, node, path, arguments }
-- for the deepest matching subcommand, or nil when the first word is not a command.
function Commands:Resolve(tokens)
	local first = tokens[1]
	local entry = type(first) == "string" and self.labels[first:lower()]
	if not entry then
		return nil
	end
	local node = entry.root
	local path = { node.name }
	local index = 2
	while tokens[index] do
		local child = node.lookup[tokens[index]:lower()]
		if not child then
			break
		end
		node = child
		path[#path + 1] = child.name
		index = index + 1
	end
	return {
		root = entry.root,
		node = node,
		path = path,
		index = index,
		arguments = { table.unpack(tokens, index) },
	}
end

local function texts(tokens, last)
	local words = {}
	for index = 1, last or #tokens do
		words[index] = tokens[index].text
	end
	return words
end

-- Parses a typed command line (without the leading '/'). Returns nil when the first word
-- is not a command; nil and a `command_usage` error when the input is wrong; otherwise
-- { root, node, path, values }.
function Commands:Parse(line)
	local tokens, reason = Arguments.Split(line)
	if not tokens then
		local _, err = self.arguments:usage_error(reason)
		return nil, err
	end
	local result = self:Resolve(texts(tokens))
	if not result then
		return nil
	end
	local node = result.node
	if not node.run then
		local choices = {}
		for _, child in ipairs(node.children) do
			choices[#choices + 1] = child.name
		end
		local _, err =
			self.arguments:usage_error("command.choose_subcommand", { choices = table.concat(choices, ", ") })
		return nil, err
	end
	local values, err = self.arguments:Parse(node.arguments, tokens, result.index, line)
	if not values then
		return nil, err
	end
	return { root = result.root, node = node, path = result.path, values = values }
end

local function add_labels(result, seen, labels, prefix)
	for _, label in ipairs(labels) do
		if not seen[label] and label:sub(1, #prefix) == prefix then
			seen[label] = true
			result[#result + 1] = label
		end
	end
end

local function finish(result)
	table.sort(result)
	while #result > Arguments.MAX_SUGGESTIONS do
		result[#result] = nil
	end
	return result
end

-- Completions for the word being typed at the end of `line`.
function Commands:Suggest(line)
	local tokens = Arguments.Split(line)
	if not tokens then
		return {}
	end
	local prefix = ""
	local completed = #tokens
	if #tokens > 0 and not line:match("%s$") then
		prefix = tokens[#tokens].text:lower()
		completed = #tokens - 1
	end
	local result, seen = {}, {}
	if completed == 0 then
		local labels = {}
		for label, entry in pairs(self.labels) do
			if entry.kind ~= "namespaced" or prefix:find(":", 1, true) then
				labels[#labels + 1] = label
			end
		end
		add_labels(result, seen, labels, prefix)
		return finish(result)
	end
	local resolved = self:Resolve(texts(tokens, completed))
	if not resolved then
		return {}
	end
	local node = resolved.node
	local position = completed - resolved.index + 2
	if position == 1 then
		local labels = {}
		for label in pairs(node.lookup) do
			labels[#labels + 1] = label
		end
		add_labels(result, seen, labels, prefix)
	end
	for index = 1, position - 1 do
		local previous = node.arguments[index]
		if not previous or (previous.builtin and previous.builtin.greedy) then
			return finish(result)
		end
	end
	local declaration = node.arguments[position]
	if declaration then
		self.arguments:Suggest(declaration, prefix, result, seen)
	end
	return finish(result)
end

local function node_path(node)
	local names = {}
	while node do
		table.insert(names, 1, node.name)
		node = node.parent
	end
	return names
end

local function argument_usage(argument)
	local name = argument.name
	if argument.builtin and argument.builtin.greedy then
		name = name .. "..."
	end
	if argument.optional then
		return "[" .. name .. "]"
	end
	return "<" .. name .. ">"
end

-- Usage line of a node: "/home set <name> [note...]", or "/admin <open|close>" for a node
-- that only groups subcommands. `prefix` is "/" for players and "" for the console.
function Commands:Usage(node, prefix)
	local parts = { (prefix or "") .. table.concat(node_path(node), " ") }
	if not node.run then
		local names = {}
		for _, child in ipairs(node.children) do
			names[#names + 1] = child.name
		end
		parts[#parts + 1] = "<" .. table.concat(names, "|") .. ">"
	else
		for _, argument in ipairs(node.arguments) do
			parts[#parts + 1] = argument_usage(argument)
		end
	end
	return table.concat(parts, " ")
end

-- Description of a node in `locale`: description_key is looked up in the owner's catalogs
-- (Foundation's own commands use the core messages).
function Commands:Describe(root, node, locale)
	if node.description_key and root.owner == "foundation" then
		return self.messages:Format(node.description_key)
	end
	if node.description_key and self.i18n then
		local text = self.i18n:Translate(root.owner, node.description_key, nil, locale, "Commands:Describe", 2)
		return text
	end
	return node.description
end

local function audit_value(value)
	local kind = type(value)
	if kind == "string" or kind == "number" or kind == "boolean" then
		return value
	end
	return tostring(value)
end

function Commands:record_audit(root, path, sender, values, outcome)
	local audit = self.audit and self.audit()
	if not audit then
		return
	end
	local arguments = {}
	for name, value in pairs(values) do
		arguments[name] = audit_value(value)
	end
	local info = { owner = root.owner, kind = "command_audit", fields = { command = table.concat(path, " ") } }
	self.invoker:Call(info, function()
		audit:Record(root.owner, root.owner .. ":command/" .. table.concat(path, "/"), {
			actor = sender.kind == "console" and "console" or ("player:" .. tostring(sender.id)),
			outcome = outcome,
			details = { arguments = arguments },
		})
	end)
end

function Commands:usage_node(line)
	local tokens = Arguments.Split(line)
	if not tokens then
		return nil
	end
	local resolved = self:Resolve(texts(tokens))
	return resolved and resolved.node
end

-- Runs a typed command line for `sender` (core/senders.lua): parse, check the sender
-- kind and cooldown, emit foundation:command (cancellable), run, record the audit entry
-- when asked, emit foundation:command_completed. Replies go to the sender.
-- Returns { status = "ok" | "unknown" | "usage" | "denied" | "cooldown" | "cancelled" | "failed" }.
function Commands:Execute(sender, line)
	local prefix = sender:IsPlayer() and "/" or ""
	local parsed, err = self:Parse(line)
	if not parsed then
		if not err then
			return { status = "unknown" }
		end
		sender:Reply(err.message)
		local node = self:usage_node(line)
		if node then
			sender:Reply(self.messages:Format("command.usage", { usage = self:Usage(node, prefix) }))
		end
		return { status = "usage", error = err }
	end

	local node, root = parsed.node, parsed.root
	if node.senders and not node.senders[sender.kind] then
		sender:Reply(
			self.messages:Format(sender.kind == "console" and "command.players_only" or "command.console_only")
		)
		return { status = "denied" }
	end
	local now = self.now_ms()
	local cooled = node.cooldown and node.cooldown > 0 and not sender:IsConsole()
	if cooled then
		local ready_at = node.cooldowns[sender.id]
		if ready_at and ready_at > now then
			sender:Reply(self.messages:Format("command.cooldown", { seconds = math.ceil((ready_at - now) / 1000) }))
			return { status = "cooldown" }
		end
	end

	local command = table.concat(parsed.path, " ")
	local payload = {
		command = command,
		owner = root.owner,
		sender = sender.kind,
		name = sender.name,
		arguments = parsed.values,
	}
	if self.events:Emit("foundation", "command", payload, "Commands:Execute", 2):IsCancelled() then
		return { status = "cancelled" }
	end

	local info = { owner = root.owner, kind = "command", fields = { command = command } }
	local ok = self.invoker:Call(info, node.run, sender, parsed.values, { path = parsed.path, line = line })
	if ok and cooled then
		node.cooldowns[sender.id] = now + node.cooldown
	end
	if not ok then
		sender:Reply(self.messages:Format("command.failed"))
	end
	local outcome = ok and "success" or "failure"
	if node.audit then
		self:record_audit(root, parsed.path, sender, parsed.values, outcome)
	end
	payload.outcome = outcome
	self.events:Emit("foundation", "command_completed", payload, "Commands:Execute", 2)
	return { status = ok and "ok" or "failed" }
end

-- Plain and namespaced labels with the owner and command name they lead to.
function Commands:Labels()
	local result = {}
	for label, entry in pairs(self.labels) do
		result[label] = { owner = entry.root.owner, name = entry.root.name, kind = entry.kind }
	end
	return result
end

function Commands:Snapshot()
	local commands = {}
	for _, root in ipairs(self.roots) do
		local labels = {}
		for label, entry in pairs(self.labels) do
			if entry.root == root then
				labels[#labels + 1] = label
			end
		end
		table.sort(labels)
		commands[#commands + 1] = { owner = root.owner, name = root.name, labels = labels }
	end
	return { commands = commands }
end

return Commands
