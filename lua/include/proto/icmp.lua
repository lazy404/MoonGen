local ffi = require "ffi"
local pkt = require "packet"

require "utils"
require "headers"

local eth = require "proto.ethernet"
local ip = require "proto.ip"
local ip6 = require "proto.ip6"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format

-- FIXME
-- ICMPv6 and ICMPv4 use different values for the same types/codes which causes some complications when handling this with only one header:
-- - get() always returns values twice with the respective named arguments for both icmpv4/6
-- - fill(<ip6 values>), followed by fill(get()), will not work, because get also returns ip4 values which are then prefered in the next call of fill
-- - getString() does not work for ICMPv6 correctly without some ugly workarounds (basically adding 'ipv4' flags to getString()'s of type/code and header)
-- 	 currently getString() simply does not recognise ICMPv6
-- - Furthermore, dumpPacket would need a change to pass this flag when calling getString()
-- Once this is really needed, better move ICMPv6 to a seperate file (which would result in copying/duplicating 95% of this code)
-- For now those cosmetic issues should not matter.

---------------------------------------------------------------------------
--- ICMPv4 constants
---------------------------------------------------------------------------

local icmp = {}

-- type-code pairs
icmp.ECHO_REPLY					= { type = 0, code = 0 }
icmp.ECHO_REQUEST 				= { type = 8, code = 0 }

icmp.DST_UNR_PORT_UNR		 	= { type = 3, code = 3 }

icmp.TIME_EXCEEDED_TTL_EXPIRED	= { type = 11, code = 0 }


---------------------------------------------------------------------------
--- ICMPv6 constants
---------------------------------------------------------------------------

local icmp6 = {}

icmp6.ECHO_REQUEST				= { type = 128, code = 0 }
icmp6.ECHO_REPLY				= { type = 129, code = 0 }


---------------------------------------------------------------------------
--- ICMP header
---------------------------------------------------------------------------

local icmpHeader = {}
icmpHeader.__index = icmpHeader

--- Set the type.
-- @param int Type of the icmp header as 8 bit integer.
function icmpHeader:setType(int)
	int = int or icmp.ECHO_REQUEST.type
	self.type = int
end

--- Retrieve the type.
-- @return Type as 8 bit integer.
function icmpHeader:getType()
	return self.type
end

--- Retrieve the type.
-- does not work for ICMPv6 (ICMPv6 uses different values)
-- @return Type as string.
function icmpHeader:getTypeString()
	local type = self:getType()
	local cleartext = "unknown"

	if type == icmp.ECHO_REPLY.type then
		cleartext = "echo reply"
	elseif type == icmp.ECHO_REQUEST.type then
		cleartext = "echo request"
	elseif type == icmp.DST_UNR_PORT_UNR.type then
		cleartext = "dst. unr."
	elseif type == icmp.TIME_EXCEEDED_TTL_EXPIRED.type then
		cleartext = "time exceeded"
	end

	return format("%s (%s)", type, cleartext)
end

--- Set the code.
-- @param int Code of the icmp header as 8 bit integer.
function icmpHeader:setCode(int)
	int = int or icmp.ECHO_REQUEST.code
	self.code = int
end

--- Retrieve the code.
-- @return Code as 8 bit integer.
function icmpHeader:getCode()
	return self.code
end

--- Retrieve the code.
-- does not work for ICMPv6
-- @return Code as string.
function icmpHeader:getCodeString()
	local type = self:getType()
	local code = self:getCode()
	local cleartext = "unknown"

	if type == icmp.ECHO_REPLY.type then
		cleartext = code == icmp.ECHO_REPLY.code and "correct" or "wrong"
	
	elseif type == icmp.ECHO_REQUEST.type then
		cleartext = code == icmp.ECHO_REQUEST.code and "correct" or "wrong"
	
	elseif type == icmp.DST_UNR_PORT_UNR.type then
		if code == icmp.DST_UNR_PORT_UNR.code then
			cleartext = "port unr."
		end
	
	elseif type == icmp.TIME_EXCEEDED_TTL_EXPIRED.type then
		if code == icmp.TIME_EXCEEDED_TTL_EXPIRED.code then
			cleartext = "ttl expired"
		end
	end

	return format("%s (%s)", code, cleartext)
end


--- Set the checksum.
-- @param int Checksum of the icmp header as 16 bit integer.
function icmpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Calculate the checksum
function icmpHeader:calculateChecksum(len)
	len = len or sizeof(self)
	self:setChecksum(0)
	self:setChecksum(hton16(checksum(self, len)))
end

--- Retrieve the checksum.
-- @return Checksum as 16 bit integer.
function icmpHeader:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum.
-- @return Checksum as string.
function icmpHeader:getChecksumString()
	return format("0x%04x", self:getChecksum())  
end

--- Set the message body.
-- @param int Message body of the icmp header as TODO.
function icmpHeader:setMessageBody(body)
	body = body or 0
	--self.body.uint8_t = body
end

--- Retrieve the message body.
-- @return Message body as TODO.
function icmpHeader:getMessageBody()
	return self.body
end

--- Retrieve the message body.
-- @return Message body as string TODO.
function icmpHeader:getMessageBodyString()
	return "<some data>"
end

--- Set all members of the icmp header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: icmpType, icmpCode, icmpChecksum, icmpMessageBody
-- @usage fill() -- only default values
-- @usage fill{ icmpCode=3 } -- all members are set to default values with the exception of icmpCode
function icmpHeader:fill(args)
	args = args or {}

	self:setType(args.icmpType or args.icmp6Type)
	self:setCode(args.icmpCode or args.icmp6Code)
	self:setChecksum(args.icmpChecksum or args.icmp6Checksum)
	self:setMessageBody(args.icmpMessageBody or args.icmp6MessageBody)
end

--- Retrieve the values of all members.
-- Returns for both ICMP and ICMP6, the user normally knows which one he needs.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see icmpHeader:fill
function icmpHeader:get()
	return { icmpType 			= self:getType(), 
			 icmpCode 			= self:getCode(), 
			 icmpChecksum 		= self:getChecksum(), 
			 icmpMessageBody 	= self:getMessageBody(),
			 -- now the same for icmp6
			 icmp6Type 			= self:getType(), 
			 icmp6Code 			= self:getCode(), 
			 icmp6Checksum 		= self:getChecksum(), 
			 icmp6MessageBody 	= self:getMessageBody() }
end

--- Retrieve the values of all members.
-- Does not work correctly for ICMPv6 packets
-- @return Values in string format.
function icmpHeader:getString()
	return "ICMP type "			.. self:getTypeString() 
			.. " code "		.. self:getCodeString() 
			.. " cksum "	.. self:getChecksumString()
			.. " body "		.. self:getMessageBodyString() .. " "
end

function icmpHeader:resolveNextHeader()
	return nil
end

function icmpHeader:setDefaultNamedArgs(namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end


------------------------------------------------------------------------
--- Packets
------------------------------------------------------------------------

-- TODO instead of only payload add inner_ip for icmp payload
pkt.getIcmp4Packet = packetCreate("eth", { "ip4", "ip" }, "icmp")
pkt.getIcmp6Packet = packetCreate("eth", { "ip6", "ip" }, "icmp")
pkt.getIcmpPacket = function(self, ip4) ip4 = ip4 == nil or ip4 if ip4 then return pkt.getIcmp4Packet(self) else return pkt.getIcmp6Packet(self) end end   


------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct icmp_header", icmpHeader)

return icmp, icmp6
