-- binary serializer for cross-actor data
local lib = {}

local T_NUM  = 1
local T_BOOL = 2
local T_STR  = 3
local T_V3   = 4
local T_CF   = 5
local T_ARR  = 6
local T_NIL  = 7
local T_INT  = 8
local T_MAP  = 9
local T_ANUM = 10
local T_AV3  = 11
local T_BUF  = 12

local pool = buffer.create(4096)
local size = 4096
local pos = 0

-- make sure we have enough space in our buffer
local function grow(n)
	if pos + n > size then
		local new = math.max(size * 2, pos + n)
		local nb = buffer.create(new)
		buffer.copy(nb, 0, pool, 0, pos)
		pool, size = nb, new
	end
end

-- write any value to the internal buffer
local function write(v)
	local t = type(v)

	if v == nil then
		grow(1)
		buffer.writeu8(pool, pos, T_NIL)
		pos += 1
	elseif t == "boolean" then
		grow(2)
		buffer.writeu8(pool, pos, T_BOOL)
		buffer.writeu8(pool, pos + 1, v and 1 or 0)
		pos += 2
	elseif t == "number" then
		if v == math.floor(v) and v >= -2147483648 and v <= 2147483647 then
			grow(5)
			buffer.writeu8(pool, pos, T_INT)
			buffer.writei32(pool, pos + 1, v)
			pos += 5
		else
			grow(9)
			buffer.writeu8(pool, pos, T_NUM)
			buffer.writef64(pool, pos + 1, v)
			pos += 9
		end
	elseif t == "string" then
		local len = #v
		grow(5 + len)
		buffer.writeu8(pool, pos, T_STR)
		buffer.writeu32(pool, pos + 1, len)
		buffer.writestring(pool, pos + 5, v)
		pos += 5 + len
	elseif typeof(v) == "Vector3" then
		grow(13)
		buffer.writeu8(pool, pos, T_V3)
		buffer.writef32(pool, pos + 1, v.X)
		buffer.writef32(pool, pos + 5, v.Y)
		buffer.writef32(pool, pos + 9, v.Z)
		pos += 13
	elseif typeof(v) == "buffer" then
		local len = buffer.len(v)
		grow(5 + len)
		buffer.writeu8(pool, pos, T_BUF)
		buffer.writeu32(pool, pos + 1, len)
		buffer.copy(pool, pos + 5, v, 0, len)
		pos += 5 + len
	elseif typeof(v) == "CFrame" then
		grow(49)
		buffer.writeu8(pool, pos, T_CF)
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
		buffer.writef32(pool, pos + 1, x); buffer.writef32(pool, pos + 5, y); buffer.writef32(pool, pos + 9, z)
		buffer.writef32(pool, pos + 13, r00); buffer.writef32(pool, pos + 17, r01); buffer.writef32(pool, pos + 21, r02)
		buffer.writef32(pool, pos + 25, r10); buffer.writef32(pool, pos + 29, r11); buffer.writef32(pool, pos + 33, r12)
		buffer.writef32(pool, pos + 37, r20); buffer.writef32(pool, pos + 41, r21); buffer.writef32(pool, pos + 45, r22)
		pos += 49
	elseif t == "table" then
		local n = #v
		if n > 0 or next(v) == nil then
			-- check if we can use fast arrays
			if n > 8 then
				local first = v[1]
				if type(first) == "number" then
					grow(5 + n * 8)
					buffer.writeu8(pool, pos, T_ANUM)
					buffer.writeu32(pool, pos + 1, n)
					pos += 5
					for i = 1, n do buffer.writef64(pool, pos, v[i]); pos += 8 end
					return
				elseif typeof(first) == "Vector3" then
					grow(5 + n * 12)
					buffer.writeu8(pool, pos, T_AV3)
					buffer.writeu32(pool, pos + 1, n)
					pos += 5
					for i = 1, n do
						local vec = v[i]
						buffer.writef32(pool, pos, vec.X); buffer.writef32(pool, pos + 4, vec.Y); buffer.writef32(pool, pos + 8, vec.Z)
						pos += 12
					end
					return
				end
			end
			-- generic array
			grow(5)
			buffer.writeu8(pool, pos, T_ARR)
			buffer.writeu32(pool, pos + 1, n)
			pos += 5
			for i = 1, n do write(v[i]) end
		else
			-- dictionary
			grow(5)
			buffer.writeu8(pool, pos, T_MAP)
			local count = 0; for _ in v do count += 1 end
			buffer.writeu32(pool, pos + 1, count); pos += 5
			for k, val in v do write(k); write(val) end
		end
	else
		warn("unsupported type: " .. t)
		grow(1); buffer.writeu8(pool, pos, T_NIL); pos += 1
	end
end

-- read value from buffer
local function read(buf, offset)
	local id = buffer.readu8(buf, offset)
	offset += 1

	if id == T_NIL then return nil, offset
	elseif id == T_BOOL then return buffer.readu8(buf, offset) == 1, offset + 1
	elseif id == T_INT then return buffer.readi32(buf, offset), offset + 4
	elseif id == T_NUM then return buffer.readf64(buf, offset), offset + 8
	elseif id == T_STR then
		local len = buffer.readu32(buf, offset)
		return buffer.readstring(buf, offset + 4, len), offset + 4 + len
	elseif id == T_V3 then
		return Vector3.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8)), offset + 12
	elseif id == T_CF then
		local x, y, z = buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8)
		local r00 = buffer.readf32(buf, offset + 12); local r01 = buffer.readf32(buf, offset + 16); local r02 = buffer.readf32(buf, offset + 20)
		local r10 = buffer.readf32(buf, offset + 24); local r11 = buffer.readf32(buf, offset + 28); local r12 = buffer.readf32(buf, offset + 32)
		local r20 = buffer.readf32(buf, offset + 36); local r21 = buffer.readf32(buf, offset + 40); local r22 = buffer.readf32(buf, offset + 44)
		return CFrame.new(x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22), offset + 48
	elseif id == T_ARR then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = table.create(n)
		for i = 1, n do local v; v, offset = read(buf, offset); res[i] = v end
		return res, offset
	elseif id == T_MAP then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = {}
		for i = 1, n do local k, v; k, offset = read(buf, offset); v, offset = read(buf, offset); res[k] = v end
		return res, offset
	elseif id == T_ANUM then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = table.create(n)
		for i = 1, n do res[i] = buffer.readf64(buf, offset); offset += 8 end
		return res, offset
	elseif id == T_AV3 then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = table.create(n)
		for i = 1, n do
			res[i] = Vector3.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8))
			offset += 12
		end
		return res, offset
	elseif id == T_BUF then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = buffer.create(n); buffer.copy(res, 0, buf, offset, n)
		return res, offset + n
	end
	
	warn("unknown type id: " .. id)
	return nil, offset
end

function lib.encode(v, startIdx, endIdx)
	pos = 0
	if startIdx and endIdx and type(v) == "table" then
		local n = endIdx - startIdx + 1
		grow(5); buffer.writeu8(pool, pos, T_ARR); buffer.writeu32(pool, pos + 1, n); pos += 5
		for i = startIdx, endIdx do write(v[i]) end
	else
		write(v)
	end
	local res = buffer.create(pos); buffer.copy(res, 0, pool, 0, pos)
	return res
end

function lib.decode(buf)
	local v = read(buf, 0)
	return v
end

function lib.packNumbers(data)
	local n = #data
	local res = buffer.create(n * 8)
	for i = 1, n do buffer.writef64(res, (i-1)*8, data[i]) end
	return res
end

function lib.packVector3s(data)
	local n = #data
	local res = buffer.create(n * 12)
	for i = 1, n do
		local v = data[i]; local off = (i-1)*12
		buffer.writef32(res, off, v.X); buffer.writef32(res, off+4, v.Y); buffer.writef32(res, off+8, v.Z)
	end
	return res
end

return lib
