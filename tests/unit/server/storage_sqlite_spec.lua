-- Fake native Database: async queries wait until the test answers them, so the spec can
-- check that the backend never has two queries in flight.
local function fake_database()
	local database = { pending = {}, log = {}, max_in_flight = 0, sync = {} }
	local function submit(kind, sql, callback, ...)
		database.log[#database.log + 1] = sql
		database.pending[#database.pending + 1] = { kind = kind, sql = sql, callback = callback, params = { ... } }
		if #database.pending > database.max_in_flight then
			database.max_in_flight = #database.pending
		end
	end
	function database:ExecuteAsync(sql, callback, ...)
		submit("execute", sql, callback, ...)
	end
	function database:SelectAsync(sql, callback, ...)
		submit("select", sql, callback, ...)
	end
	function database:Execute(sql)
		self.sync[#self.sync + 1] = sql
		return 0, self.schema_error
	end
	-- Answers the oldest pending query.
	function database:answer(result, err)
		local query = table.remove(self.pending, 1)
		assert(query, "no pending query")
		query.callback(result, err)
		return query
	end
	return database
end

local function memory_files(fail_directory)
	local raw = { directories = {} }
	function raw.IsDirectory(path)
		return raw.directories[path] == true
	end
	function raw.CreateDirectory(path)
		if not fail_directory then
			raw.directories[path] = true
		end
		return not fail_directory
	end
	return raw
end

local function setup(options)
	options = options or {}
	local loader = Loader.new({ side = "Server" })
	local Sqlite = loader:require("foundation/core/storage_sqlite.lua")
	local Files = loader:require("foundation/core/files.lua")
	local database = fake_database()
	database.schema_error = options.schema_error
	local opened
	local backend = Sqlite.new({
		open = function(path)
			opened = path
			if options.open_fails then
				return nil
			end
			return database
		end,
		files = Files.new(memory_files(options.fail_directory)),
		now = function()
			return 1760100000
		end,
	})
	return backend, database, function()
		return opened
	end
end

describe("SQLite storage backend", function()
	describe("opening", function()
		it("creates the directory, opens the file and creates the table", function()
			local backend, database, opened = setup()
			expect.same({ backend:Open() }, { true })
			expect.equal(opened(), "foundation/data/foundation.db")
			expect.contains(database.sync[1], "CREATE TABLE IF NOT EXISTS foundation_kv")
		end)

		it("reports what went wrong", function()
			expect.same({ setup({ fail_directory = true }):Open() }, { false, "foundation/data" })
			expect.falsy((setup({ open_fails = true }):Open()))
			expect.same({ setup({ schema_error = "disk I/O error" }):Open() }, { false, "disk I/O error" })
		end)

		it("fails operations when the database is not open", function()
			local backend = setup()
			local ok, reason
			backend:Get("shop", "a", function(a, b)
				ok, reason = a, b
			end)
			expect.same({ ok, reason }, { false, "storage is not open" })
		end)
	end)

	describe("queue", function()
		local backend, database

		before_each(function()
			backend, database = setup()
			backend:Open()
		end)

		it("sends one query at a time, in submission order", function()
			local results = {}
			backend:Set("shop", "a", "1", function(ok)
				results[#results + 1] = "set:" .. tostring(ok)
			end)
			backend:Get("shop", "a", function(_, value)
				results[#results + 1] = "get:" .. tostring(value)
			end)
			backend:Delete("shop", "a", function(ok)
				results[#results + 1] = "delete:" .. tostring(ok)
			end)
			expect.equal(#database.pending, 1)
			local set = database:answer(1)
			expect.equal(#database.pending, 1)
			database:answer({ { value = "1" } })
			database:answer(1)
			expect.equal(database.max_in_flight, 1)
			expect.same(results, { "set:true", "get:1", "delete:true" })
			expect.same(set.params, { "shop", "a", "1", 1760100000 })
		end)

		it("returns nil for a missing key and converts usage numbers", function()
			local value, usage = "unset", nil
			backend:Get("shop", "missing", function(_, v)
				value = v
			end)
			backend:Usage("shop", function(_, u)
				usage = u
			end)
			database:answer({})
			database:answer({ { count = "3", bytes = "42" } })
			expect.is_nil(value)
			expect.same(usage, { count = 3, bytes = 42 })
		end)

		it("escapes LIKE wildcards in key prefixes", function()
			backend:Keys("shop", "50%_off\\", 10, function() end)
			local query = database:answer({ { key = "50%_off\\x" } })
			expect.same(query.params, { "shop", "50\\%\\_off\\\\%", 10 })
		end)

		it("keeps going when a callback raises", function()
			backend:Set("shop", "a", "1", function()
				error("caller bug")
			end)
			local reached = false
			backend:Set("shop", "b", "2", function()
				reached = true
			end)
			database:answer(1)
			database:answer(1)
			expect.truthy(reached)
		end)

		it("reports SQL errors to the caller", function()
			local ok, reason
			backend:Set("shop", "a", "1", function(a, b)
				ok, reason = a, b
			end)
			database:answer(0, "SQL Error: disk full")
			expect.same({ ok, reason }, { false, "SQL Error: disk full" })
		end)

		it("calls Flush back once earlier operations are done", function()
			local order = {}
			backend:Set("shop", "a", "1", function()
				order[#order + 1] = "set"
			end)
			backend:Flush(function()
				order[#order + 1] = "flush"
			end)
			expect.same(order, {})
			database:answer(1)
			expect.same(order, { "set", "flush" })
		end)
	end)

	describe("batches", function()
		local backend, database

		before_each(function()
			backend, database = setup()
			backend:Open()
		end)

		local function batch()
			local outcome = {}
			backend:Batch("shop", {
				{ op = "set", key = "a", value = "1" },
				{ op = "delete", key = "b" },
			}, function(ok, reason)
				outcome.ok, outcome.reason = ok, reason
			end)
			return outcome
		end

		it("wraps the operations in a transaction", function()
			local outcome = batch()
			for _ = 1, 4 do
				database:answer(1)
			end
			expect.truthy(outcome.ok)
			expect.equal(database.log[1], "BEGIN IMMEDIATE")
			expect.contains(database.log[2], "INSERT INTO foundation_kv")
			expect.contains(database.log[3], "DELETE FROM foundation_kv")
			expect.equal(database.log[4], "COMMIT")
		end)

		it("rolls back on the first error and lets the next job run afterwards", function()
			local outcome = batch()
			local after = false
			backend:Get("shop", "a", function()
				after = true
			end)
			database:answer(1)
			database:answer(0, "SQL Error: constraint failed")
			expect.equal(database.log[3], "ROLLBACK")
			expect.equal(#database.pending, 1)
			database:answer(0)
			expect.same(outcome, { ok = false, reason = "SQL Error: constraint failed" })
			expect.contains(database.log[4], "SELECT value FROM foundation_kv")
			database:answer({})
			expect.truthy(after)
			expect.equal(database.max_in_flight, 1)
		end)
	end)

	describe("merging", function()
		local backend, database

		before_each(function()
			backend, database = setup()
			backend:Open()
			backend:Set("shop", "busy", "x", function() end)
		end)

		it("merges waiting writes, the last one on a key winning", function()
			local done = {}
			local function note(name)
				return function(ok)
					done[#done + 1] = name .. ":" .. tostring(ok)
				end
			end
			backend:Set("shop", "a", "1", note("a1"))
			backend:Set("shop", "a", "2", note("a2"))
			backend:Delete("shop", "b", note("b"))
			backend:Batch("bank", { { op = "set", key = "c", value = "3" } }, note("c"))
			database:answer(1)
			expect.same(database.log, {
				database.log[1],
				"BEGIN IMMEDIATE",
			})
			database:answer(0)
			local insert = database:answer(2)
			expect.contains(insert.sql, "VALUES (:0, :1, :2, :3), (:4, :5, :6, :7) ON CONFLICT")
			expect.same(insert.params, { "shop", "a", "2", 1760100000, "bank", "c", "3", 1760100000 })
			local delete = database:answer(1)
			expect.equal(delete.sql, "DELETE FROM foundation_kv WHERE (namespace = :0 AND key = :1)")
			expect.same(delete.params, { "shop", "b" })
			expect.same(done, {})
			database:answer(0)
			expect.same(done, { "a1:true", "a2:true", "b:true", "c:true" })
		end)

		it("sends a single statement without a transaction", function()
			backend:Set("shop", "a", "1", function() end)
			backend:Set("shop", "b", "2", function() end)
			database:answer(1)
			local insert = database:answer(2)
			expect.contains(insert.sql, "INSERT INTO foundation_kv")
			expect.equal(#database.pending, 0)
			expect.equal(#database.log, 2)
		end)

		it("splits large writes into chunks inside one transaction", function()
			local operations = {}
			for index = 1, 450 do
				operations[index] = { op = "set", key = "k" .. index, value = "v" }
			end
			backend:Batch("shop", operations, function() end)
			database:answer(1)
			local statements = {}
			while #database.pending > 0 do
				statements[#statements + 1] = database:answer(1).sql:sub(1, 14)
			end
			expect.same(
				statements,
				{ "BEGIN IMMEDIAT", "INSERT INTO fo", "INSERT INTO fo", "INSERT INTO fo", "COMMIT" }
			)
		end)

		it("replays a failed group one job at a time so that only the faulty one fails", function()
			local outcomes = {}
			backend:Set("shop", "good", "1", function(ok)
				outcomes.good = ok
			end)
			backend:Set("shop", "bad", "2", function(ok, reason)
				outcomes.bad = { ok, reason }
			end)
			database:answer(1)
			database:answer(0, "SQL Error: something")
			database:answer(1)
			database:answer(0, "SQL Error: bad value")
			expect.truthy(outcomes.good)
			expect.same(outcomes.bad, { false, "SQL Error: bad value" })
			expect.equal(database.max_in_flight, 1)
		end)
	end)
end)
