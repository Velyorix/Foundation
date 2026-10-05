local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local db = Database(DatabaseEngine.SQLite, "db=:memory:")
db:Execute("CREATE TABLE items (name TEXT)")
db:Execute("INSERT INTO items VALUES ('apple'), ('pear')")

local function select_async(query)
	return context:Future(function(resolve, reject)
		db:SelectAsync(query, function(rows, err)
			if err then
				reject(err)
			else
				resolve(rows)
			end
		end)
	end)
end

local suite = FoundationTest.Suite("core-future")

suite:Async("a database query resolves on a later tick", 3000, function(done)
	local synchronous = true
	select_async("SELECT name FROM items ORDER BY name")
		:Then(function(rows)
			if synchronous then
				done("resolved synchronously")
			elseif #rows ~= 2 or rows[1].name ~= "apple" then
				done("unexpected rows: " .. JSON.stringify(rows))
			else
				done()
			end
		end)
		:Catch(function(err)
			done("rejected: " .. tostring(err))
		end)
	synchronous = false
end)

suite:Async("a failing query rejects with the database error", 3000, function(done)
	select_async("SELECT * FROM missing_table")
		:Then(function()
			done("resolved")
		end)
		:Catch(function(err)
			if tostring(err):find("missing_table", 1, true) then
				done()
			else
				done("unexpected error: " .. tostring(err))
			end
		end)
end)

suite:Async("Timeout rejects a future that never settles", 3000, function(done)
	local started = Server.GetTime()
	context:Future():Timeout(200):Catch(function(err)
		if err.code == "timeout" and Server.GetTime() - started >= 180 then
			done()
		else
			done("unexpected: " .. tostring(err))
		end
	end)
end)

suite:Run()
