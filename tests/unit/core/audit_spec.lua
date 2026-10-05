local function memory_files()
	local fs = { contents = {}, directories = {}, fail_open = false, not_good = false, fail_mkdir = false }

	function fs.Open(path, truncate)
		if fs.fail_open then
			error("File extension not allowed")
		end
		if truncate or fs.contents[path] == nil then
			fs.contents[path] = ""
		end
		local position = 0
		return {
			IsGood = function()
				return not fs.not_good
			end,
			Size = function()
				return #fs.contents[path]
			end,
			Seek = function(_, at)
				position = at
			end,
			Write = function(_, data)
				local content = fs.contents[path]
				fs.contents[path] = content:sub(1, position) .. data .. content:sub(position + #data + 1)
				position = position + #data
			end,
			Flush = function() end,
			HasFailed = function()
				return false
			end,
			Close = function() end,
		}
	end

	function fs.Exists(path)
		return fs.contents[path] ~= nil or fs.directories[path] ~= nil
	end

	function fs.CreateDirectory(path)
		if fs.fail_mkdir == "raise" then
			error("create_directories: Cannot create a file when that file already exists.")
		elseif fs.fail_mkdir then
			return false
		end
		fs.directories[path] = true
		return true
	end

	function fs.IsDirectory(path)
		return fs.directories[path] == true
	end

	return fs
end

local function setup()
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Check = loader:require("foundation/core/check.lua")
	local Log = loader:require("foundation/core/log.lua")
	local Audit = loader:require("foundation/core/audit.lua")
	local messages = Messages.new({ en = loader:require("foundation/locales/en/core.lua") })
	local state = { now = 1759679465, lines = {} }
	local errors = Errors.new(messages)
	local log = Log.new({
		sink = function(level, line)
			state.lines[#state.lines + 1] = { level = level, line = line }
		end,
		messages = messages,
		clock = function()
			return 0
		end,
	})
	local files = memory_files()
	local audit = Audit.new({
		files = files,
		now = function()
			return state.now
		end,
		check = Check.new(errors),
		log = log,
	})
	return audit, files, state, Errors
end

local function lines_of(text)
	local lines = {}
	for line in text:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	return lines
end

describe("Audit", function()
	it("appends one JSON line per record to the daily file", function()
		local audit, files = setup()
		expect.truthy(audit:Record("foundation", "foundation:operator_added", { actor = "console", target = "acc-1" }))
		expect.truthy(audit:Record("foundation", "foundation:config_reloaded"))
		local path = "foundation/audit/audit-2025-10-05.log"
		local lines = lines_of(files.contents[path])
		expect.equal(#lines, 2)
		expect.equal(
			lines[1],
			'{"action":"foundation:operator_added","actor":"console","outcome":"success","owner":"foundation",'
				.. '"target":"acc-1","time":"2025-10-05T15:51:05Z"}'
		)
		expect.contains(lines[2], '"action":"foundation:config_reloaded"')
	end)

	it("keeps existing content when appending", function()
		local audit, files = setup()
		local path = "foundation/audit/audit-2025-10-05.log"
		files.directories["foundation/audit"] = true
		files.contents[path] = '{"previous":true}\n'
		audit:Record("foundation", "foundation:x")
		local lines = lines_of(files.contents[path])
		expect.equal(lines[1], '{"previous":true}')
		expect.equal(#lines, 2)
	end)

	it("rotates files by UTC day", function()
		local audit, files, state = setup()
		audit:Record("foundation", "foundation:a")
		state.now = state.now + 86400
		audit:Record("foundation", "foundation:b")
		expect.truthy(files.contents["foundation/audit/audit-2025-10-05.log"])
		expect.truthy(files.contents["foundation/audit/audit-2025-10-06.log"])
	end)

	it("masks sensitive fields in details", function()
		local audit, files = setup()
		audit:Record("my-package", "my-package:login", { details = { user = "ana", password = "hunter22" } })
		local content = files.contents["foundation/audit/audit-2025-10-05.log"]
		expect.contains(content, '"details":{"password":"***","user":"ana"}')
		expect.falsy(content:find("hunter22", 1, true))
	end)

	it("records the outcome", function()
		local audit, files = setup()
		audit:Record("foundation", "foundation:command", { outcome = "denied" })
		expect.contains(files.contents["foundation/audit/audit-2025-10-05.log"], '"outcome":"denied"')
		expect.raises(function()
			audit:Record("foundation", "foundation:command", { outcome = "maybe" })
		end, "expected one of success, denied, failure")
	end)

	it("only accepts actions in the owner's namespace", function()
		local audit = setup()
		expect.raises(function()
			audit:Record("my-package", "foundation:operator_added")
		end, "with the namespace 'my-package'")
		expect.raises(function()
			audit:Record("my-package", "Bad Action")
		end, "[foundation:invalid_value]")
		expect.raises(function()
			audit:Record("my-package", "my-package:")
		end, "[foundation:invalid_value]")
	end)

	it("validates entry fields", function()
		local audit = setup()
		expect.raises(function()
			audit:Record("foundation", "foundation:x", { actor = 5 })
		end, "'entry.actor' must be string? (got number)")
		expect.raises(function()
			audit:Record("foundation", "foundation:x", { details = { fn = print } })
		end, "$.details.fn has unsupported type function")
	end)

	describe("when writing fails", function()
		local function assert_fallback(prepare)
			local audit, files, state, Errors = setup()
			prepare(files)
			local ok, err = audit:Record("foundation", "foundation:operator_added", { actor = "console" })
			expect.is_nil(ok)
			expect.truthy(Errors.Is(err))
			expect.equal(err.code, "audit_write_failed")
			expect.equal(err.category, "infrastructure")
			local logged = state.lines[#state.lines]
			expect.equal(logged.level, "error")
			expect.contains(logged.line, "audit record could not be written to foundation/audit/audit-2025-10-05.log")
			expect.contains(logged.line, "foundation:operator_added")
			local snapshot = audit:Snapshot()
			expect.equal(snapshot.failed, 1)
			expect.equal(snapshot.written, 0)
			expect.equal(snapshot.last_failure.path, "foundation/audit/audit-2025-10-05.log")
		end

		it("logs the record when the file cannot be opened", function()
			assert_fallback(function(files)
				files.fail_open = true
			end)
		end)

		it("logs the record when the file is not usable", function()
			assert_fallback(function(files)
				files.not_good = true
			end)
		end)

		it("logs the record when the directory cannot be created", function()
			assert_fallback(function(files)
				files.fail_mkdir = true
			end)
		end)

		it("logs the record when creating the directory raises", function()
			assert_fallback(function(files)
				files.fail_mkdir = "raise"
			end)
		end)
	end)

	it("counts written records", function()
		local audit = setup()
		audit:Record("foundation", "foundation:a")
		audit:Record("foundation", "foundation:b")
		expect.equal(audit:Snapshot().written, 2)
	end)
end)
