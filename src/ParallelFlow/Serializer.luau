--!strict
local lib = {}
local TypeCodecs = require(script.Parent.TypeCodecs)

-- binary serializer for cross-actor data

local T_NUM   = 1
local T_BOOL  = 2
local T_STR   = 3
local T_V3    = 4
local T_CF    = 5
local T_ARR   = 6
local T_NIL   = 7
local T_INT   = 8
local T_MAP   = 9
local T_ANUM  = 10
local T_AV3   = 11
local T_BUF   = 12
local T_ACF   = 13
local T_SMAP  = 14

-- Each encode uses its own state (buf/size/pos) so concurrent or re-entrant
-- encodes never corrupt a shared buffer. States are recycled via a small
-- free-list to keep buffer reuse (no per-call allocation on the hot path).
type EncState = { buf: buffer, size: number, pos: number }
local freeStates: {EncState} = {}

local function acquire(): EncState
	local st = table.remove(freeStates)
	if st then
		st.pos = 0
		return st
	end
	return { buf = buffer.create(4096), size = 4096, pos = 0 }
end

local function release(st: EncState)
	if #freeStates < 8 then -- cap pooled buffers
		freeStates[#freeStates + 1] = st
	end
end

-- fast lookup for centralized codecs
local registry = TypeCodecs._getRegistry()
local typeMap: {[string]: {id: number, stride: number, encode: any, decode: any}} = {}

-- map legacy IDs to their codecs
typeMap["Vector3"] = {id = T_V3, stride = 12, encode = registry.Vector3.encode, decode = registry.Vector3.decode}
typeMap["CFrame"] = {id = T_CF, stride = 48, encode = registry.CFrame.encode, decode = registry.CFrame.decode}

-- cache commonly used locals
local encodeV3 = typeMap.Vector3.encode
local encodeCF = typeMap.CFrame.encode

-- populate the rest of the codecs with generic IDs (starting from 50 to avoid any overlap)
local nextId = 50
for name, codec in registry do
	if name == "Vector3" or name == "CFrame" then continue end
	typeMap[name] = {
		id = nextId,
		stride = codec.stride,
		encode = codec.encode,
		decode = codec.decode
	}
	nextId += 1
end

-- reverse lookup for decoding
local idToCodec = {}
for name, info in typeMap do idToCodec[info.id] = info end

-- make sure the encode state has enough space
local function grow(st, n)
	if st.pos + n > st.size then
		local new = math.max(math.floor(st.size * 1.5), st.pos + n)
		local nb = buffer.create(new)
		buffer.copy(nb, 0, st.buf, 0, st.pos)
		st.buf, st.size = nb, new
	end
end

-- write any value into the encode state's buffer
local function write(st, v)
	local t = type(v)

	if v == nil then
		grow(st, 1)
		buffer.writeu8(st.buf, st.pos, T_NIL)
		st.pos += 1
	elseif t == "boolean" then
		grow(st, 2)
		buffer.writeu8(st.buf, st.pos, T_BOOL)
		buffer.writeu8(st.buf, st.pos + 1, v and 1 or 0)
		st.pos += 2
	elseif t == "number" then
		if v == math.floor(v) and v >= -2147483648 and v <= 2147483647 then
			grow(st, 5)
			buffer.writeu8(st.buf, st.pos, T_INT)
			buffer.writei32(st.buf, st.pos + 1, v)
			st.pos += 5
		else
			grow(st, 9)
			buffer.writeu8(st.buf, st.pos, T_NUM)
			buffer.writef64(st.buf, st.pos + 1, v)
			st.pos += 9
		end
	elseif t == "string" then
		local len = #v
		grow(st, 5 + len)
		buffer.writeu8(st.buf, st.pos, T_STR)
		buffer.writeu32(st.buf, st.pos + 1, len)
		buffer.writestring(st.buf, st.pos + 5, v)
		st.pos += 5 + len
	elseif t == "table" then
		local n = #v
		if n > 0 or next(v) == nil then
			if n > 8 then
				local first = v[1]
				if type(first) == "number" then
					grow(st, 5 + n * 8)
					buffer.writeu8(st.buf, st.pos, T_ANUM)
					buffer.writeu32(st.buf, st.pos + 1, n)
					st.pos += 5
					for i = 1, n do buffer.writef64(st.buf, st.pos, v[i]); st.pos += 8 end
					return
				elseif typeof(first) == "Vector3" then
					grow(st, 5 + n * 12)
					buffer.writeu8(st.buf, st.pos, T_AV3)
					buffer.writeu32(st.buf, st.pos + 1, n)
					st.pos += 5
					for i = 1, n do encodeV3(st.buf, st.pos, v[i]); st.pos += 12 end
					return
				elseif typeof(first) == "CFrame" then
					grow(st, 5 + n * 48)
					buffer.writeu8(st.buf, st.pos, T_ACF)
					buffer.writeu32(st.buf, st.pos + 1, n)
					st.pos += 5
					for i = 1, n do encodeCF(st.buf, st.pos, v[i]); st.pos += 48 end
					return
				end
			end
			grow(st, 5)
			buffer.writeu8(st.buf, st.pos, T_ARR)
			buffer.writeu32(st.buf, st.pos + 1, n)
			st.pos += 5
			for i = 1, n do write(st, v[i]) end
		else
			grow(st, 5)
			buffer.writeu8(st.buf, st.pos, T_MAP)
			local count = 0; for _ in v do count += 1 end
			buffer.writeu32(st.buf, st.pos + 1, count); st.pos += 5
			for k, val in v do write(st, k); write(st, val) end
		end
	elseif typeof(v) == "buffer" then
		local len = buffer.len(v)
		grow(st, 5 + len)
		buffer.writeu8(st.buf, st.pos, T_BUF)
		buffer.writeu32(st.buf, st.pos + 1, len)
		buffer.copy(st.buf, st.pos + 5, v, 0, len)
		st.pos += 5 + len
	else
		-- roblox type centralization
		local typeName = typeof(v)
		local info = typeMap[typeName]
		if info then
			local stride = info.stride
			if stride > 0 then
				grow(st, 1 + stride)
				buffer.writeu8(st.buf, st.pos, info.id)
				info.encode(st.buf, st.pos + 1, v)
				st.pos += 1 + stride
			else
				-- variable length (sequences)
				grow(st, 1024)
				buffer.writeu8(st.buf, st.pos, info.id)
				local startPos = st.pos + 1
				info.encode(st.buf, startPos, v)
				if typeName == "ColorSequence" then
					st.pos = startPos + 1 + (#(v :: any).Keypoints * 16)
				elseif typeName == "NumberSequence" then
					st.pos = startPos + 1 + (#(v :: any).Keypoints * 12)
				else
					st.pos = startPos + 1 -- fallback for empty or unknown var-len
				end
			end
		else
			warn("unsupported type: " .. typeName)
			grow(st, 1); buffer.writeu8(st.buf, st.pos, T_NIL); st.pos += 1
		end
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
	elseif id == T_BUF then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = buffer.create(n); buffer.copy(res, 0, buf, offset, n)
		return res, offset + n
	elseif id == T_AV3 then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = table.create(n)
		local decV3 = registry.Vector3.decode
		for i = 1, n do res[i] = decV3(buf, offset); offset += 12 end
		return res, offset
	elseif id == T_ACF then
		local n = buffer.readu32(buf, offset); offset += 4
		local res = table.create(n)
		local decCF = registry.CFrame.decode
		for i = 1, n do res[i] = decCF(buf, offset); offset += 48 end
		return res, offset
	elseif id == T_SMAP then
		local n = buffer.readu32(buf, offset)
		local keyCount = buffer.readu8(buf, offset + 4)
		offset += 5
		local keys = table.create(keyCount)
		for i = 1, keyCount do
			local key; key, offset = read(buf, offset)
			keys[i] = key
		end
		local res = table.create(n)
		for i = 1, n do
			local item = {}
			for j = 1, keyCount do
				local val; val, offset = read(buf, offset)
				item[keys[j]] = val
			end
			res[i] = item
		end
		return res, offset
	else
		-- centralized numeric ID lookup
		local info = idToCodec[id]
		if info then
			local res = info.decode(buf, offset)
			local stride = info.stride
			if stride > 0 then
				offset += stride
			else
				-- variable length offset reconstruction
				local count = buffer.readu8(buf, offset)
				if info.id == typeMap.ColorSequence.id then
					offset += 1 + count * 16
				elseif info.id == typeMap.NumberSequence.id then
					offset += 1 + count * 12
				else
					offset += 1
				end
			end
			return res, offset
		end
	end

	warn("unknown type id: " .. id)
	return nil, offset
end

function lib.encode(v, startIdx, endIdx)
	local st = acquire()
	if startIdx and endIdx and type(v) == "table" then
		local n = endIdx - startIdx + 1

		-- schema compression detection
		local first = v[startIdx]
		if type(first) == "table" and next(first) ~= nil and first[1] == nil then
			local keys = {}
			local keyCount = 0
			for k in first do
				table.insert(keys, k)
				keyCount += 1
			end

			if keyCount < 256 then
				local homogeneous = true
				for i = startIdx + 1, endIdx do
					local item = v[i]
					if type(item) ~= "table" then homogeneous = false; break end
					local count = 0
					for k in item do
						if first[k] == nil then homogeneous = false; break end
						count += 1
					end
					if count ~= keyCount then homogeneous = false; break end
				end

				if homogeneous then
					grow(st, 6)
					buffer.writeu8(st.buf, st.pos, T_SMAP)
					buffer.writeu32(st.buf, st.pos + 1, n)
					buffer.writeu8(st.buf, st.pos + 5, keyCount)
					st.pos += 6
					for _, k in keys do write(st, k) end
					for i = startIdx, endIdx do
						local item = v[i]
						for _, k in keys do write(st, item[k]) end
					end
					local res = buffer.create(st.pos); buffer.copy(res, 0, st.buf, 0, st.pos)
					release(st)
					return res
				end
			end
		end

		grow(st, 5); buffer.writeu8(st.buf, st.pos, T_ARR); buffer.writeu32(st.buf, st.pos + 1, n); st.pos += 5
		for i = startIdx, endIdx do write(st, v[i]) end
	else
		write(st, v)
	end
	local res = buffer.create(st.pos); buffer.copy(res, 0, st.buf, 0, st.pos)
	release(st)
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
		encodeV3(res, off, v)
	end
	return res
end

function lib.estimateSize(v)
	local t = type(v)
	if t == "number" then return 9
	elseif t == "boolean" then return 2
	elseif t == "string" then return 5 + #v
	elseif t == "table" then
		local s = 5; for k, val in v do s += lib.estimateSize(k) + lib.estimateSize(val) end
		return s
	elseif typeof(v) == "buffer" then return 5 + buffer.len(v)
	else
		local info = typeMap[typeof(v)]
		if info then
			if info.stride > 0 then return 1 + info.stride end
			if info.id == typeMap.ColorSequence.id then return 2 + #(v :: any).Keypoints * 16 end
			if info.id == typeMap.NumberSequence.id then return 2 + #(v :: any).Keypoints * 12 end
		end
	end
	return 1
end

return lib
