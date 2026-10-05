local Ownership = {}
Ownership.__index = Ownership

local Handle = {}
Handle.__index = Handle

function Handle:Release()
	return self.tracker:Release(self)
end

function Handle:IsActive()
	return not self.released
end

function Ownership.new(options)
	return setmetatable({
		check = options.check,
		errors = options.check.errors,
		invoker = options.invoker,
		sequence = 0,
		owners = {},
		release_failures = 0,
	}, Ownership)
end

function Ownership:owner_state(owner)
	local state = self.owners[owner]
	if not state then
		state = { resources = {}, count = 0, kinds = {}, closed = false, releasing = false }
		self.owners[owner] = state
	end
	return state
end

function Ownership:Track(owner, kind, release, info)
	local check = self.check
	check:NonEmptyString("Ownership:Track", 1, "owner", owner)
	check:NonEmptyString("Ownership:Track", 2, "kind", kind)
	check:Argument("Ownership:Track", 3, "release", release, "function")
	check:Argument("Ownership:Track", 4, "info", info, "table?")
	local state = self:owner_state(owner)
	if state.closed or state.releasing then
		self.errors:Raise("invalid_state", {
			api = "Ownership:Track",
			reason = self.errors.messages:Format("reason.owner_closed", { owner = owner }),
		})
	end
	self.sequence = self.sequence + 1
	local copied
	if info then
		copied = {}
		for key, value in pairs(info) do
			copied[key] = value
		end
	end
	local handle = setmetatable({
		tracker = self,
		id = self.sequence,
		sequence = self.sequence,
		owner = owner,
		kind = kind,
		info = copied,
		release = release,
		released = false,
	}, Handle)
	state.resources[handle] = true
	state.count = state.count + 1
	state.kinds[kind] = (state.kinds[kind] or 0) + 1
	return handle
end

function Ownership:forget(handle)
	local state = self.owners[handle.owner]
	if state and state.resources[handle] then
		state.resources[handle] = nil
		state.count = state.count - 1
		local remaining = state.kinds[handle.kind] - 1
		state.kinds[handle.kind] = remaining > 0 and remaining or nil
	end
end

function Ownership:run_release(handle)
	local release = handle.release
	handle.released = true
	handle.release = nil
	self:forget(handle)
	local ok = self.invoker:Call(
		{ owner = handle.owner, kind = "release", fields = { resource = handle.kind, id = handle.id } },
		release,
		handle
	)
	if not ok then
		self.release_failures = self.release_failures + 1
	end
	return ok
end

-- Returns true when the release callback ran now, false when already released.
function Ownership:Release(handle)
	if type(handle) ~= "table" or getmetatable(handle) ~= Handle or handle.tracker ~= self then
		self.errors:Raise("invalid_argument", {
			api = "Ownership:Release",
			index = 1,
			name = "handle",
			expected = "resource handle",
			actual = type(handle),
		})
	end
	if handle.released then
		return false
	end
	self:run_release(handle)
	return true
end

-- Releases every resource of `owner`, newest first. With `close`, the owner then
-- refuses new resources until Open is called.
function Ownership:ReleaseOwner(owner, close)
	local state = self.owners[owner]
	if not state then
		if close then
			self:owner_state(owner).closed = true
		end
		return 0, 0
	end
	if state.releasing then
		return 0, 0
	end
	state.releasing = true
	local handles = {}
	for handle in pairs(state.resources) do
		handles[#handles + 1] = handle
	end
	table.sort(handles, function(a, b)
		return a.sequence > b.sequence
	end)
	local released, failed = 0, 0
	for _, handle in ipairs(handles) do
		if not handle.released then
			if self:run_release(handle) then
				released = released + 1
			else
				failed = failed + 1
			end
		end
	end
	state.releasing = false
	if close then
		state.closed = true
	end
	if state.count == 0 and not state.closed then
		self.owners[owner] = nil
	end
	return released, failed
end

function Ownership:Open(owner)
	local state = self.owners[owner]
	if state then
		state.closed = false
	end
end

function Ownership:IsClosed(owner)
	local state = self.owners[owner]
	return state ~= nil and state.closed
end

function Ownership:Count(owner, kind)
	local state = self.owners[owner]
	if not state then
		return 0
	end
	if kind then
		return state.kinds[kind] or 0
	end
	return state.count
end

function Ownership:Snapshot()
	local owners = {}
	local total = 0
	for owner, state in pairs(self.owners) do
		local kinds = {}
		for kind, count in pairs(state.kinds) do
			kinds[kind] = count
		end
		owners[owner] = { count = state.count, kinds = kinds, closed = state.closed }
		total = total + state.count
	end
	return { total = total, owners = owners, release_failures = self.release_failures }
end

return Ownership
