--!strict
local TypeCodecs = {}

local registry: {[string]: {
	stride: number,
	encode: (buf: buffer, offset: number, value: any) -> (),
	decode: (buf: buffer, offset: number) -> any,
}} = {}

function TypeCodecs.register(name: string, codec: {
	stride: number,
	encode: (buf: buffer, offset: number, value: any) -> (),
	decode: (buf: buffer, offset: number) -> any,
	})
	if not (codec.stride and codec.encode and codec.decode) then 
		error("missing codec parts for: " .. name)
	end

	if registry[name] then
		warn("type " .. name .. " already exists, overwriting")
	end
	registry[name] = codec
end

function TypeCodecs.get(name: string)
	local codec = registry[name]
	if not codec then 
		error("unknown type: " .. name .. " — did you register it?")
	end
	return codec
end

function TypeCodecs.has(name: string): boolean
	return registry[name] ~= nil
end

function TypeCodecs._getRegistry()
	return registry
end

TypeCodecs.register("Vector2", {
	stride = 8,
	encode = function(buf, offset, v: Vector2)
		buffer.writef32(buf, offset,     v.X)
		buffer.writef32(buf, offset + 4, v.Y)
	end,
	decode = function(buf, offset): Vector2
		return Vector2.new(
			buffer.readf32(buf, offset),
			buffer.readf32(buf, offset + 4)
		)
	end,
})

TypeCodecs.register("Vector2int16", {
	stride = 4,
	encode = function(buf, offset, v: Vector2int16)
		buffer.writei16(buf, offset,     v.X)
		buffer.writei16(buf, offset + 2, v.Y)
	end,
	decode = function(buf, offset): Vector2int16
		return Vector2int16.new(
			buffer.readi16(buf, offset),
			buffer.readi16(buf, offset + 2)
		)
	end,
})

TypeCodecs.register("Vector3", {
	stride = 12,
	encode = function(buf, offset, v: Vector3)
		buffer.writef32(buf, offset,     v.X)
		buffer.writef32(buf, offset + 4, v.Y)
		buffer.writef32(buf, offset + 8, v.Z)
	end,
	decode = function(buf, offset): Vector3
		return Vector3.new(
			buffer.readf32(buf, offset),
			buffer.readf32(buf, offset + 4),
			buffer.readf32(buf, offset + 8)
		)
	end,
})

TypeCodecs.register("Vector3int16", {
	stride = 6,
	encode = function(buf, offset, v: Vector3int16)
		buffer.writei16(buf, offset,     v.X)
		buffer.writei16(buf, offset + 2, v.Y)
		buffer.writei16(buf, offset + 4, v.Z)
	end,
	decode = function(buf, offset): Vector3int16
		return Vector3int16.new(
			buffer.readi16(buf, offset),
			buffer.readi16(buf, offset + 2),
			buffer.readi16(buf, offset + 4)
		)
	end,
})

TypeCodecs.register("CFrame", {
	stride = 48,
	encode = function(buf, offset, cf: CFrame)
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		buffer.writef32(buf, offset,      x)
		buffer.writef32(buf, offset +  4, y)
		buffer.writef32(buf, offset +  8, z)
		buffer.writef32(buf, offset + 12, r00)
		buffer.writef32(buf, offset + 16, r01)
		buffer.writef32(buf, offset + 20, r02)
		buffer.writef32(buf, offset + 24, r10)
		buffer.writef32(buf, offset + 28, r11)
		buffer.writef32(buf, offset + 32, r12)
		buffer.writef32(buf, offset + 36, r20)
		buffer.writef32(buf, offset + 40, r21)
		buffer.writef32(buf, offset + 44, r22)
	end,
	decode = function(buf, offset): CFrame
		return CFrame.new(
			buffer.readf32(buf, offset),
			buffer.readf32(buf, offset +  4),
			buffer.readf32(buf, offset +  8),
			buffer.readf32(buf, offset + 12),
			buffer.readf32(buf, offset + 16),
			buffer.readf32(buf, offset + 20),
			buffer.readf32(buf, offset + 24),
			buffer.readf32(buf, offset + 28),
			buffer.readf32(buf, offset + 32),
			buffer.readf32(buf, offset + 36),
			buffer.readf32(buf, offset + 40),
			buffer.readf32(buf, offset + 44)
		)
	end,
})

TypeCodecs.register("Color3", {
	stride = 12,
	encode = function(buf, offset, c: Color3)
		buffer.writef32(buf, offset,     c.R)
		buffer.writef32(buf, offset + 4, c.G)
		buffer.writef32(buf, offset + 8, c.B)
	end,
	decode = function(buf, offset): Color3
		return Color3.new(
			buffer.readf32(buf, offset),
			buffer.readf32(buf, offset + 4),
			buffer.readf32(buf, offset + 8)
		)
	end,
})

TypeCodecs.register("UDim", {
	stride = 8,
	encode = function(buf, offset, u: UDim)
		buffer.writef32(buf, offset,     u.Scale)
		buffer.writei32(buf, offset + 4, u.Offset)
	end,
	decode = function(buf, offset): UDim
		return UDim.new(
			buffer.readf32(buf, offset),
			buffer.readi32(buf, offset + 4)
		)
	end,
})

TypeCodecs.register("UDim2", {
	stride = 16,
	encode = function(buf, offset, u: UDim2)
		buffer.writef32(buf, offset,      u.X.Scale)
		buffer.writei32(buf, offset +  4, u.X.Offset)
		buffer.writef32(buf, offset +  8, u.Y.Scale)
		buffer.writei32(buf, offset + 12, u.Y.Offset)
	end,
	decode = function(buf, offset): UDim2
		return UDim2.new(
			buffer.readf32(buf, offset),
			buffer.readi32(buf, offset + 4),
			buffer.readf32(buf, offset + 8),
			buffer.readi32(buf, offset + 12)
		)
	end,
})

TypeCodecs.register("Rect", {
	stride = 16,
	encode = function(buf, offset, r: Rect)
		buffer.writef32(buf, offset,      r.Min.X)
		buffer.writef32(buf, offset +  4, r.Min.Y)
		buffer.writef32(buf, offset +  8, r.Max.X)
		buffer.writef32(buf, offset + 12, r.Max.Y)
	end,
	decode = function(buf, offset): Rect
		return Rect.new(
			buffer.readf32(buf, offset),
			buffer.readf32(buf, offset + 4),
			buffer.readf32(buf, offset + 8),
			buffer.readf32(buf, offset + 12)
		)
	end,
})

TypeCodecs.register("Ray", {
	stride = 24,
	encode = function(buf, offset, r: Ray)
		buffer.writef32(buf, offset,      r.Origin.X)
		buffer.writef32(buf, offset +  4, r.Origin.Y)
		buffer.writef32(buf, offset +  8, r.Origin.Z)
		buffer.writef32(buf, offset + 12, r.Direction.X)
		buffer.writef32(buf, offset + 16, r.Direction.Y)
		buffer.writef32(buf, offset + 20, r.Direction.Z)
	end,
	decode = function(buf, offset): Ray
		return Ray.new(
			Vector3.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8)),
			Vector3.new(buffer.readf32(buf, offset + 12), buffer.readf32(buf, offset + 16), buffer.readf32(buf, offset + 20))
		)
	end,
})

TypeCodecs.register("Region3", {
	stride = 48,
	encode = function(buf, offset, r: Region3)
		local min = r.CFrame.Position - r.Size * 0.5
		local max = r.CFrame.Position + r.Size * 0.5
		buffer.writef32(buf, offset,      min.X)
		buffer.writef32(buf, offset +  4, min.Y)
		buffer.writef32(buf, offset +  8, min.Z)
		buffer.writef32(buf, offset + 12, max.X)
		buffer.writef32(buf, offset + 16, max.Y)
		buffer.writef32(buf, offset + 20, max.Z)
	end,
	decode = function(buf, offset): Region3
		return Region3.new(
			Vector3.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8)),
			Vector3.new(buffer.readf32(buf, offset + 12), buffer.readf32(buf, offset + 16), buffer.readf32(buf, offset + 20))
		)
	end,
})

TypeCodecs.register("Region3int16", {
	stride = 12,
	encode = function(buf, offset, r: Region3int16)
		buffer.writei16(buf, offset,      r.Min.X)
		buffer.writei16(buf, offset +  2, r.Min.Y)
		buffer.writei16(buf, offset +  4, r.Min.Z)
		buffer.writei16(buf, offset +  6, r.Max.X)
		buffer.writei16(buf, offset +  8, r.Max.Y)
		buffer.writei16(buf, offset + 10, r.Max.Z)
	end,
	decode = function(buf, offset): Region3int16
		return Region3int16.new(
			Vector3int16.new(buffer.readi16(buf, offset), buffer.readi16(buf, offset + 2), buffer.readi16(buf, offset + 4)),
			Vector3int16.new(buffer.readi16(buf, offset + 6), buffer.readi16(buf, offset + 8), buffer.readi16(buf, offset + 10))
		)
	end,
})

TypeCodecs.register("NumberRange", {
	stride = 8,
	encode = function(buf, offset, n: NumberRange)
		buffer.writef32(buf, offset,     n.Min)
		buffer.writef32(buf, offset + 4, n.Max)
	end,
	decode = function(buf, offset): NumberRange
		return NumberRange.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4))
	end,
})

TypeCodecs.register("PhysicalProperties", {
	stride = 20,
	encode = function(buf, offset, p: PhysicalProperties)
		buffer.writef32(buf, offset,      p.Density)
		buffer.writef32(buf, offset +  4, p.Friction)
		buffer.writef32(buf, offset +  8, p.Elasticity)
		buffer.writef32(buf, offset + 12, p.FrictionWeight)
		buffer.writef32(buf, offset + 16, p.ElasticityWeight)
	end,
	decode = function(buf, offset): PhysicalProperties
		return PhysicalProperties.new(
			buffer.readf32(buf, offset),
			buffer.readf32(buf, offset + 4),
			buffer.readf32(buf, offset + 8),
			buffer.readf32(buf, offset + 12),
			buffer.readf32(buf, offset + 16)
		)
	end,
})

TypeCodecs.register("BrickColor", {
	stride = 4,
	encode = function(buf, offset, b: BrickColor)
		buffer.writeu32(buf, offset, b.Number)
	end,
	decode = function(buf, offset): BrickColor
		return BrickColor.new(buffer.readu32(buf, offset))
	end,
})

TypeCodecs.register("EnumItem", {
	stride = 8,
	encode = function(buf, offset, e: EnumItem)
		buffer.writeu32(buf, offset,     e.Value)
		buffer.writeu32(buf, offset + 4, 0)
	end,
	decode = function(buf, offset)
		return buffer.readu32(buf, offset)
	end,
})

TypeCodecs.register("Axes", {
	stride = 1,
	encode = function(buf, offset, a: Axes)
		local bits = 0
		if a.X then bits += 1 end
		if a.Y then bits += 2 end
		if a.Z then bits += 4 end
		buffer.writeu8(buf, offset, bits)
	end,
	decode = function(buf, offset): Axes
		local bits = buffer.readu8(buf, offset)
		local axes = {}
		if bits % 2 >= 1         then table.insert(axes, Enum.Axis.X) end
		if math.floor(bits/2) % 2 >= 1 then table.insert(axes, Enum.Axis.Y) end
		if math.floor(bits/4) % 2 >= 1 then table.insert(axes, Enum.Axis.Z) end
		return Axes.new(table.unpack(axes))
	end,
})

TypeCodecs.register("Faces", {
	stride = 1,
	encode = function(buf, offset, f: Faces)
		local bits = 0
		if f.Top    then bits += 1  end
		if f.Bottom then bits += 2  end
		if f.Left   then bits += 4  end
		if f.Right  then bits += 8  end
		if f.Front  then bits += 16 end
		if f.Back   then bits += 32 end
		buffer.writeu8(buf, offset, bits)
	end,
	decode = function(buf, offset): Faces
		local bits = buffer.readu8(buf, offset)
		local faces = {}
		local map = {{1, Enum.NormalId.Top}, {2, Enum.NormalId.Bottom}, {4, Enum.NormalId.Left}, {8, Enum.NormalId.Right}, {16, Enum.NormalId.Front}, {32, Enum.NormalId.Back}}
		for _, entry in map do
			if math.floor(bits / entry[1]) % 2 >= 1 then
				table.insert(faces, entry[2])
			end
		end
		return Faces.new(table.unpack(faces))
	end,
})

TypeCodecs.register("UniqueId", {
	stride = 16,
	encode = function(buf, offset, id)
		local str = tostring(id)
		for i = 0, 15 do
			local byte = tonumber(str:sub(i*2+1, i*2+2), 16) or 0
			buffer.writeu8(buf, offset + i, byte)
		end
	end,
	decode = function(buf, offset)
		local hex = ""
		for i = 0, 15 do hex ..= string.format("%02x", buffer.readu8(buf, offset + i)) end
		return hex
	end,
})

TypeCodecs.register("DateTime", {
	stride = 8,
	encode = function(buf, offset, d: DateTime)
		local ms = d.UnixTimestampMillis
		buffer.writeu32(buf, offset,     ms % 4294967296)
		buffer.writeu32(buf, offset + 4, math.floor(ms / 4294967296))
	end,
	decode = function(buf, offset): DateTime
		local lo = buffer.readu32(buf, offset)
		local hi = buffer.readu32(buf, offset + 4)
		return DateTime.fromUnixTimestampMillis(hi * 4294967296 + lo)
	end,
})

TypeCodecs.register("TweenInfo", {
	stride = 17,
	encode = function(buf, offset, t: TweenInfo)
		buffer.writef32(buf, offset,      t.Time)
		buffer.writeu8 (buf, offset +  4, t.EasingStyle.Value)
		buffer.writeu8 (buf, offset +  5, t.EasingDirection.Value)
		buffer.writei32(buf, offset +  6, t.RepeatCount)
		buffer.writeu8 (buf, offset + 10, t.Reverses and 1 or 0)
		buffer.writef32(buf, offset + 11, t.DelayTime)
		buffer.writeu8 (buf, offset + 15, 0)
		buffer.writeu8 (buf, offset + 16, 0)
	end,
	decode = function(buf, offset): TweenInfo
		return TweenInfo.new(
			buffer.readf32(buf, offset),
			Enum.EasingStyle:FromValue(buffer.readu8(buf, offset + 4)),
			Enum.EasingDirection:FromValue(buffer.readu8(buf, offset + 5)),
			buffer.readi32(buf, offset + 6),
			buffer.readu8(buf, offset + 10) == 1,
			buffer.readf32(buf, offset + 11)
		)
	end,
})

TypeCodecs.register("ColorSequenceKeypoint", {
	stride = 16,
	encode = function(buf, offset, k: ColorSequenceKeypoint)
		buffer.writef32(buf, offset,      k.Time)
		buffer.writef32(buf, offset +  4, k.Value.R)
		buffer.writef32(buf, offset +  8, k.Value.G)
		buffer.writef32(buf, offset + 12, k.Value.B)
	end,
	decode = function(buf, offset): ColorSequenceKeypoint
		return ColorSequenceKeypoint.new(
			buffer.readf32(buf, offset),
			Color3.new(buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8), buffer.readf32(buf, offset + 12))
		)
	end,
})

TypeCodecs.register("NumberSequenceKeypoint", {
	stride = 12,
	encode = function(buf, offset, k: NumberSequenceKeypoint)
		buffer.writef32(buf, offset,     k.Time)
		buffer.writef32(buf, offset + 4, k.Value)
		buffer.writef32(buf, offset + 8, k.Envelope)
	end,
	decode = function(buf, offset): NumberSequenceKeypoint
		return NumberSequenceKeypoint.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8))
	end,
})

TypeCodecs.register("ColorSequence", {
	stride = 0,
	encode = function(buf, offset, cs: ColorSequence)
		local kps = cs.Keypoints
		buffer.writeu8(buf, offset, #kps)
		for i, k in kps do
			local o = offset + 1 + (i-1) * 16
			buffer.writef32(buf, o,      k.Time)
			buffer.writef32(buf, o +  4, k.Value.R)
			buffer.writef32(buf, o +  8, k.Value.G)
			buffer.writef32(buf, o + 12, k.Value.B)
		end
	end,
	decode = function(buf, offset): ColorSequence
		local count = buffer.readu8(buf, offset)
		local kps = table.create(count)
		for i = 1, count do
			local o = offset + 1 + (i-1) * 16
			kps[i] = ColorSequenceKeypoint.new(buffer.readf32(buf, o), Color3.new(buffer.readf32(buf, o + 4), buffer.readf32(buf, o + 8), buffer.readf32(buf, o + 12)))
		end
		return ColorSequence.new(kps)
	end,
})

TypeCodecs.register("NumberSequence", {
	stride = 0,
	encode = function(buf, offset, ns: NumberSequence)
		local kps = ns.Keypoints
		buffer.writeu8(buf, offset, #kps)
		for i, k in kps do
			local o = offset + 1 + (i-1) * 12
			buffer.writef32(buf, o,     k.Time)
			buffer.writef32(buf, o + 4, k.Value)
			buffer.writef32(buf, o + 8, k.Envelope)
		end
	end,
	decode = function(buf, offset): NumberSequence
		local count = buffer.readu8(buf, offset)
		local kps = table.create(count)
		for i = 1, count do
			local o = offset + 1 + (i-1) * 12
			kps[i] = NumberSequenceKeypoint.new(buffer.readf32(buf, o), buffer.readf32(buf, o + 4), buffer.readf32(buf, o + 8))
		end
		return NumberSequence.new(kps)
	end,
})

TypeCodecs.register("FloatCurveKey", {
	stride = 16,
	encode = function(buf, offset, k: FloatCurveKey)
		buffer.writef32(buf, offset,      k.Time)
		buffer.writef32(buf, offset +  4, k.Value)
		buffer.writef32(buf, offset +  8, k.LeftTangent)
		buffer.writef32(buf, offset + 12, k.RightTangent)
	end,
	decode = function(buf, offset): FloatCurveKey
		local key = FloatCurveKey.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), Enum.KeyInterpolationMode.Cubic)
		key.LeftTangent  = buffer.readf32(buf, offset + 8)
		key.RightTangent = buffer.readf32(buf, offset + 12)
		return key
	end,
})

TypeCodecs.register("RotationCurveKey", {
	stride = 52,
	encode = function(buf, offset, k: RotationCurveKey)
		buffer.writef32(buf, offset, k.Time)
		buffer.writeu8 (buf, offset + 4, k.Interpolation.Value)
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = k.Value:GetComponents()
		buffer.writef32(buf, offset +  5, r00)
		buffer.writef32(buf, offset +  9, r01)
		buffer.writef32(buf, offset + 13, r02)
		buffer.writef32(buf, offset + 17, r10)
		buffer.writef32(buf, offset + 21, r11)
		buffer.writef32(buf, offset + 25, r12)
		buffer.writef32(buf, offset + 29, r20)
		buffer.writef32(buf, offset + 33, r21)
		buffer.writef32(buf, offset + 37, r22)
		buffer.writeu8(buf, offset + 41, 0)
		buffer.writeu8(buf, offset + 42, 0)
		buffer.writeu8(buf, offset + 43, 0)
	end,
	decode = function(buf, offset): RotationCurveKey
		local time = buffer.readf32(buf, offset)
		local interp = Enum.RotationCurveKeyInterpolation:FromValue(buffer.readu8(buf, offset + 4))
		local cf = CFrame.fromMatrix(
			Vector3.zero,
			Vector3.new(buffer.readf32(buf, offset+5), buffer.readf32(buf, offset+9),  buffer.readf32(buf, offset+13)),
			Vector3.new(buffer.readf32(buf, offset+17), buffer.readf32(buf, offset+21), buffer.readf32(buf, offset+25)),
			Vector3.new(buffer.readf32(buf, offset+29), buffer.readf32(buf, offset+33), buffer.readf32(buf, offset+37))
		)
		return RotationCurveKey.new(time, cf, interp)
	end,
})

TypeCodecs.register("PathWaypoint", {
	stride = 17,
	encode = function(buf, offset, p: PathWaypoint)
		buffer.writef32(buf, offset,      p.Position.X)
		buffer.writef32(buf, offset +  4, p.Position.Y)
		buffer.writef32(buf, offset +  8, p.Position.Z)
		buffer.writeu8 (buf, offset + 12, p.Action.Value)
		buffer.writeu32(buf, offset + 13, 0)
	end,
	decode = function(buf, offset): PathWaypoint
		return PathWaypoint.new(
			Vector3.new(buffer.readf32(buf, offset), buffer.readf32(buf, offset + 4), buffer.readf32(buf, offset + 8)),
			Enum.PathWaypointAction:FromValue(buffer.readu8(buf, offset + 12))
		)
	end,
})

return TypeCodecs
