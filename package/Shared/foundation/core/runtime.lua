local Messages = Package.Require("messages.lua")
local Errors = Package.Require("errors.lua")
local Check = Package.Require("check.lua")
local Log = Package.Require("log.lua")
local Invoker = Package.Require("invoke.lua")
local Ownership = Package.Require("ownership.lua")
local Registry = Package.Require("packages.lua")
local Keys = Package.Require("keys.lua")
local Schema = Package.Require("schema.lua")
local I18n = Package.Require("i18n.lua")
local Scheduler = Package.Require("scheduler.lua")
local Futures = Package.Require("future.lua")
local Events = Package.Require("events.lua")
local Services = Package.Require("services.lua")
local Capabilities = Package.Require("capabilities.lua")
local Commands = Package.Require("commands.lua")
local Arguments = Package.Require("arguments.lua")
local Admin = Package.Require("admin_commands.lua")

local Runtime = {}
Runtime.__index = Runtime

-- env: side, version, api_version, catalogs, sink, clock, now, and optionally
-- create_audit(runtime) on sides that can write files.
function Runtime.new(env)
	local messages = Messages.new(env.catalogs, env.locale or "en")
	local errors = Errors.new(messages)
	return setmetatable({
		env = env,
		messages = messages,
		errors = errors,
		check = Check.new(errors),
		keys = Keys.new(errors),
		state = "created",
		components = {},
	}, Runtime)
end

local COMPONENTS = {
	{
		name = "log",
		required = true,
		create = function(runtime)
			local env = runtime.env
			runtime.log = Log.new({ sink = env.sink, messages = runtime.messages, clock = env.clock })
		end,
	},
	{
		name = "invoker",
		required = true,
		create = function(runtime)
			runtime.invoker = Invoker.new({ log = runtime.log, side = runtime.env.side })
		end,
	},
	{
		name = "schema",
		required = true,
		create = function(runtime)
			runtime.schema = Schema.new({
				errors = runtime.errors,
				check = runtime.check,
				keys = runtime.keys,
				invoker = runtime.invoker,
			})
		end,
	},
	{
		name = "ownership",
		required = true,
		create = function(runtime)
			runtime.ownership = Ownership.new({ check = runtime.check, invoker = runtime.invoker })
		end,
	},
	{
		name = "packages",
		required = true,
		create = function(runtime)
			runtime.packages = Registry.new({
				check = runtime.check,
				log = runtime.log,
				ownership = runtime.ownership,
				invoker = runtime.invoker,
				api_version = runtime.env.api_version,
			})
		end,
	},
	{
		name = "i18n",
		required = true,
		create = function(runtime)
			local i18n = I18n.new({ check = runtime.check, log = runtime.log, messages = runtime.messages })
			runtime.i18n = i18n
			runtime.packages:ExtendContext("RegisterCatalog", function(context, entry, locale, entries)
				local release = i18n:Register(entry.id, locale, entries, "context:RegisterCatalog", 3)
				context:Track("catalog", release, { locale = locale })
			end)
			runtime.packages:ExtendContext("Translate", function(_, entry, key, params, locale)
				local text = i18n:Translate(entry.id, key, params, locale, "context:Translate", 3)
				return text
			end)
		end,
	},
	{
		name = "scheduler",
		required = false,
		create = function(runtime)
			local env = runtime.env
			if not env.timer then
				return "absent"
			end
			local scheduler = Scheduler.new({
				timer = env.timer,
				now_ms = env.now_ms,
				invoker = runtime.invoker,
				ownership = runtime.ownership,
				check = runtime.check,
				log = runtime.log,
			})
			runtime.scheduler = scheduler
			local packages = runtime.packages
			packages:ExtendContext("NextTick", function(_, entry, fn)
				local task = scheduler:NextTick(entry.id, fn, "context:NextTick", 3)
				return task
			end)
			packages:ExtendContext("Delay", function(_, entry, milliseconds, fn)
				local task = scheduler:Delay(entry.id, milliseconds, fn, "context:Delay", 3)
				return task
			end)
			packages:ExtendContext("Repeat", function(_, entry, milliseconds, fn, options)
				local task = scheduler:Repeat(entry.id, milliseconds, fn, options, "context:Repeat", 3)
				return task
			end)
			packages:ExtendContext("Debounce", function(_, entry, milliseconds, fn)
				local debounced = scheduler:Debounce(entry.id, milliseconds, fn, "context:Debounce", 3)
				return debounced
			end)
			packages:ExtendContext("Throttle", function(_, entry, milliseconds, fn)
				local throttled = scheduler:Throttle(entry.id, milliseconds, fn, "context:Throttle", 3)
				return throttled
			end)
		end,
	},
	{
		name = "future",
		required = true,
		create = function(runtime)
			local futures = Futures.new({
				invoker = runtime.invoker,
				ownership = runtime.ownership,
				scheduler = runtime.scheduler,
				check = runtime.check,
			})
			runtime.futures = futures
			runtime.packages:ExtendContext("Future", function(_, entry, executor)
				local future = futures:New(entry.id, executor, "context:Future", 3)
				return future
			end)
			runtime.packages:ExtendContext("All", function(_, entry, list)
				local future = futures:All(entry.id, list, "context:All", 3)
				return future
			end)
		end,
	},
	{
		name = "events",
		required = true,
		create = function(runtime)
			local events = Events.new({
				check = runtime.check,
				keys = runtime.keys,
				schema = runtime.schema,
				invoker = runtime.invoker,
				ownership = runtime.ownership,
			})
			runtime.events = events
			local packages = runtime.packages
			local S = runtime.schema
			local package_fields = { package = S:String(), version = S:Optional(S:String()) }
			events:Define("foundation", "package_ready", { fields = package_fields }, "Runtime", 2)
			events:Define("foundation", "package_failed", {
				fields = { package = S:String(), version = S:Optional(S:String()), message = S:String() },
			}, "Runtime", 2)
			events:Define("foundation", "package_disabled", {
				fields = {
					package = S:String(),
					version = S:Optional(S:String()),
					reason = S:Enum({ "unload", "dependency_disabled", "dependency_failed", "foundation_stopping" }),
				},
			}, "Runtime", 2)
			events:Define("foundation", "config_reloaded", {
				fields = {
					package = S:String(),
					path = S:String(),
					changed = S:List(S:String()),
					pending = S:List(S:String()),
				},
			}, "Runtime", 2)
			packages:Observe(function(kind, entry, details)
				events:Emit("foundation", "package_" .. kind, {
					package = entry.id,
					version = entry.version,
					message = details and kind == "failed" and details.reason or nil,
					reason = details and kind == "disabled" and details.reason or nil,
				}, "Runtime", 2)
			end)
			packages:ExtendContext("DefineEvent", function(context, entry, name, definition)
				local key, release = events:Define(entry.id, name, definition, "context:DefineEvent", 3)
				context:Track("event", release, { event = key })
				return key
			end)
			packages:ExtendContext("Listen", function(_, entry, name, fn, options)
				local handle = events:Listen(entry.id, name, fn, options, "context:Listen", 3)
				return handle
			end)
			packages:ExtendContext("Emit", function(_, entry, name, payload)
				local event = events:Emit(entry.id, name, payload, "context:Emit", 3)
				return event
			end)
		end,
	},
	{
		name = "services",
		required = true,
		create = function(runtime)
			local services = Services.new({
				check = runtime.check,
				keys = runtime.keys,
				ownership = runtime.ownership,
				invoker = runtime.invoker,
				events = runtime.events,
				packages = runtime.packages,
			})
			runtime.services = services
			runtime.packages:ExtendManifest("services", function(value, api, level)
				return services:CheckManifest(value, api, level)
			end)
			runtime.packages:AddReadyCheck(function(entry)
				return services:ReadyCheck(entry)
			end)
			local packages = runtime.packages
			local S = runtime.schema
			local fields = {
				service = S:String(),
				provider = S:String(),
				version = S:String(),
				priority = S:Integer(),
			}
			runtime.events:Define("foundation", "service_available", { fields = fields }, "Runtime", 2)
			runtime.events:Define("foundation", "service_unavailable", { fields = fields }, "Runtime", 2)
			packages:ExtendContext("OnService", function(_, entry, name, version, fn)
				local handle = services:Watch(entry.id, name, version, fn, "context:OnService", 3)
				return handle
			end)
			packages:ExtendContext("ProvideService", function(_, entry, name, version, implementation, options)
				local provider =
					services:Provide(entry.id, name, version, implementation, options, "context:ProvideService", 3)
				return provider.handle
			end)
			packages:ExtendContext("GetService", function(_, entry, name, version)
				local service, info = services:Get(entry.id, name, version, "context:GetService", 3)
				return service, info
			end)
			packages:ExtendContext("GetServices", function(_, entry, name, version)
				local list = services:All(entry.id, name, version, "context:GetServices", 3)
				return list
			end)
		end,
	},
	{
		name = "capabilities",
		required = true,
		create = function(runtime)
			local capabilities = Capabilities.new({
				check = runtime.check,
				keys = runtime.keys,
				log = runtime.log,
				events = runtime.events,
				services = runtime.services,
			})
			runtime.capabilities = capabilities
			local S = runtime.schema
			local fields = { capability = S:String(), package = S:String(), version = S:Optional(S:String()) }
			runtime.events:Define("foundation", "capability_available", { fields = fields }, "Runtime", 2)
			runtime.events:Define("foundation", "capability_unavailable", { fields = fields }, "Runtime", 2)
			runtime.packages:ExtendManifest("capabilities", function(value, api, level)
				return capabilities:CheckManifest(value, api, level)
			end)
			runtime.packages:Observe(function(kind, entry)
				capabilities:Observe(kind, entry)
			end)
		end,
	},
	{
		name = "commands",
		required = true,
		create = function(runtime)
			local arguments = Arguments.new({
				check = runtime.check,
				keys = runtime.keys,
				invoker = runtime.invoker,
				log = runtime.log,
			})
			local env = runtime.env
			local commands = Commands.new({
				check = runtime.check,
				log = runtime.log,
				arguments = arguments,
				invoker = runtime.invoker,
				events = runtime.events,
				i18n = runtime.i18n,
				now_ms = env.now_ms or function()
					return math.floor(env.clock() * 1000)
				end,
				audit = function()
					return runtime.audit
				end,
			})
			local S = runtime.schema
			local command_fields = {
				command = S:String(),
				owner = S:String(),
				sender = S:Enum({ "console", "player" }),
				name = S:String(),
				arguments = S:Any(),
			}
			runtime.events:Define(
				"foundation",
				"command",
				{ fields = command_fields, cancellable = true },
				"Runtime",
				2
			)
			local completed_fields = { outcome = S:Enum({ "success", "failure" }) }
			for field, schema in pairs(command_fields) do
				completed_fields[field] = schema
			end
			runtime.events:Define("foundation", "command_completed", { fields = completed_fields }, "Runtime", 2)
			runtime.commands = commands
			runtime.arguments = arguments
			runtime.packages:ExtendContext("RegisterArgumentType", function(context, entry, name, definition)
				local key, release =
					arguments:RegisterType(entry.id, name, definition, "context:RegisterArgumentType", 3)
				context:Track("argument_type", release, { type = key })
				return key
			end)
			runtime.packages:ExtendContext("RegisterCommand", function(context, entry, spec)
				local root, release = commands:Register(entry.id, spec, "context:RegisterCommand", 3)
				local handle = context:Track("command", release, { command = root.name })
				return handle
			end)
			Admin.Register(runtime)
		end,
	},
	{
		name = "config",
		required = false,
		create = function(runtime)
			if not runtime.env.create_config then
				return "absent"
			end
			runtime.config = runtime.env.create_config(runtime)
			runtime:ApplySettings(runtime.config:Load())
		end,
	},
	{
		name = "package_config",
		required = false,
		create = function(runtime)
			if not runtime.env.create_package_configs then
				return "absent"
			end
			local configs = runtime.env.create_package_configs(runtime)
			runtime.package_configs = configs
			runtime.packages:ExtendContext("Config", function(context, entry, spec)
				local settings, release = configs:Create(entry.id, entry.name, spec, "context:Config", 3)
				context:Track("config", release)
				return settings
			end)
		end,
	},
	{
		name = "command_bridges",
		required = false,
		create = function(runtime)
			if not runtime.env.create_command_bridges then
				return "absent"
			end
			local bridges = runtime.env.create_command_bridges(runtime)
			runtime.command_bridges = bridges
			runtime.commands:OnLabelsChanged(function()
				bridges:Sync()
			end)
			bridges:Start()
		end,
	},
	{
		name = "audit",
		required = false,
		create = function(runtime)
			if not runtime.env.create_audit then
				return "absent"
			end
			runtime.audit = runtime.env.create_audit(runtime)
		end,
	},
}

function Runtime:Start()
	if self.state ~= "created" then
		self.errors:Raise("invalid_state", {
			api = "Runtime:Start",
			reason = self.messages:Format("reason.runtime_already_started"),
		})
	end
	self.state = "starting"
	for _, component in ipairs(COMPONENTS) do
		local ok, result = xpcall(component.create, debug.traceback, self)
		if ok and result == "absent" then
			self.components[#self.components + 1] = { name = component.name, required = false, state = "absent" }
		elseif ok then
			self.components[#self.components + 1] =
				{ name = component.name, required = component.required, state = "running" }
		elseif component.required then
			self.components[#self.components + 1] = { name = component.name, required = true, state = "failed" }
			self.state = "failed"
			self.failure =
				self.messages:Format("runtime.component_failed", { component = component.name, reason = result })
			if self.log then
				self.log:Error("runtime.component_failed", { component = component.name, reason = result })
			else
				self.env.sink("error", self.failure)
			end
			return false
		else
			self.components[#self.components + 1] = { name = component.name, required = false, state = "unavailable" }
			self.log:Warning("runtime.optional_unavailable", { component = component.name, reason = result })
		end
	end
	self.state = "running"
	self.started_at = self.env.now()
	self.log:Info("runtime.started", { version = self.env.version, api = self.env.api_version, side = self.env.side })
	return true
end

function Runtime:ApplySettings(values)
	self.settings = values
	self.i18n:SetServerLocale(values.language)
	self.log:SetLevel(values.log.level)
	self.log:SetDebugCategories(values.log.debug_categories)
end

-- Reloads Foundation's file and every package file independently. Report:
-- { core = { changed, pending } | { error } | nil, packages = { [owner] = ... } }
function Runtime:ReloadConfig()
	local report = { packages = {} }
	if self.config then
		local changed, pending = self.config:Reload()
		if changed then
			self:ApplySettings(self.config:Values())
			report.core = { changed = changed, pending = pending, path = self.config.spec.path }
		else
			report.core = { error = pending, path = self.config.spec.path }
		end
	end
	if self.package_configs then
		report.packages = self.package_configs:ReloadAll()
	end
	self:announce_reload("foundation", report.core)
	for _, owner in ipairs(self.package_configs and self.package_configs.order or {}) do
		self:announce_reload(owner, report.packages[owner])
	end
	return report
end

function Runtime:announce_reload(owner, result)
	if not result or result.error or not self.events then
		return
	end
	self.invoker:Call({ owner = "foundation", kind = "config_event" }, function()
		self.events:Emit("foundation", "config_reloaded", {
			package = owner,
			path = result.path,
			changed = result.changed,
			pending = result.pending,
		}, "Runtime:ReloadConfig", 2)
	end)
end

function Runtime:IsRunning()
	return self.state == "running"
end

-- `level` as for error(), seen from the public function calling it (default 2).
function Runtime:RequireRunning(api, level)
	if self.state ~= "running" then
		self.errors:Raise("invalid_state", {
			api = api,
			reason = self.failure or self.messages:Format("reason.runtime_not_running", { state = self.state }),
		}, (level or 2) + 1)
	end
end

function Runtime:ActivePackages()
	local ids = {}
	if self.packages then
		for _, entry in ipairs(self.packages:Snapshot().packages) do
			if entry.state == "initializing" or entry.state == "ready" then
				ids[#ids + 1] = entry.id
			end
		end
	end
	return ids
end

function Runtime:Stop()
	if self.state ~= "running" and self.state ~= "failed" then
		return false
	end
	self.state = "stopping"
	if self.packages then
		self.packages:Shutdown()
	end
	if self.ownership then
		self.ownership:ReleaseOwner("foundation", true)
	end
	if self.log then
		self.log:Info("runtime.stopped")
		self.log:Flush()
	end
	self.state = "stopped"
	return true
end

function Runtime:Snapshot()
	local components = {}
	for index, component in ipairs(self.components) do
		components[index] = { name = component.name, required = component.required, state = component.state }
	end
	return {
		version = self.env.version,
		api_version = self.env.api_version,
		side = self.env.side,
		state = self.state,
		failure = self.failure,
		started_at = self.started_at,
		components = components,
		packages = self.packages and self.packages:Snapshot().packages or {},
		resources = self.ownership and self.ownership:Snapshot() or nil,
		callbacks = self.invoker and self.invoker:Snapshot() or nil,
		audit = self.audit and self.audit:Snapshot() or nil,
		config = self.config and self.config:Snapshot() or nil,
		package_configs = self.package_configs and self.package_configs:Snapshot() or nil,
		scheduler = self.scheduler and self.scheduler:Snapshot() or nil,
		locale = self.i18n and self.i18n:GetServerLocale() or nil,
	}
end

return Runtime
