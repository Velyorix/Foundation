-- Foundation's own commands, under the reserved "foundation" root, each behind a
-- foundation.command.* permission (operators by default; the console has every permission).
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

local function requirement_text(messages, requirement)
	local version = requirement.version or messages:Format("service.any_version")
	if requirement.satisfied then
		return messages:Format("admin.service_requirement", { package = requirement.package, version = version })
	end
	return messages:Format("admin.service_requirement_missing", { package = requirement.package, version = version })
end

local function join(messages, items, format)
	local parts = {}
	for index, item in ipairs(items) do
		parts[index] = format(messages, item)
	end
	return table.concat(parts, ", ")
end

local function services(runtime, sender)
	local messages = runtime.messages
	local graph = runtime.services:Graph()
	local capabilities = runtime.capabilities:Snapshot().capabilities
	local capability_names = {}
	for name in pairs(capabilities) do
		capability_names[#capability_names + 1] = name
	end
	table.sort(capability_names)
	if #graph == 0 and #capability_names == 0 then
		sender:Reply(messages:Format("admin.services_none"))
		return
	end
	sender:Reply(messages:Format("admin.services_header", { count = #graph }))
	for _, node in ipairs(graph) do
		sender:Reply(node.key)
		if #node.providers == 0 then
			sender:Reply("  " .. messages:Format("admin.service_no_provider"))
		else
			sender:Reply("  " .. messages:Format("admin.service_providers", {
				providers = join(messages, node.providers, function(m, provider)
					return m:Format("admin.service_provider", provider)
				end),
			}))
		end
		if #node.required > 0 then
			sender:Reply("  " .. messages:Format("admin.service_required", {
				packages = join(messages, node.required, requirement_text),
			}))
		end
		if #node.optional > 0 then
			sender:Reply("  " .. messages:Format("admin.service_optional", {
				packages = join(messages, node.optional, requirement_text),
			}))
		end
	end
	sender:Reply(messages:Format("admin.capabilities_header", { count = #capability_names }))
	for _, name in ipairs(capability_names) do
		sender:Reply("  " .. messages:Format("admin.capability_line", {
			name = name,
			packages = join(messages, capabilities[name], function(_, item)
				return item.version and (item.package .. " " .. item.version) or item.package
			end),
		}))
	end
end

local function actor_of(sender)
	if sender:IsConsole() then
		return "console"
	end
	return "player:" .. tostring(sender:GetId())
end

local function operators_or_reply(runtime, sender)
	if not runtime.operators then
		sender:Reply(runtime.messages:Format("admin.operators_unavailable"))
		return nil
	end
	return runtime.operators
end

local function op_add(runtime, sender, args)
	local operators = operators_or_reply(runtime, sender)
	if not operators then
		return
	end
	local ok, reason = operators:Add(args.account, args.name, actor_of(sender))
	if ok then
		sender:Reply(runtime.messages:Format("admin.op_added", { account = args.account }))
	else
		sender:Reply(runtime.messages:Format(reason))
	end
end

local function op_remove(runtime, sender, args)
	local operators = operators_or_reply(runtime, sender)
	if not operators then
		return
	end
	local ok, reason = operators:Remove(args.account, actor_of(sender))
	if ok then
		sender:Reply(runtime.messages:Format("admin.op_removed", { account = args.account }))
	else
		sender:Reply(runtime.messages:Format(reason))
	end
end

local function op_list(runtime, sender)
	local operators = operators_or_reply(runtime, sender)
	if not operators then
		return
	end
	local messages = runtime.messages
	local list = operators:List()
	if #list == 0 then
		sender:Reply(messages:Format("admin.op_none"))
		return
	end
	sender:Reply(messages:Format("admin.op_header", { count = #list }))
	for _, entry in ipairs(list) do
		local key = entry.name and "admin.op_line_named" or "admin.op_line"
		sender:Reply("  " .. messages:Format(key, { account = entry.id, name = entry.name, by = entry.added_by }))
	end
end

local function permission_check(runtime, sender, args)
	local messages = runtime.messages
	local permissions = runtime.permissions
	local result = permissions:Explain(args.account, args.node)
	local node = args.node:lower()
	local source = messages:Format("admin.source." .. result.source, { package = result.package })
	sender:Reply(messages:Format(result.allowed and "admin.permission_allowed" or "admin.permission_denied", {
		node = node,
		account = args.account,
		source = source,
	}))
	local declaration = permissions:Get(node)
	if declaration then
		sender:Reply("  " .. messages:Format("admin.permission_declared", {
			owner = declaration.owner,
			default = declaration.default,
		}))
		if declaration.description then
			sender:Reply("  " .. declaration.description)
		end
	else
		sender:Reply("  " .. messages:Format("admin.permission_undeclared"))
	end
end

local function permission_list(runtime, sender, args)
	local messages = runtime.messages
	local list = runtime.permissions:List(args.package)
	if #list == 0 then
		sender:Reply(messages:Format("admin.permissions_none"))
		return
	end
	sender:Reply(messages:Format("admin.permissions_header", { count = #list }))
	for _, declaration in ipairs(list) do
		local line = declaration.node .. " (" .. declaration.default .. ")"
		if declaration.description then
			line = line .. " - " .. declaration.description
		end
		sender:Reply("  " .. line)
	end
end

-- Permissions of Foundation's own commands; the console has them all.
Admin.PERMISSIONS = {
	{ node = "foundation.command.version", default = "everyone" },
	{ node = "foundation.command.help", default = "everyone" },
	{ node = "foundation.command.packages", default = "operators" },
	{ node = "foundation.command.services", default = "operators" },
	{ node = "foundation.command.reload-config", default = "operators" },
	{ node = "foundation.command.op", default = "operators" },
	{ node = "foundation.command.permissions", default = "operators" },
}

function Admin.Register(runtime)
	local function bind(fn)
		return function(sender, args)
			fn(runtime, sender, args)
		end
	end
	for _, item in ipairs(Admin.PERMISSIONS) do
		local key = "admin.permission." .. item.node:match("^foundation%.command%.(.+)$"):gsub("-", "_")
		runtime.permissions:Declare("foundation", item.node, {
			default = item.default,
			description = runtime.messages:Format(key),
		}, "Runtime", 2)
	end
	runtime.commands:Register("foundation", {
		name = "foundation",
		description_key = "admin.description.root",
		subcommands = {
			{
				name = "version",
				description_key = "admin.description.version",
				permission = "foundation.command.version",
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
				permission = "foundation.command.help",
				arguments = { { name = "command", type = "greedy", optional = true } },
				run = bind(help),
			},
			{
				name = "packages",
				description_key = "admin.description.packages",
				permission = "foundation.command.packages",
				run = bind(packages),
			},
			{
				name = "services",
				description_key = "admin.description.services",
				permission = "foundation.command.services",
				run = bind(services),
			},
			{
				name = "reload-config",
				description_key = "admin.description.reload_config",
				permission = "foundation.command.reload-config",
				audit = true,
				run = bind(reload_config),
			},
			{
				name = "op",
				description_key = "admin.description.op",
				permission = "foundation.command.op",
				subcommands = {
					{
						name = "add",
						audit = true,
						arguments = { { name = "account" }, { name = "name", type = "greedy", optional = true } },
						run = bind(op_add),
					},
					{
						name = "remove",
						audit = true,
						arguments = { { name = "account" } },
						run = bind(op_remove),
					},
					{ name = "list", run = bind(op_list) },
				},
			},
			{
				name = "permissions",
				description_key = "admin.description.permissions",
				permission = "foundation.command.permissions",
				subcommands = {
					{
						name = "check",
						arguments = { { name = "account" }, { name = "node" } },
						run = bind(permission_check),
					},
					{
						name = "list",
						arguments = { { name = "package", optional = true } },
						run = bind(permission_list),
					},
				},
			},
		},
	}, "Runtime", 2)
end

return Admin
