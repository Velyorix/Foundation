local context = Foundation.Register(Package, { api = Foundation.API_VERSION })

local suite = FoundationTest.Suite("core-scheduler")

suite:Async("NextTick runs after the current call, on a later tick", 2000, function(done)
	local ran = false
	context:NextTick(function()
		ran = true
		done()
	end)
	if ran then
		done("NextTick ran synchronously")
	end
end)

suite:Async("Delay waits for the requested time", 2000, function(done)
	local started = Server.GetTime()
	context:Delay(200, function()
		local elapsed = Server.GetTime() - started
		if elapsed < 180 then
			done("fired after " .. elapsed .. " ms")
		else
			done()
		end
	end)
end)

suite:Async("Repeat runs until its callback returns false", 3000, function(done)
	local runs = 0
	local task
	task = context:Repeat(50, function()
		runs = runs + 1
		if runs == 3 then
			context:Delay(200, function()
				if task:GetState() == "completed" and runs == 3 then
					done()
				else
					done("state " .. task:GetState() .. " after " .. runs .. " runs")
				end
			end)
			return false
		end
	end)
end)

suite:Async("a repeating task stops after consecutive failures", 3000, function(done)
	local task = context:Repeat(30, function()
		error("scheduled failure")
	end, { max_failures = 2 })
	context:Delay(500, function()
		if task:GetState() == "failed" then
			done()
		else
			done("state " .. task:GetState())
		end
	end)
end)

local ticks_at_unload
suite:Do(function()
	ticks_at_unload = SchedulerFixture.ticks
	Server.UnloadPackage("foundation-scheduler-fixture")
end)
suite:Wait(400)

suite:Test("tasks of an unloaded package stop", function()
	FoundationTest.True(ticks_at_unload > 0, "fixture task never ran")
	FoundationTest.True(SchedulerFixture.ticks <= ticks_at_unload + 1, "task kept running: " .. SchedulerFixture.ticks)
end)

suite:Run()
