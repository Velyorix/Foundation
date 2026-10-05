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
	local function register(id)
		local native = {
			GetName = function()
				return id
			end,
			Subscribe = function() end,
		}
		return runtime.packages:Register(native, { api = "0.1" })
	end
	return runtime, register, lines
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.line
	end
	return table.concat(parts, "\n")
end

local function line_of(message)
	return tonumber(tostring(message):match("events_spec%.lua:(%d+):"))
end

describe("Events", function()
	local runtime, register, lines, shop, bank, S

	before_each(function()
		runtime, register, lines = setup()
		shop = register("shop")
		bank = register("bank")
		S = runtime.schema
	end)

	local function define_purchase()
		return shop:DefineEvent("purchase", {
			fields = {
				player = S:String({ min = 1 }),
				item = S:String({ min = 1 }),
				price = S:Integer({ min = 0 }),
				reason = S:Optional(S:String(), "none"),
			},
			mutable = { "price" },
			cancellable = true,
		})
	end

	describe("definitions", function()
		it("puts the event in the package namespace", function()
			expect.equal(define_purchase(), "shop:purchase")
			expect.equal(shop:DefineEvent("shop:refund"), "shop:refund")
			expect.equal(runtime.events:Snapshot().defined, 2)
		end)

		it("rejects malformed definitions", function()
			expect.raises(function()
				shop:DefineEvent("bank:deposit")
			end, "must be in the 'shop' namespace")
			expect.raises(function()
				shop:DefineEvent("purchase", { cancelable = true })
			end, "unknown field 'cancelable'")
			expect.raises(function()
				shop:DefineEvent("purchase", { fields = { price = "integer" } })
			end, "'definition.fields.price' must be schema (got string)")
			expect.raises(function()
				shop:DefineEvent("purchase", { fields = { price = S:Integer() }, mutable = { "cost" } })
			end, "'cost' is not one of the fields")
			expect.raises(function()
				shop:DefineEvent("purchase", { cancellable = "yes" })
			end, "'definition.cancellable' must be boolean? (got string)")
		end)

		it("refuses a second definition of the same event", function()
			define_purchase()
			expect.raises(define_purchase, "'shop:purchase' is already defined by shop")
		end)

		it("reports errors at the package's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				shop:DefineEvent("Bad Name")
			end)
			expect.falsy(ok)
			expect.equal(line_of(message), expected_line)
			ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				bank:Listen("shop:missing", function() end)
			end)
			expect.falsy(ok)
			expect.equal(line_of(message), expected_line)
		end)
	end)

	describe("dispatch", function()
		before_each(define_purchase)

		it("validates the payload, applies defaults and only lets the owner emit", function()
			local event = shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.equal(event:GetName(), "shop:purchase")
			expect.equal(event:Get("reason"), "none")
			expect.raises(function()
				shop:Emit("purchase", { player = "alex", item = "apple", price = -1 })
			end, "does not match the definition of 'shop:purchase': $.price: must be at least 0")
			expect.raises(function()
				bank:Emit("shop:purchase", { player = "alex", item = "apple", price = 1 })
			end, "must be in the 'bank' namespace")
			expect.raises(function()
				shop:Emit("unknown")
			end, "'shop:unknown' is not a defined event")
		end)

		it("calls listeners by priority, then in registration order", function()
			local order = {}
			local function listener(name)
				return function()
					order[#order + 1] = name
				end
			end
			bank:Listen("shop:purchase", listener("monitor"), { priority = "monitor" })
			bank:Listen("shop:purchase", listener("normal-1"))
			shop:Listen("purchase", listener("highest"), { priority = "highest" })
			bank:Listen("shop:purchase", listener("lowest"), { priority = "lowest" })
			shop:Listen("purchase", listener("normal-2"), { priority = "normal" })
			shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.same(order, { "lowest", "normal-1", "normal-2", "highest", "monitor" })
		end)

		it("lets listeners change mutable fields and cancel", function()
			bank:Listen("shop:purchase", function(event)
				event:Set("price", event:Get("price") * 2)
			end)
			bank:Listen("shop:purchase", function(event)
				if event:Get("price") > 8 then
					event:Cancel()
				end
			end, { priority = "high" })
			local event = shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.equal(event:Get("price"), 10)
			expect.truthy(event:IsCancelled())
			expect.same(event:GetData(), { player = "alex", item = "apple", price = 10, reason = "none" })
		end)

		it("skips cancelled events for listeners that ignore them, and allows uncancelling", function()
			local seen = {}
			bank:Listen("shop:purchase", function(event)
				event:SetCancelled(true)
			end, { priority = "low" })
			bank:Listen("shop:purchase", function()
				seen[#seen + 1] = "ignored"
			end, { ignore_cancelled = true })
			bank:Listen("shop:purchase", function(event)
				seen[#seen + 1] = "uncancel"
				event:SetCancelled(false)
			end, { priority = "high" })
			bank:Listen("shop:purchase", function(event)
				seen[#seen + 1] = "highest:" .. tostring(event:IsCancelled())
			end, { priority = "highest", ignore_cancelled = true })
			shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.same(seen, { "uncancel", "highest:false" })
		end)

		it("refuses invalid changes inside listeners and keeps dispatching", function()
			local reached = false
			bank:Listen("shop:purchase", function(event)
				event:Set("item", "pear")
			end)
			bank:Listen("shop:purchase", function(event)
				event:Set("price", -3)
			end)
			bank:Listen("shop:purchase", function(event)
				event:Set("price", 1)
			end, { priority = "monitor" })
			bank:Listen("shop:purchase", function()
				reached = true
			end, { priority = "monitor" })
			local event = shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.truthy(reached)
			expect.equal(event:Get("item"), "apple")
			expect.equal(event:Get("price"), 5)
			local output = text(lines)
			expect.contains(output, "listeners cannot change 'item' of 'shop:purchase'")
			expect.contains(output, "$: must be at least 0")
			expect.contains(output, "monitor listeners cannot change the event")
			expect.contains(output, "event_listener callback of bank failed")
		end)

		it("refuses cancelling events that are not cancellable", function()
			shop:DefineEvent("opened")
			bank:Listen("shop:opened", function(event)
				event:Cancel()
			end)
			local event = shop:Emit("opened")
			expect.falsy(event:IsCancelled())
			expect.contains(text(lines), "'shop:opened' cannot be cancelled")
		end)

		it("freezes the event once dispatch is over", function()
			local event = shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.raises(function()
				event:Set("price", 1)
			end, "can only be changed by its listeners while it is dispatched")
			expect.raises(function()
				event:Get("color")
			end, "'color' is not a field of 'shop:purchase'")
		end)

		it("returns copies of table fields", function()
			shop:DefineEvent("basket", { fields = { items = S:List(S:String()) } })
			local event = shop:Emit("basket", { items = { "apple" } })
			event:Get("items")[1] = "changed"
			expect.equal(event:Get("items")[1], "apple")
		end)

		it("applies unsubscriptions made during dispatch, and not new listeners", function()
			local seen = {}
			local later
			bank:Listen("shop:purchase", function()
				seen[#seen + 1] = "first"
				later:Release()
				bank:Listen("shop:purchase", function()
					seen[#seen + 1] = "added"
				end)
			end, { priority = "low" })
			later = bank:Listen("shop:purchase", function()
				seen[#seen + 1] = "later"
			end)
			shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.same(seen, { "first" })
		end)

		it("stops runaway nesting", function()
			local depth = 0
			shop:DefineEvent("loop")
			shop:Listen("loop", function()
				depth = depth + 1
				shop:Emit("loop")
			end)
			shop:Emit("loop")
			expect.equal(depth, 16)
			expect.contains(text(lines), "events are nested more than 16 levels deep")
		end)
	end)

	describe("listeners", function()
		before_each(define_purchase)

		it("requires a defined event and valid options", function()
			expect.raises(function()
				bank:Listen("shop:missing", function() end)
			end, "'shop:missing' is not a defined event")
			expect.raises(function()
				bank:Listen("shop:purchase", function() end, { priority = "urgent" })
			end, "expected one of lowest, low, normal, high, highest, monitor")
			expect.raises(function()
				bank:Listen("shop:purchase", function() end, { once = true })
			end, "unknown field 'once'")
		end)

		it("refuses the same function twice for one package", function()
			local function on_purchase() end
			bank:Listen("shop:purchase", on_purchase)
			expect.raises(function()
				bank:Listen("shop:purchase", on_purchase)
			end, "this function already listens to 'shop:purchase'")
			expect.no_error(function()
				shop:Listen("purchase", on_purchase)
			end)
		end)

		it("can be removed with the returned handle", function()
			local calls = 0
			local handle = bank:Listen("shop:purchase", function()
				calls = calls + 1
			end)
			expect.truthy(handle:Release())
			expect.falsy(handle:IsActive())
			shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.equal(calls, 0)
		end)

		it("are removed when their package is disabled", function()
			local calls = 0
			bank:Listen("shop:purchase", function()
				calls = calls + 1
			end)
			runtime.packages:Disable("bank", "unload")
			shop:Emit("purchase", { player = "alex", item = "apple", price = 5 })
			expect.equal(calls, 0)
			expect.equal(runtime.events:Snapshot().events["shop:purchase"].listeners, 0)
			expect.equal(runtime.ownership:Count("bank"), 0)
		end)

		it("are removed with the event when the defining package is disabled", function()
			local handle = bank:Listen("shop:purchase", function() end)
			runtime.packages:Disable("shop", "unload")
			expect.falsy(handle:IsActive())
			expect.equal(runtime.ownership:Count("bank"), 0)
			expect.equal(runtime.events:Snapshot().defined, 0)
			expect.raises(function()
				bank:Listen("shop:purchase", function() end)
			end, "'shop:purchase' is not a defined event")
		end)
	end)
end)
