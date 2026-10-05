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
	self.i18n:SetServerLocale(values.language)
	self.log:SetLevel(values.log.level)
	self.log:SetDebugCategories(values.log.debug_categories)
end

-- Returns the changed and restart-pending setting paths, or nil and an error.
function Runtime:ReloadConfig()
	if not self.config then
		return nil,
			self.errors:New("invalid_state", {
				api = "Runtime:ReloadConfig",
				reason = self.messages:Format("reason.config_absent"),
			})
	end
	local changed, pending = self.config:Reload()
	if changed then
		self:ApplySettings(self.config:Values())
	end
	return changed, pending
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
		locale = self.i18n and self.i18n:GetServerLocale() or nil,
	}
end

return Runtime
