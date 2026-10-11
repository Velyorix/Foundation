local Memory = {}
Memory.__index = Memory

function Memory.new()
	return setmetatable({ namespaces = {} }, Memory)
end

function Memory:space(namespace)
	local space = self.namespaces[namespace]
	if not space then
		space = {}
		self.namespaces[namespace] = space
	end
	return space
end

function Memory:Get(namespace, key, callback)
	callback(true, self:space(namespace)[key])
end

function Memory:Set(namespace, key, value, callback)
	self:space(namespace)[key] = value
	callback(true)
end

function Memory:Delete(namespace, key, callback)
	self:space(namespace)[key] = nil
	callback(true)
end

function Memory:Keys(namespace, prefix, limit, callback)
	local keys = {}
	for key in pairs(self:space(namespace)) do
		if key:sub(1, #prefix) == prefix then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	while #keys > limit do
		keys[#keys] = nil
	end
	callback(true, keys)
end

-- operations: { { op = "set", key, value } | { op = "delete", key } }, applied together.
function Memory:Batch(namespace, operations, callback)
	local space = self:space(namespace)
	for _, operation in ipairs(operations) do
		if operation.op == "set" then
			space[operation.key] = operation.value
		else
			space[operation.key] = nil
		end
	end
	callback(true)
end

function Memory:Usage(namespace, callback)
	local count, bytes = 0, 0
	for key, value in pairs(self:space(namespace)) do
		count = count + 1
		bytes = bytes + #key + #value
	end
	callback(true, { count = count, bytes = bytes })
end

function Memory:Flush(callback)
	callback(true)
end

return Memory
