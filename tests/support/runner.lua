-- Minimal spec runner: describe/it blocks, before_each/after_each hooks, plain-text
-- report and a non-zero exit status on failure.

local Runner = {}
Runner.__index = Runner

function Runner.new(output)
	return setmetatable({
		output = output or io.stdout,
		passed = 0,
		failed = 0,
		failures = {},
	}, Runner)
end

local function new_group(name, parent)
	return { name = name, parent = parent, children = {}, before = {}, after = {} }
end

local function full_name(group, test_name)
	local parts = { test_name }
	local current = group
	while current and current.name do
		table.insert(parts, 1, current.name)
		current = current.parent
	end
	return table.concat(parts, " > ")
end

local function collect_hooks(group, field)
	local chain = {}
	local current = group
	while current do
		table.insert(chain, 1, current)
		current = current.parent
	end
	local hooks = {}
	for _, node in ipairs(chain) do
		for _, hook in ipairs(node[field]) do
			hooks[#hooks + 1] = hook
		end
	end
	if field == "after" then
		local reversed = {}
		for index = #hooks, 1, -1 do
			reversed[#reversed + 1] = hooks[index]
		end
		return reversed
	end
	return hooks
end

local function short_traceback(err)
	return debug.traceback(tostring(err), 2)
end

--- Loads one spec file and returns its root group, or nil and a load error.
function Runner:collect(path, extra_globals)
	local root = new_group(nil, nil)
	local current = root
	local env = setmetatable({}, { __index = _G })
	for key, value in pairs(extra_globals or {}) do
		env[key] = value
	end
	env.describe = function(name, body)
		local group = new_group(name, current)
		current.children[#current.children + 1] = group
		local previous = current
		current = group
		body()
		current = previous
	end
	env.it = function(name, body)
		current.children[#current.children + 1] = { test = true, name = name, body = body, group = current }
	end
	env.before_each = function(hook)
		current.before[#current.before + 1] = hook
	end
	env.after_each = function(hook)
		current.after[#current.after + 1] = hook
	end

	local handle, open_error = io.open(path, "rb")
	if not handle then
		return nil, open_error
	end
	local source = handle:read("a")
	handle:close()
	local chunk, compile_error = load(source, "@" .. path, "t", env)
	if not chunk then
		return nil, compile_error
	end
	local ok, run_error = xpcall(chunk, short_traceback)
	if not ok then
		return nil, run_error
	end
	return root
end

function Runner:run_test(test)
	local ok, err = true, nil
	for _, hook in ipairs(collect_hooks(test.group, "before")) do
		ok, err = xpcall(hook, short_traceback)
		if not ok then
			break
		end
	end
	if ok then
		ok, err = xpcall(test.body, short_traceback)
	end
	for _, hook in ipairs(collect_hooks(test.group, "after")) do
		local hook_ok, hook_err = xpcall(hook, short_traceback)
		if ok and not hook_ok then
			ok, err = false, hook_err
		end
	end
	return ok, err
end

function Runner:run_group(group, path)
	for _, child in ipairs(group.children) do
		if child.test then
			local name = full_name(child.group, child.name)
			local ok, err = self:run_test(child)
			if ok then
				self.passed = self.passed + 1
				self.output:write("  ok    ", name, "\n")
			else
				self.failed = self.failed + 1
				self.failures[#self.failures + 1] = { path = path, name = name, err = err }
				self.output:write("  FAIL  ", name, "\n")
			end
		else
			self:run_group(child, path)
		end
	end
end

function Runner:run_file(path, extra_globals)
	self.output:write(path, "\n")
	local root, load_error = self:collect(path, extra_globals)
	if not root then
		self.failed = self.failed + 1
		self.failures[#self.failures + 1] = { path = path, name = "(load)", err = load_error }
		self.output:write("  FAIL  (load)\n")
		return
	end
	self:run_group(root, path)
end

function Runner:report()
	if #self.failures > 0 then
		self.output:write("\nFailures:\n")
		for _, failure in ipairs(self.failures) do
			self.output:write("\n", failure.path, " :: ", failure.name, "\n", tostring(failure.err), "\n")
		end
	end
	self.output:write(string.format("\n%d passed, %d failed\n", self.passed, self.failed))
	return self.failed == 0
end

return Runner
