local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local lines = {}
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(level, line)
			lines[#lines + 1] = { level = level, line = line }
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
	})
	runtime:Start()
	local natives = {}
	local function register(id, manifest)
		local handlers = {}
		local native = {
			GetName = function()
				return id
			end,
			GetVersion = function()
				return "2.1.0"
			end,
			Subscribe = function(event, callback)
				handlers[event] = callback
				return callback
			end,
		}
		function native.fire(event)
			handlers[event]()
		end
		natives[id] = native
		local context = runtime.packages:Register(native, manifest or { api = "0.1" })
		return context, native
	end
	return runtime, register, lines
end

describe("Core events", function()
	local runtime, register, lines, watcher, seen

	before_each(function()
		runtime, register, lines = setup()
		watcher = register("watcher")
		seen = {}
		for _, name in ipairs({ "package_ready", "package_failed", "package_disabled" }) do
			watcher:Listen("foundation:" .. name, function(event)
				seen[#seen + 1] = { name = event:GetName(), data = event:GetData() }
			end)
		end
	end)

	it("announces a package that becomes ready", function()
		local _, native = register("shop")
		native.fire("Load")
		expect.same(seen, {
			{ name = "foundation:package_ready", data = { package = "shop", version = "2.1.0" } },
		})
	end)

	it("announces a failed package with its reason", function()
		local shop, native = register("shop")
		shop:OnReady(function()
			error("database unavailable")
		end)
		native.fire("Load")
		expect.equal(#seen, 1)
		expect.equal(seen[1].name, "foundation:package_failed")
		expect.equal(seen[1].data.package, "shop")
		expect.equal(seen[1].data.message, "a ready hook of 'shop' failed")
	end)

	it("announces disabled packages with a stable reason, dependents first", function()
		register("economy")
		register("shop", { api = "0.1", depends = { "economy" } })
		runtime.packages:Disable("economy", "unload")
		expect.same(seen, {
			{
				name = "foundation:package_disabled",
				data = { package = "shop", version = "2.1.0", reason = "dependency_disabled" },
			},
			{
				name = "foundation:package_disabled",
				data = { package = "economy", version = "2.1.0", reason = "unload" },
			},
		})
	end)

	it("does not let packages emit, redefine or cancel Foundation's events", function()
		expect.raises(function()
			watcher:Emit("foundation:package_ready", { package = "fake" })
		end, "must be in the 'watcher' namespace")
		expect.raises(function()
			watcher:DefineEvent("foundation:package_ready")
		end, "must be in the 'watcher' namespace")
		watcher:Listen("foundation:package_ready", function(event)
			event:Cancel()
		end)
		local _, native = register("shop")
		native.fire("Load")
		expect.contains(lines[#lines].line, "'foundation:package_ready' cannot be cancelled")
	end)

	it("keeps going when a listener fails", function()
		watcher:Listen("foundation:package_ready", function()
			error("listener failure")
		end, { priority = "lowest" })
		local shop, native = register("shop")
		native.fire("Load")
		expect.equal(shop:GetState(), "ready")
		expect.equal(#seen, 1)
	end)
end)
