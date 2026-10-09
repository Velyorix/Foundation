-- Foundation's own commands, under the reserved "foundation" root. Console only until
-- permissions exist.
local Admin = {}

local function prefix_for(sender)
	return sender:IsPlayer() and "/" or ""
end

local function describe_line(runtime, root, node, prefix)
	local commands = runtime.commands
	local usage = commands:Usage(node, prefix)
	local description = commands:Describe(root, node)
	if description and description ~= "" then
		return runtime.messages:Format("admin.help_line", { usage = usage, description = description })
	end
	return usage
end

local function help(runtime, sender, args)
	local commands, messages = runtime.commands, runtime.messages
	local prefix = prefix_for(sender)
	if not args.command then
		local roots = {}
		for _, root in ipairs(commands.roots) do
			roots[#roots + 1] = root
		end
		table.sort(roots, function(a, b)
			return a.name < b.name or (a.name == b.name and a.owner < b.owner)
		end)
		sender:Reply(messages:Format("admin.help_header", { count = #roots }))
		for _, root in ipairs(roots) do
			sender:Reply(describe_line(runtime, root, root, prefix))
		end
		return
	end
	local words = {}
	for word in args.command:gmatch("%S+") do
		words[#words + 1] = word
	end
	local resolved = commands:Resolve(words)
	if not resolved then
		sender:Reply(messages:Format("command.unknown", { label = words[1] or "" }))
		return
	end
	local node = resolved.node
	sender:Reply(describe_line(runtime, resolved.root, node, prefix))
	if #node.aliases > 0 then
		sender:Reply(messages:Format("admin.help_aliases", { aliases = table.concat(node.aliases, ", ") }))
	end
	for _, child in ipairs(node.children) do
		sender:Reply("  " .. describe_line(runtime, resolved.root, child, prefix))
	end
end

local function packages(runtime, sender)
	local messages = runtime.messages
	local list = runtime.packages:Snapshot().packages
	if #list == 0 then
		sender:Reply(messages:Format("admin.packages_none"))
		return
	end
	sender:Reply(messages:Format("admin.packages_header", { count = #list }))
	for _, entry in ipairs(list) do
		local params = { id = entry.id, version = entry.version or "?", state = entry.state, reason = entry.failure }
		sender:Reply(messages:Format(entry.failure and "admin.package_failed" or "admin.package_line", params))
	end
end

local function report_file(messages, sender, result)
	if result.error then
		sender:Reply(messages:Format("admin.reload_rejected", { path = result.path }))
		return
	end
	if #result.changed > 0 then
		sender:Reply(messages:Format("admin.reload_changed", { path = result.path, count = #result.changed }))
	else
		sender:Reply(messages:Format("admin.reload_unchanged", { path = result.path }))
	end
	if #result.pending > 0 then
		sender:Reply(
			messages:Format("admin.reload_pending", { path = result.path, keys = table.concat(result.pending, ", ") })
		)
	end
end

local function reload_config(runtime, sender)
	local report = runtime:ReloadConfig()
	local files = 0
	if report.core then
		files = files + 1
		report_file(runtime.messages, sender, report.core)
	end
	for _, owner in ipairs(runtime.package_configs and runtime.package_configs.order or {}) do
		local result = report.packages[owner]
		if result then
			files = files + 1
			report_file(runtime.messages, sender, result)
		end
	end
	if files == 0 then
		sender:Reply(runtime.messages:Format("admin.reload_none"))
	end
end

function Admin.Register(runtime)
	local function bind(fn)
		return function(sender, args)
			fn(runtime, sender, args)
		end
	end
	runtime.commands:Register("foundation", {
		name = "foundation",
		description_key = "admin.description.root",
		subcommands = {
			{
				name = "version",
				description_key = "admin.description.version",
				senders = { "console" },
				run = function(sender)
					sender:Reply(runtime.messages:Format("admin.version", {
						version = runtime.env.version,
						api = runtime.env.api_version,
					}))
				end,
			},
			{
				name = "help",
				description_key = "admin.description.help",
				senders = { "console" },
				arguments = { { name = "command", type = "greedy", optional = true } },
				run = bind(help),
			},
			{
				name = "packages",
				description_key = "admin.description.packages",
				senders = { "console" },
				run = bind(packages),
			},
			{
				name = "reload-config",
				description_key = "admin.description.reload_config",
				senders = { "console" },
				audit = true,
				run = bind(reload_config),
			},
		},
	}, "Runtime", 2)
end

return Admin
