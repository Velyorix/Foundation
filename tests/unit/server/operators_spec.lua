local function memory_files()
	local raw = { contents = {}, directories = {}, fail_rename = false }
	function raw.Open(path, truncate)
		if truncate or raw.contents[path] == nil then
			raw.contents[path] = ""
		end
		return {
			Read = function()
				return raw.contents[path]
			end,
			Write = function(_, data)
				raw.contents[path] = raw.contents[path] .. data
			end,
			Flush = function() end,
			HasFailed = function()
				return false
			end,
			Close = function() end,
		}
	end
	function raw.Exists(path)
		return raw.contents[path] ~= nil
	end
	function raw.CreateDirectory(path)
		raw.directories[path] = true
		return true
	end
	function raw.IsDirectory(path)
		return raw.directories[path] == true
	end
	function raw.Rename(from, to)
		if raw.fail_rename then
			return false
		end
		raw.contents[to] = raw.contents[from]
		raw.contents[from] = nil
		return true
	end
	return raw
end

local PATH = "foundation/operators.json"

local function setup(initial)
	local loader = Loader.new({ side = "Server" })
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Facade = loader:require("foundation/core/facade.lua")
	local Files = loader:require("foundation/core/files.lua")
	local Json = loader:require("foundation/core/json.lua")
	local Operators = loader:require("foundation/core/operators.lua")
	local Senders = loader:require("foundation/core/senders.lua")
	local raw = memory_files()
	raw.contents[PATH] = initial
	local state = { lines = {}, audited = {}, now = 1760100000 }
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(_, line)
			state.lines[#state.lines + 1] = line
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
		create_operators = function(rt)
			return Operators.new({
				files = Files.new(raw),
				json = Json,
				messages = rt.messages,
				log = rt.log:For("foundation", "operators"),
				now = function()
					return state.now
				end,
				audit = function()
					return rt.audit
				end,
				announce = function(name, payload)
					rt.events:Emit("foundation", name, payload, "Operators", 2)
				end,
			})
		end,
		create_audit = function()
			return {
				Record = function(_, owner, action, entry)
					state.audited[#state.audited + 1] = { owner = owner, action = action, entry = entry }
					return true
				end,
			}
		end,
	})
	runtime:Start()
	return runtime, Facade.new(runtime), raw, state, Senders
end

local function text(lines)
	return table.concat(lines, "\n")
end

describe("Operators", function()
	it("start empty without a file and write one on the first change", function()
		local runtime, Foundation, raw = setup(nil)
		expect.same(Foundation.Operators.List(), {})
		expect.truthy(runtime.operators:Add("76561198000000001", "Sam O'Neil", "console"))
		expect.equal(
			raw.contents[PATH],
			'{"operators":{"76561198000000001":{"added_at":1760100000,"added_by":"console","name":"Sam O\'Neil"}},"version":1}\n'
		)
	end)

	it("load an existing file and survive a restart", function()
		local runtime, _, raw = setup(nil)
		runtime.operators:Add("alex-id", "Alex", "console")
		runtime.operators:Add("sam-id", nil, "player:alex-id")
		local again, Foundation = setup(raw.contents[PATH])
		expect.truthy(again.operators:IsOperator("alex-id"))
		expect.same(Foundation.Operators.List(), {
			{ id = "alex-id", name = "Alex", added_by = "console", added_at = 1760100000 },
			{ id = "sam-id", added_by = "player:alex-id", added_at = 1760100000 },
		})
	end)

	it("feed the operators default of permissions", function()
		local runtime, Foundation, _, _, Senders = setup(nil)
		local homes = runtime.packages:Register({
			GetName = function()
				return "homes"
			end,
			Subscribe = function() end,
		}, { api = "0.1" })
		homes:DeclarePermission("homes.admin")
		expect.falsy(Foundation.Permissions.Has("alex-id", "homes.admin"))
		runtime.operators:Add("alex-id", "Alex", "console")
		expect.truthy(Foundation.Permissions.Has("alex-id", "homes.admin"))
		expect.truthy(Foundation.Operators.IsOperator("alex-id"))
		expect.truthy(Foundation.Operators.IsOperator(Senders.new({ kind = "console", reply = print })))
		runtime.operators:Remove("alex-id", "console")
		expect.falsy(Foundation.Permissions.Has("alex-id", "homes.admin"))
	end)

	it("audit, log and announce every change", function()
		local runtime, _, _, state = setup(nil)
		local seen = {}
		local watcher = runtime.packages:Register({
			GetName = function()
				return "watcher"
			end,
			Subscribe = function() end,
		}, { api = "0.1" })
		for _, name in ipairs({ "operator_added", "operator_removed" }) do
			watcher:Listen("foundation:" .. name, function(event)
				seen[#seen + 1] = name .. ":" .. event:Get("account") .. ":" .. event:Get("by")
			end)
		end
		runtime.operators:Add("alex-id", "Alex", "console")
		runtime.operators:Remove("alex-id", "player:sam-id")
		expect.same(seen, { "operator_added:alex-id:console", "operator_removed:alex-id:player:sam-id" })
		expect.same(state.audited, {
			{
				owner = "foundation",
				action = "foundation:operators/add",
				entry = { actor = "console", target = "alex-id", details = { name = "Alex" } },
			},
			{
				owner = "foundation",
				action = "foundation:operators/remove",
				entry = { actor = "player:sam-id", target = "alex-id", details = { name = "Alex" } },
			},
		})
		expect.contains(text(state.lines), "alex-id is now an operator (by console)")
		expect.contains(text(state.lines), "alex-id is no longer an operator (by player:sam-id)")
	end)

	it("explain refused changes", function()
		local runtime = setup(nil)
		local operators = runtime.operators
		operators:Add("alex-id", nil, "console")
		expect.same({ operators:Add("alex-id", nil, "console") }, { false, "operators.exists" })
		expect.same({ operators:Remove("sam-id", "console") }, { false, "operators.missing" })
		expect.same({ operators:Add("", nil, "console") }, { false, "operators.invalid_id" })
		expect.same({ operators:Add("bad\nid", nil, "console") }, { false, "operators.invalid_id" })
	end)

	it("keep the previous list when the file cannot be written", function()
		local runtime, _, raw = setup(nil)
		raw.fail_rename = true
		expect.same({ runtime.operators:Add("alex-id", nil, "console") }, { false, "operators.write_failed_short" })
		expect.falsy(runtime.operators:IsOperator("alex-id"))
	end)

	for _, case in ipairs({
		{ "{not json", "invalid JSON" },
		{ '{"version":2,"operators":{}}', "expected" },
		{ '{"version":1,"operators":{"alex":{"added_by":"console"}}}', "the entry 'alex' is not valid" },
		{ '{"version":1,"operators":{"alex":{"added_by":"console","added_at":1,"rank":"admin"}}}', "not valid" },
	}) do
		it("refuse changes while the file is damaged: " .. case[2], function()
			local runtime, Foundation, raw, state = setup(case[1])
			expect.contains(text(state.lines), "foundation/operators.json cannot be read")
			expect.contains(text(state.lines), case[2])
			expect.same(Foundation.Operators.List(), {})
			expect.same({ runtime.operators:Add("sam-id", nil, "console") }, { false, "operators.locked" })
			expect.equal(raw.contents[PATH], case[1])
		end)
	end

	it("validate the subject of IsOperator at the caller's line", function()
		local _, Foundation = setup(nil)
		local expected_line
		local ok, message = pcall(function()
			expected_line = debug.getinfo(1, "l").currentline + 1
			Foundation.Operators.IsOperator(42)
		end)
		expect.falsy(ok)
		expect.contains(message, "'subject' must be sender or account id (got number)")
		expect.equal(tonumber(message:match("operators_spec%.lua:(%d+):")), expected_line)
	end)
end)
