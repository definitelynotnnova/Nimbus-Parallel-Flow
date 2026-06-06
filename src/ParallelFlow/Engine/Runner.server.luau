-- boots up the runtime engine for each actor
local actor = script:GetActor()
if not actor then return end

-- setup the engine
local lib = require(script.Parent.Parent.Parent.Serializer)
local engine = require(script.Parent.Parent.Runtime)

engine.start(actor, lib)
