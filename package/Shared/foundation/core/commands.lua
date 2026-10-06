local Commands = {}
Commands.__index = Commands

Commands.MAX_LABEL_LENGTH = 32
Commands.MAX_DEPTH = 8
Commands.RESERVED = { foundation = true }

local LABEL_PATTERN = "^[a-z][a-z0-9_-]*$"
local SPEC_FIELDS = { name = true, aliases = true, description = true, run = true, subcommands = true }
local FIELD_TYPES = {
	{ "aliases", "table" },
	{ "description", "string" },
	{ "run", "function" },
	{ "subcommands", "table" },
}

-- options: check, log
function Commands.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		log = options.log,
		roots = {},
		labels = {},
		sequence = 0,
	}, Commands)
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

	local node = {
		name = spec.name,
		aliases = {},
		description = spec.description,
		run = spec.run,
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
	return { root = entry.root, node = node, path = path, arguments = { table.unpack(tokens, index) } }
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
