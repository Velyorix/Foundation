local expect = {}

local function describe_value(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function fail(message)
	error(message, 3)
end

local function prefixed(message, text)
	return message and (message .. ": " .. text) or text
end

local function deep_equal(a, b, path, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false, path, a, b
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for key, value in pairs(a) do
		local ok, failed_path, left, right = deep_equal(value, b[key], path .. "[" .. describe_value(key) .. "]", seen)
		if not ok then
			return false, failed_path, left, right
		end
	end
	for key, value in pairs(b) do
		if a[key] == nil then
			return false, path .. "[" .. describe_value(key) .. "]", nil, value
		end
	end
	return true
end

function expect.equal(actual, expected, message)
	if actual ~= expected then
		fail(prefixed(message, string.format("expected %s, got %s", describe_value(expected), describe_value(actual))))
	end
end

function expect.not_equal(actual, unexpected, message)
	if actual == unexpected then
		fail(prefixed(message, string.format("did not expect %s", describe_value(unexpected))))
	end
end

function expect.same(actual, expected, message)
	local ok, path, left, right = deep_equal(actual, expected, "value")
	if not ok then
		fail(
			prefixed(
				message,
				string.format("mismatch at %s: expected %s, got %s", path, describe_value(right), describe_value(left))
			)
		)
	end
end

function expect.truthy(value, message)
	if not value then
		fail(message or ("expected a truthy value, got " .. describe_value(value)))
	end
end

function expect.falsy(value, message)
	if value then
		fail(message or ("expected a falsy value, got " .. describe_value(value)))
	end
end

function expect.is_nil(value, message)
	if value ~= nil then
		fail(message or ("expected nil, got " .. describe_value(value)))
	end
end

function expect.type(value, type_name, message)
	if type(value) ~= type_name then
		fail(prefixed(message, string.format("expected type %s, got %s", type_name, type(value))))
	end
end

function expect.contains(text, fragment, message)
	if type(text) ~= "string" or not text:find(fragment, 1, true) then
		fail(
			prefixed(
				message,
				string.format("expected %s to contain %s", describe_value(text), describe_value(fragment))
			)
		)
	end
end

function expect.raises(fn, fragment, message)
	local ok, err = pcall(fn)
	if ok then
		fail(message or "expected an error, none was raised")
	end
	if fragment ~= nil then
		local text = tostring(err)
		if not text:find(fragment, 1, true) then
			fail(
				prefixed(
					message,
					string.format(
						"expected error containing %s, got %s",
						describe_value(fragment),
						describe_value(text)
					)
				)
			)
		end
	end
	return err
end

function expect.no_error(fn, message)
	local ok, err = pcall(fn)
	if not ok then
		fail(prefixed(message, string.format("unexpected error: %s", tostring(err))))
	end
end

return expect
