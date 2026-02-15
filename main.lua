--!strict

-- MODULE CREATED BY @alt_orsum1 on ROBLOX
-- THIS WAS A TEST TO SEE IF I COULD MANUALLY SEND A PACKET WITHOUT USING BYTENET'S BUILT IN LIBRARY
-- This script was made for educational purposes only.

-- This script was made for old versions of ByteNet
-- Specifically for versions with internal call flags

-- Script is limited to a maximum of 255 specific packets. Try to send to any higher will fail.
-- This script does trust PacketId's, so be careful. (Meaning expecting 0-255 and not checking)
-- SCRIPT NO LONGER TRUSTS PACKETIDS

-- What's new?:
-- ADDED OPTIONAL FLAG FOR INTERNAL FUNCTION

-- / Services \ --
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- \          / --

-- / Types \ --
export type BW = {
	send: (Buff: buffer, Remote: string) -> (),
	getPacketId: (NameSpace: string, PacketName: string) -> (number | nil),
	string: (PacketId: number, Str: string) -> (buffer | nil),
	u8: (PacketId: number, Value: number) -> (buffer | nil),
	u16: (PacketId: number, Value: number) -> (buffer | nil),
	i8: (PacketId: number, Value: number) -> (buffer | nil),
	i16: (PacketId: number, Value: number) -> (buffer | nil),
}
-- \       / --

-- / Variables \ --
local ByteNetStorage = ReplicatedStorage:WaitForChild("BytenetStorage")
local Reliable: RemoteEvent = ReplicatedStorage:WaitForChild("ByteNetReliable") :: RemoteEvent
local Unreliable: RemoteEvent = ReplicatedStorage:WaitForChild("ByteNetUnreliable") :: RemoteEvent

local StoredNamespaces = {}
-- To save expensive HttpService:JSONDecode()s

local BufferWriter = {} :: BW
-- \           / --

-- / Functionality \ --
local function CheckLimits(BitSize: number, Signed: boolean, Value: number): (boolean, string)
	local LowerLimit, HigherLimit = 0, 0
	if Signed then
		BitSize -= 1
		LowerLimit = -2 ^ (BitSize)
		HigherLimit = LowerLimit * -1 - 1
	else
		HigherLimit = 2 ^ BitSize - 1
	end
	
	if Value < LowerLimit or Value > HigherLimit then
		local ErrorMessage = 
			(Value < LowerLimit) and 
			`Value is less than the lower limit of this {tostring(BitSize)} bit {Signed and "signed" or "unsigned"} integer! LowerLimit: {tostring(LowerLimit)} Value: {tostring(Value)}`
		    or
			`Value is less than the higher limit of this {tostring(BitSize)} bit {Signed and "signed" or "unsigned"} integer! HigherLimit: {tostring(HigherLimit)} Value: {tostring(Value)}`
		return false, ErrorMessage
	end
	
	return true, ""
end

-- Local function the type checks the PacketId and CallerName and then returns a buffer with the flag and packet id
-- Limitation: 0-255 Packet ID | 0-255 Flag ID | CallerName: 0-(64b limit)
local function WriteFlagAndPacketId(PacketId: number, CallerName: string, Size: number, Flag: number?) : (buffer | nil)
	if (Flag and type(Flag) and Flag > 255) or not Flag or typeof(Flag) ~= "number" then 
		Flag = 0
	end
	
	assert(CallerName, "[ByteWriter.WriteFlagAndPacketId(lf)]: ⚠️ CallerName arg wasn't provided or resulted to nil!")
	assert(typeof(CallerName) == "string", "[ByteWriter.WriteFlagAndPacketId(lf)]: ⚠️ CallerName arg wasn't nil, but isn't type 'string'!")
	
	assert(Size, "[ByteWriter.WriteFlagAndPacketId(lf)]: ⚠️ Size arg wasn't provided or resulted to nil!")
	assert(typeof(Size) == "number", "[ByteWriter.WriteFlagAndPacketId(lf)]: ⚠️ Size arg wasn't nil, but isn't type 'number'!")
	if Size < 2 then return nil end
	
	if not PacketId then warn(`[ByteWriter.{CallerName}]: ⚠️ PacketId arg wasn't provided or resulted to nil!`) return nil end
	if typeof(PacketId) ~= "number" then warn(`[ByteWriter.{CallerName}]: ⚠️ PacketId arg wasn't nil, but isn't type 'number'!`) return nil end
	if PacketId < 0 or PacketId > 255 then return nil end
	
	local Buff = buffer.create(Size)
	buffer.writeu8(Buff, 0, Flag :: number)
	buffer.writeu8(Buff, 1, PacketId)
	-- [Flag] [PacketId]
	
	return Buff
end

-- Limitations:  0-255   (8-bit Unsigned Integer)
function BufferWriter.u8(PacketId: number, Value: number): buffer | nil
	local Check, Err = CheckLimits(8, false, Value)
	if not Check then warn(Err) return nil end
	
	local Buff: (buffer | nil) = WriteFlagAndPacketId(PacketId, "u8", 3)
	if Buff == nil then return nil end
	--flag + id + value  (1 each)

	--local Cursor = 2
	buffer.writeu8(Buff, 2, Value)

	return Buff
end

-- Limitations:  0-65535   (16-bit Unsigned Integer)
function BufferWriter.u16(PacketId: number, Value: number): buffer | nil
	local Check, Err = CheckLimits(16, false, Value)
	if not Check then warn(Err) return nil end
	
	local Buff: (buffer | nil) = WriteFlagAndPacketId(PacketId, "u16", 4)
	if Buff == nil then return nil end
	--flag + id + (2)value  (1 each)

	--local Cursor = 2
	buffer.writeu16(Buff, 2, Value)

	return Buff
end

-- Limitations:  -128 - 127   (8-bit signed Integer)
function BufferWriter.i8(PacketId: number, Value: number): buffer | nil
	local Check, Err = CheckLimits(8, true, Value)
	if not Check then warn(Err) return nil end

	local Buff: (buffer | nil) = WriteFlagAndPacketId(PacketId, "i8", 3)
	if Buff == nil then return nil end
	--flag + id + value  (1 each)

	--local Cursor = 2

	buffer.writei8(Buff, 2, Value)

	return Buff
end

-- Limitations:  -32768 - 32767   (16-bit signed Integer)
function BufferWriter.i16(PacketId: number, Value: number): buffer | nil
	local Check, Err = CheckLimits(16, true, Value)
	if not Check then warn(Err) return nil end
	
	local Buff: (buffer | nil) = WriteFlagAndPacketId(PacketId, "i16", 4)
	if Buff == nil then return nil end
	--flag + id + (2)value  (1 each)

	--local Cursor = 2
	buffer.writei16(Buff, 2, Value)

	return Buff
end

-- String Character Limitations:  0-65535  (16-bit Unsigned Integer)
function BufferWriter.string(PacketId: number, Str: string): buffer | nil
	local StringLength = #Str
	
	local Check, Err = CheckLimits(16, false, StringLength)
	if not Check then warn(Err) return nil end

	local Buff: (buffer | nil) = WriteFlagAndPacketId(PacketId, "i16", StringLength + 4)
	if Buff == nil then return nil end
	-- flag + id + value + StringLength
	-- 1+1+1+#Str
	
	local Cursor = 2

	buffer.writeu16(Buff, Cursor, StringLength)
	Cursor += 2

	buffer.writestring(Buff, Cursor, Str)

	return Buff
end

-- Trusts that Remote is provided.
-- Doesn't trust that the remote is correct.
function BufferWriter.send(Buff: buffer, Remote: string)
	if Buff == nil then warn("[BufferWriter.send]: ⚠️ Buff arg is nil or resulted to nil!") return end
	if typeof(Buff) ~= "buffer" then warn("[BufferWriter.send]: ⚠️ Buff arg isn't nil, but isn't type 'buffer'!") return end
	
	local RemoteEvent: RemoteEvent | false = Remote == "Reliable" and Reliable or Remote == "Unreliable" and Unreliable
	if RemoteEvent == false then warn("[BufferWriter.send]: ⚠️ Remote arg was provided, but isn't a valid remote type!") return end
	
	warn(RemoteEvent.Name)
	
	RemoteEvent:FireServer(Buff, nil)
	-- Sending the buffer, then the references which aren't fully added in the version that this module supports.
end

-- Expects types to be correct
function BufferWriter.getPacketId(NameSpace: string, PacketName: string): number | nil
	if not NameSpace or not PacketName then return nil end
	
	local FoundNamespace = StoredNamespaces[NameSpace]
	
	local StorageNamespace: Instance? = ByteNetStorage:FindFirstChild(NameSpace)
	
	if not FoundNamespace and not StorageNamespace then
		warn(`[BufferWriter.getPacketId]: ⚠️ couldn't find namespace '{NameSpace}'!`)
		return nil
	elseif not FoundNamespace and StorageNamespace and StorageNamespace:IsA("StringValue") then
		local Decoded = HttpService:JSONDecode(StorageNamespace.Value::string)
		StoredNamespaces[NameSpace] = Decoded
		FoundNamespace = Decoded
	end
	local PacketId = FoundNamespace.packets[PacketName]
	if PacketId then return PacketId end
	
	warn(`[BufferWriter.getPacketId]: ⚠️ Couldn't get the id of search: packet '{PacketName}' inside of namespace '{NameSpace}'!`)
	return nil
end

return BufferWriter
-- \               / --
