local Sqlite = {}
Sqlite.__index = Sqlite

Sqlite.ROWS_PER_STATEMENT = 200
Sqlite.MAX_MERGED_OPERATIONS = 5000

local SCHEMA = "CREATE TABLE IF NOT EXISTS foundation_kv ("
	.. "namespace TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated_at INTEGER NOT NULL, "
	.. "PRIMARY KEY (namespace, key)) WITHOUT ROWID"

local function like_prefix(prefix)
	return (prefix:gsub("[\\%%_]", "\\%0")) .. "%"
end

-- options: open(path) returning a native Database or nil, files (core/files.lua), path, now
function Sqlite.new(options)
	return setmetatable({
		open = options.open,
		files = options.files,
		path = options.path or "foundation/data/foundation.db",
		now = options.now,
		queue = {},
		busy = false,
	}, Sqlite)
end

-- Returns true, or false and a reason.
function Sqlite:Open()
	local directory = self.path:match("^(.*)/[^/]+$")
	if directory then
		local ready, reason = self.files:EnsureDirectory(directory)
		if not ready then
			return false, reason
		end
	end
	local ok, database = pcall(self.open, self.path)
	if not ok or not database then
		return false, tostring(database)
	end
	local _, err = database:Execute(SCHEMA)
	if err then
		return false, err
	end
	self.database = database
	return true
end

-- Statements for a list of { namespace, op, key, value }: the last operation on a key wins,
-- sets become multi-row upserts and deletes multi-row deletes.
function Sqlite:compile(operations)
	local final, order = {}, {}
	for _, operation in ipairs(operations) do
		local id = operation.namespace .. "\0" .. operation.key
		if not final[id] then
			order[#order + 1] = id
		end
		final[id] = operation
	end
	local sets, deletes = {}, {}
	for _, id in ipairs(order) do
		local operation = final[id]
		if operation.op == "set" then
			sets[#sets + 1] = operation
		else
			deletes[#deletes + 1] = operation
		end
	end
	local steps, now = {}, self.now()
	for first = 1, #sets, Sqlite.ROWS_PER_STATEMENT do
		local rows, params = {}, {}
		for index = first, math.min(first + Sqlite.ROWS_PER_STATEMENT - 1, #sets) do
			local base = #params
			rows[#rows + 1] = string.format("(:%d, :%d, :%d, :%d)", base, base + 1, base + 2, base + 3)
			local operation = sets[index]
			params[base + 1], params[base + 2], params[base + 3], params[base + 4] =
				operation.namespace, operation.key, operation.value, now
		end
		steps[#steps + 1] = {
			sql = "INSERT INTO foundation_kv (namespace, key, value, updated_at) VALUES "
				.. table.concat(rows, ", ")
				.. " ON CONFLICT (namespace, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
			params = params,
		}
	end
	for first = 1, #deletes, Sqlite.ROWS_PER_STATEMENT do
		local conditions, params = {}, {}
		for index = first, math.min(first + Sqlite.ROWS_PER_STATEMENT - 1, #deletes) do
			local base = #params
			conditions[#conditions + 1] = string.format("(namespace = :%d AND key = :%d)", base, base + 1)
			params[base + 1], params[base + 2] = deletes[index].namespace, deletes[index].key
		end
		steps[#steps + 1] =
			{ sql = "DELETE FROM foundation_kv WHERE " .. table.concat(conditions, " OR "), params = params }
	end
	if #steps > 1 then
		table.insert(steps, 1, { sql = "BEGIN IMMEDIATE" })
		steps[#steps + 1] = { sql = "COMMIT" }
		return steps, true
	end
	return steps, false
end

function Sqlite:enqueue(job)
	self.queue[#self.queue + 1] = job
	self:pump()
end

-- Takes the next job, merged with the write jobs right behind it.
function Sqlite:take()
	local job = table.remove(self.queue, 1)
	if not job.operations then
		return job
	end
	local group, operations = { job }, {}
	for _, operation in ipairs(job.operations) do
		operations[#operations + 1] = operation
	end
	while self.queue[1] and self.queue[1].operations and not self.queue[1].alone do
		local next_job = self.queue[1]
		if #operations + #next_job.operations > Sqlite.MAX_MERGED_OPERATIONS then
			break
		end
		table.remove(self.queue, 1)
		group[#group + 1] = next_job
		for _, operation in ipairs(next_job.operations) do
			operations[#operations + 1] = operation
		end
	end
	local steps, transaction = self:compile(operations)
	return {
		steps = steps,
		transaction = transaction,
		finish = function(ok, err)
			if ok or #group == 1 then
				for _, member in ipairs(group) do
					pcall(member.finish, ok, err)
				end
				return
			end
			-- Replay one by one so that only the job at fault fails.
			for index = #group, 1, -1 do
				group[index].alone = true
				table.insert(self.queue, 1, group[index])
			end
		end,
	}
end

function Sqlite:pump()
	while not self.busy and #self.queue > 0 do
		local job = self:take()
		if not self.database then
			pcall(job.finish, false, "storage is not open")
		elseif self.sync then
			self:run_sync(job)
		else
			self.busy = true
			self.current = job
			self:run_step(job, 1, nil)
			return
		end
	end
end

function Sqlite:complete(job, ok, result)
	if self.current ~= job then
		return
	end
	self.current = nil
	self.busy = false
	pcall(job.finish, ok, result)
	self:pump()
end

-- Runs every step with the blocking API; used once async queries are no longer possible
-- (the engine refuses them while Foundation unloads).
function Sqlite:run_sync(job)
	local database, last = self.database, nil
	for index, step in ipairs(job.steps) do
		local result, err
		if step.select then
			result, err = database:Select(step.sql, table.unpack(step.params or {}))
		else
			result, err = database:Execute(step.sql, table.unpack(step.params or {}))
		end
		if err then
			if job.transaction and index > 1 then
				database:Execute("ROLLBACK")
			end
			pcall(job.finish, false, err)
			return
		end
		last = result
	end
	pcall(job.finish, true, last)
end

-- Restarts the job in flight synchronously: its async answer may never come. Writes set final
-- states, so running them again is harmless; an open transaction is rolled back first.
function Sqlite:abandon_current()
	local job, index = self.current, self.current_index or 1
	self.current, self.busy = nil, false
	if not job then
		return
	end
	if job.transaction and index > 1 then
		self.database:Execute("ROLLBACK")
	end
	self:run_sync(job)
end

-- Switches to blocking queries and runs everything still queued. Called when Foundation stops.
function Sqlite:Drain()
	if not self.database then
		return 0
	end
	local pending = #self.queue + (self.current and 1 or 0)
	self.sync = true
	self:abandon_current()
	self:pump()
	return pending
end

function Sqlite:run_step(job, index, last)
	local step = job.steps[index]
	if not step then
		return self:complete(job, true, last)
	end
	self.current_index = index
	local method = step.select and "SelectAsync" or "ExecuteAsync"
	local sent = pcall(self.database[method], self.database, step.sql, function(result, err)
		if self.current ~= job then
			return
		end
		if err then
			if job.transaction and index > 1 then
				self.database:ExecuteAsync("ROLLBACK", function()
					self:complete(job, false, err)
				end)
				return
			end
			return self:complete(job, false, err)
		end
		self:run_step(job, index + 1, result)
	end, table.unpack(step.params or {}))
	if not sent then
		self.sync = true
		self:abandon_current()
		self:pump()
	end
end

function Sqlite:write(operations, callback)
	self:enqueue({
		operations = operations,
		finish = function(ok, err)
			callback(ok, not ok and err or nil)
		end,
	})
end

function Sqlite:Get(namespace, key, callback)
	self:enqueue({
		steps = {
			{
				sql = "SELECT value FROM foundation_kv WHERE namespace = :0 AND key = :1",
				params = { namespace, key },
				select = true,
			},
		},
		finish = function(ok, rows)
			if not ok then
				return callback(false, rows)
			end
			callback(true, rows[1] and rows[1].value or nil)
		end,
	})
end

function Sqlite:Set(namespace, key, value, callback)
	self:write({ { namespace = namespace, op = "set", key = key, value = value } }, callback)
end

function Sqlite:Delete(namespace, key, callback)
	self:write({ { namespace = namespace, op = "delete", key = key } }, callback)
end

-- operations: { { op = "set", key, value } | { op = "delete", key } }, applied together.
function Sqlite:Batch(namespace, operations, callback)
	local list = {}
	for index, operation in ipairs(operations) do
		list[index] = { namespace = namespace, op = operation.op, key = operation.key, value = operation.value }
	end
	self:write(list, callback)
end

function Sqlite:Keys(namespace, prefix, limit, callback)
	self:enqueue({
		steps = {
			{
				sql = "SELECT key FROM foundation_kv WHERE namespace = :0 AND key LIKE :1 ESCAPE '\\' ORDER BY key LIMIT :2",
				params = { namespace, like_prefix(prefix), limit },
				select = true,
			},
		},
		finish = function(ok, rows)
			if not ok then
				return callback(false, rows)
			end
			local keys = {}
			for index, row in ipairs(rows) do
				keys[index] = row.key
			end
			callback(true, keys)
		end,
	})
end

function Sqlite:Usage(namespace, callback)
	self:enqueue({
		steps = {
			{
				sql = "SELECT COUNT(*) AS count, COALESCE(SUM(LENGTH(key) + LENGTH(value)), 0) AS bytes "
					.. "FROM foundation_kv WHERE namespace = :0",
				params = { namespace },
				select = true,
			},
		},
		finish = function(ok, rows)
			if not ok then
				return callback(false, rows)
			end
			callback(true, { count = tonumber(rows[1].count) or 0, bytes = tonumber(rows[1].bytes) or 0 })
		end,
	})
end

-- Every key and value of a namespace.
function Sqlite:All(namespace, callback)
	self:enqueue({
		steps = {
			{
				sql = "SELECT key, value FROM foundation_kv WHERE namespace = :0",
				params = { namespace },
				select = true,
			},
		},
		finish = function(ok, rows)
			if not ok then
				return callback(false, rows)
			end
			local values = {}
			for _, row in ipairs(rows) do
				values[row.key] = row.value
			end
			callback(true, values)
		end,
	})
end

-- Applies operations of several namespaces ({ namespace, op, key, value }) together.
function Sqlite:Write(operations, callback)
	self:enqueue({
		operations = operations,
		alone = true,
		finish = function(ok, err)
			callback(ok, not ok and err or nil)
		end,
	})
end

-- Size (key + value bytes) of every key of a namespace.
function Sqlite:Sizes(namespace, callback)
	self:enqueue({
		steps = {
			{
				sql = "SELECT key, LENGTH(key) + LENGTH(value) AS size FROM foundation_kv WHERE namespace = :0",
				params = { namespace },
				select = true,
			},
		},
		finish = function(ok, rows)
			if not ok then
				return callback(false, rows)
			end
			local sizes = {}
			for _, row in ipairs(rows) do
				sizes[row.key] = tonumber(row.size) or 0
			end
			callback(true, sizes)
		end,
	})
end

-- Calls back once every operation queued before it has finished.
function Sqlite:Flush(callback)
	self:enqueue({ steps = {}, finish = callback })
end

return Sqlite
