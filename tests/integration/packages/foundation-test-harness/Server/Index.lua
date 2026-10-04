-- In-server harness for Foundation integration suites. Suites are ordinary script
-- packages that require this package; scripts/integration.py starts a disposable
-- server, waits for it to stop and reads the result lines from the server log.
--
-- Output protocol, one line per event:
--   [FOUNDATION-TEST] <suite> PASS <test name>
--   [FOUNDATION-TEST] <suite> FAIL <test name> :: <reason>
--   [FOUNDATION-TEST] <suite> DONE passed=<n> failed=<n>

local PREFIX = "[FOUNDATION-TEST]"
local STEP_GAP_MS = 100

local FoundationTest = {}

local function describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function single_line(text)
	return (tostring(text):gsub("[\r\n]+", " | "))
end

function FoundationTest.Equal(actual, expected, message)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				message and (message .. ": ") or "",
				describe(expected),
				describe(actual)
			),
			2
		)
	end
end

function FoundationTest.True(value, message)
	if not value then
		error(message or ("expected a truthy value, got " .. describe(value)), 2)
	end
end

function FoundationTest.Raises(fn, fragment)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error, none was raised", 2)
	end
	if fragment and not tostring(err):find(fragment, 1, true) then
		error(string.format("expected error containing %s, got %s", describe(fragment), describe(tostring(err))), 2)
	end
	return err
end

local Suite = {}
Suite.__index = Suite

--- Creates a suite. Steps run in declaration order after the server `Start` event,
-- each on its own timer tick so that engine work deferred by a step (package
-- reloads, timers) happens before the next one.
function FoundationTest.Suite(name)
	return setmetatable({ name = name, steps = {}, passed = 0, failed = 0, finished = false }, Suite)
end

function Suite:emit(format, ...)
	Console.Log(PREFIX .. " " .. self.name .. " " .. string.format(format, ...))
end

--- Synchronous test: passes unless `fn` raises.
function Suite:Test(name, fn)
	self.steps[#self.steps + 1] = { kind = "test", name = name, fn = fn }
end

--- Asynchronous test: `fn(done)` must call `done()` on success or `done(reason)` on
-- failure within `timeout_ms`.
function Suite:Async(name, timeout_ms, fn)
	self.steps[#self.steps + 1] = { kind = "async", name = name, fn = fn, timeout_ms = timeout_ms }
end

--- Action without a verdict, for setup that takes effect after the call returns.
function Suite:Do(fn)
	self.steps[#self.steps + 1] = { kind = "action", fn = fn }
end

--- Pause between steps.
function Suite:Wait(milliseconds)
	self.steps[#self.steps + 1] = { kind = "wait", milliseconds = milliseconds }
end

function Suite:record(name, ok, reason)
	if ok then
		self.passed = self.passed + 1
		self:emit("PASS %s", name)
	else
		self.failed = self.failed + 1
		self:emit("FAIL %s :: %s", name, single_line(reason))
	end
end

function Suite:finish()
	if self.finished then
		return
	end
	self.finished = true
	self:emit("DONE passed=%d failed=%d", self.passed, self.failed)
	Timer.SetTimeout(function()
		Server.Stop()
	end, 250)
end

function Suite:run_step(index)
	local step = self.steps[index]
	if not step then
		self:finish()
		return
	end
	local function next_step(delay)
		Timer.SetTimeout(function()
			self:run_step(index + 1)
		end, delay or STEP_GAP_MS)
	end

	if step.kind == "wait" then
		next_step(step.milliseconds)
	elseif step.kind == "action" then
		local ok, err = xpcall(step.fn, debug.traceback)
		if not ok then
			self:record("setup action #" .. index, false, err)
		end
		next_step()
	elseif step.kind == "test" then
		local ok, err = xpcall(step.fn, debug.traceback)
		self:record(step.name, ok, err)
		next_step()
	else
		local settled = false
		local timeout_id
		local function done(reason)
			if settled then
				return
			end
			settled = true
			Timer.ClearTimeout(timeout_id)
			self:record(step.name, reason == nil, reason)
			next_step()
		end
		timeout_id = Timer.SetTimeout(function()
			done(string.format("timed out after %d ms", step.timeout_ms))
		end, step.timeout_ms)
		local ok, err = xpcall(step.fn, debug.traceback, done)
		if not ok then
			done(err)
		end
	end
end

--- Starts the suite once the server has started.
function Suite:Run()
	Server.Subscribe("Start", function()
		self:run_step(1)
	end)
end

Package.Export("FoundationTest", FoundationTest)
