local Invoker = {}
Invoker.__index = Invoker

function Invoker.new(options)
	return setmetatable({
		log = options.log,
		side = options.side,
		stack = {},
		owners = {},
		total_errors = 0,
	}, Invoker)
end

function Invoker:Side()
	return self.side
end

-- info of the innermost Foundation callback running now, or nil.
function Invoker:Current()
	return self.stack[#self.stack]
end

function Invoker:Depth()
	return #self.stack
end

function Invoker:record_failure(info, err)
	local stats = self.owners[info.owner]
	if not stats then
		stats = { errors = 0, kinds = {} }
		self.owners[info.owner] = stats
	end
	stats.errors = stats.errors + 1
	stats.kinds[info.kind] = (stats.kinds[info.kind] or 0) + 1
	stats.last = { kind = info.kind, message = tostring(err):match("^[^\n]*") }
	self.total_errors = self.total_errors + 1

	local fields = { trace = tostring(err) }
	if info.fields then
		for key, value in pairs(info.fields) do
			fields[key] = value
		end
	end
	self.log:Error("invoke.failed", { owner = info.owner, kind = info.kind }, fields)
end

-- Returns true and fn's results, or false and the error with its traceback.
function Invoker:Call(info, fn, ...)
	local stack = self.stack
	stack[#stack + 1] = info
	local results = table.pack(xpcall(fn, debug.traceback, ...))
	stack[#stack] = nil
	if not results[1] then
		self:record_failure(info, results[2])
	end
	return table.unpack(results, 1, results.n)
end

function Invoker:Errors(owner)
	local stats = self.owners[owner]
	return stats and stats.errors or 0
end

function Invoker:Snapshot()
	local owners = {}
	for owner, stats in pairs(self.owners) do
		local kinds = {}
		for kind, count in pairs(stats.kinds) do
			kinds[kind] = count
		end
		owners[owner] = { errors = stats.errors, kinds = kinds, last = stats.last }
	end
	return { side = self.side, total_errors = self.total_errors, owners = owners }
end

return Invoker
