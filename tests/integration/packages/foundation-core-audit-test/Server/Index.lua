local Messages = Package.Require("foundation/Shared/foundation/core/messages.lua")
local Errors = Package.Require("foundation/Shared/foundation/core/errors.lua")
local Check = Package.Require("foundation/Shared/foundation/core/check.lua")
local Log = Package.Require("foundation/Shared/foundation/core/log.lua")
local Audit = Package.Require("foundation/Server/foundation/core/audit.lua")
local Files = Package.Require("foundation/Server/foundation/core/files.lua")
local Json = Package.Require("foundation/Shared/foundation/core/json.lua")
local Sensitive = Package.Require("foundation/Shared/foundation/core/sensitive.lua")
local en = Package.Require("foundation/Shared/foundation/locales/en/core.lua")

local suite = FoundationTest.Suite("core-audit")

local messages = Messages.new({ en = en })
local check = Check.new(Errors.new(messages))
local log = Log.new({
	sink = Log.console_sink(Console),
	messages = messages,
	clock = function()
		return Server.GetTime() / 1000
	end,
})
local engine_files = Files.new({
	Open = function(path, truncate)
		return File(path, truncate)
	end,
	Exists = File.Exists,
	CreateDirectory = File.CreateDirectory,
	IsDirectory = File.IsDirectory,
	Rename = File.Rename,
})

local function new_audit(directory)
	return Audit.new({
		files = engine_files,
		json = Json,
		sensitive = Sensitive,
		now = function()
			return math.floor(Server.GetTime() / 1000)
		end,
		check = check,
		log = log,
		directory = directory,
	})
end

local function read_lines(path)
	local file = File(path)
	local content = file:Read(0)
	file:Close()
	local lines = {}
	for line in content:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	return lines
end

suite:Test("creates the directory and appends JSON lines", function()
	local audit = new_audit("foundation/audit-test")
	FoundationTest.True(audit:Record("foundation", "foundation:first", { actor = "console" }))
	FoundationTest.True(audit:Record("foundation", "foundation:second", { details = { password = "x1234" } }))
	local path = audit:PathFor(math.floor(Server.GetTime() / 1000))
	FoundationTest.True(File.IsDirectory("foundation/audit-test"), "directory not created")
	local lines = read_lines(path)
	FoundationTest.Equal(#lines, 2)
	FoundationTest.Equal(JSON.parse(lines[1]).action, "foundation:first")
	FoundationTest.Equal(JSON.parse(lines[2]).details.password, "***")
end)

suite:Test("keeps existing content", function()
	local audit = new_audit("foundation/audit-test")
	audit:Record("foundation", "foundation:third")
	local lines = read_lines(audit:PathFor(math.floor(Server.GetTime() / 1000)))
	FoundationTest.Equal(#lines, 3)
	FoundationTest.Equal(JSON.parse(lines[1]).action, "foundation:first")
	FoundationTest.Equal(JSON.parse(lines[3]).action, "foundation:third")
end)

suite:Test("falls back to the log when the directory cannot be created", function()
	local blocker = File("foundation/blocked.txt", true)
	blocker:Write("not a directory")
	blocker:Close()
	local audit = new_audit("foundation/blocked.txt")
	local ok, err = audit:Record("foundation", "foundation:fallback_marker")
	FoundationTest.Equal(ok, nil)
	FoundationTest.Equal(err.code, "audit_write_failed")
	FoundationTest.Equal(audit:Snapshot().failed, 1)
end)

suite:Run()
