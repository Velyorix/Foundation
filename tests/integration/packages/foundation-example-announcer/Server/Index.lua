local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Announcer",
})

local db = Database(DatabaseEngine.SQLite, "db=:memory:")
db:Execute("CREATE TABLE announcements (position INTEGER, text TEXT)")
db:Execute([[INSERT INTO announcements VALUES
	(1, 'Welcome to the server!'),
	(2, 'Read the rules with /rules.'),
	(3, 'Have fun!')]])

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

local function announce_all(rows)
	local index = 0
	context:Repeat(1000, function()
		index = index + 1
		Console.Log("announcement: %s", rows[index].text)
		if index == #rows then
			return false
		end
	end)
end

context:OnReady(function()
	select_async("SELECT text FROM announcements ORDER BY position")
		:Timeout(5000)
		:Then(function(rows)
			Console.Log("loaded %d announcements", #rows)
			announce_all(rows)
		end)
		:Catch(function(err)
			Console.Error("could not load announcements: %s", tostring(err))
		end)
end)
