local Files = Package.Require("foundation/Server/foundation/core/files.lua")
local Sqlite = Package.Require("foundation/Server/foundation/core/storage_sqlite.lua")

local backend = Sqlite.new({
	open = function(path)
		return Database(DatabaseEngine.SQLite, "db=" .. path .. " timeout=2", 1)
	end,
	files = Files.new({
		Open = function(path, truncate)
			return File(path, truncate)
		end,
		Exists = File.Exists,
		CreateDirectory = File.CreateDirectory,
		IsDirectory = File.IsDirectory,
		Rename = File.Rename,
	}),
	path = "foundation/data/backend-test.db",
	now = function()
		return math.floor(Server.GetTime() / 1000)
	end,
})

local suite = FoundationTest.Suite("core-storage")

suite:Test("the backend creates its directory and table", function()
	FoundationTest.Equal(backend:Open(), true)
	FoundationTest.True(File.Exists("foundation/data/backend-test.db"))
end)

suite:Async("many writes to one key keep their order and finish quickly", 5000, function(done)
	local started = Server.GetTime()
	for index = 1, 200 do
		backend:Set("shop", "counter", tostring(index), function() end)
	end
	backend:Get("shop", "counter", function(ok, value)
		local elapsed = Server.GetTime() - started
		if not ok or value ~= "200" then
			done("got " .. tostring(value))
		elseif elapsed > 1000 then
			done("took " .. elapsed .. " ms")
		else
			done()
		end
	end)
end)

suite:Async("values, deletes and prefixes round-trip", 5000, function(done)
	local tricky = 'it\'s "quoted"; DROP TABLE foundation_kv; -- é\n'
	backend:Set("shop", "items/50%_off", tricky, function() end)
	backend:Set("shop", "items/apple", "1", function() end)
	backend:Set("shop", "itemsX", "no", function() end)
	backend:Set("bank", "items/other", "x", function() end)
	backend:Delete("shop", "items/apple", function() end)
	backend:Keys("shop", "items/", 10, function(_, keys)
		if table.concat(keys, ",") ~= "items/50%_off" then
			return done("keys " .. table.concat(keys, ","))
		end
		backend:Get("shop", "items/50%_off", function(_, value)
			if value ~= tricky then
				return done("value " .. tostring(value))
			end
			backend:Keys("shop", "items/50%", 10, function(_, escaped)
				if #escaped == 1 then
					done()
				else
					done("escaped " .. #escaped)
				end
			end)
		end)
	end)
end)

suite:Async("a batch is applied as a whole or not at all", 5000, function(done)
	backend:Batch("shop", {
		{ op = "set", key = "tx/a", value = "1" },
		{ op = "set", key = "tx/b", value = "2" },
	}, function(ok)
		if not ok then
			return done("commit failed")
		end
		backend:Batch("shop", {
			{ op = "set", key = "tx/c", value = "3" },
			{ op = "delete", key = "tx/a" },
			{ op = "set", key = "tx/d" },
		}, function(failed_ok, reason)
			if failed_ok then
				return done("the failing batch was accepted")
			end
			backend:Keys("shop", "tx/", 10, function(_, keys)
				local listed = table.concat(keys, ",")
				if listed == "tx/a,tx/b" then
					done()
				else
					done("after rollback: " .. listed .. " " .. tostring(reason))
				end
			end)
		end)
	end)
end)

suite:Async("usage counts the namespace only, and Flush waits for earlier work", 5000, function(done)
	local flushed = false
	backend:Set("usage", "k", "1234", function() end)
	backend:Flush(function()
		flushed = true
	end)
	backend:Usage("usage", function(ok, usage)
		if ok and flushed and usage.count == 1 and usage.bytes == 5 then
			done()
		else
			done("usage " .. tostring(usage and usage.count) .. "/" .. tostring(usage and usage.bytes))
		end
	end)
end)

suite:Run()
