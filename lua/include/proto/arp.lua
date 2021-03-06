local ffi = require "ffi"
local pkt = require "packet"

require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local memory = require "memory"
local filter = require "filter"
local ns = require "namespaces"

local eth = require "proto.ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local format = string.format
local istype = ffi.istype

local arp = {}


--------------------------------------------------------------------------------------------------------
--- ARP constants (c.f. http://www.iana.org/assignments/arp-parameters/arp-parameters.xhtml)
--------------------------------------------------------------------------------------------------------

-- hrd
arp.HARDWARE_ADDRESS_TYPE_ETHERNET = 1

-- pro (for ethernet based protocols uses ether type numbers)
arp.PROTO_ADDRESS_TYPE_IP = 0x0800

-- op
arp.OP_REQUEST = 1
arp.OP_REPLY = 2


--------------------------------------------------------------------------------------------------------
--- ARP header
--------------------------------------------------------------------------------------------------------

local arpHeader = {}
arpHeader.__index = arpHeader

--- Set the hardware address type.
-- @param int Type as 16 bit integer.
function arpHeader:setHardwareAddressType(int)
	int = int or arp.HARDWARE_ADDRESS_TYPE_ETHERNET
	self.hrd = hton16(int)
end

--- Retrieve the hardware address type.
-- @return Type as 16 bit integer.
function arpHeader:getHardwareAddressType()
	return hton16(self.hrd)
end

--- Retrieve the hardware address type.
-- @return Type in string format.
function arpHeader:getHardwareAddressTypeString()
	local type = self:getHardwareAddressType()
	if type == arp.HARDWARE_ADDRESS_TYPE_ETHERNET then
		return "Ethernet"
	else
		return format("0x%04x", type)
	end
end
	
function arpHeader:setProtoAddressType(int)
	int = int or arp.PROTO_ADDRESS_TYPE_IP
	self.pro = hton16(int)
end

function arpHeader:getProtoAddressType()
	return hton16(self.pro)
end

function arpHeader:getProtoAddressTypeString()
	local type = self:getProtoAddressType()
	if type == arp.PROTO_ADDR_TYPE_IP then
		return "IPv4"
	else
		return format("0x%04x", type)
	end
end

function arpHeader:setHardwareAddressLength(int)
	int = int or 6
	self.hln = int
end

function arpHeader:getHardwareAddressLength()
	return self.hln
end

function arpHeader:getHardwareAddressLengthString()
	return self:getHardwareAddressLength()
end

function arpHeader:setProtoAddressLength(int)
	int = int or 4
	self.pln = int
end

function arpHeader:getProtoAddressLength()
	return self.pln
end

function arpHeader:getProtoAddressLengthString()
	return self:getProtoAddressLength()
end

function arpHeader:setOperation(int)
	int = int or arp.OP_REQUEST
	self.op = hton16(int)
end

function arpHeader:getOperation()
	return hton16(self.op)
end

function arpHeader:getOperationString()
	local op = self:getOperation()
	if op == arp.OP_REQUEST then
		return "Request"
	elseif op == arp.OP_REPLY then
		return "Reply"
	else
		return op
	end
end

function arpHeader:setHardwareSrc(addr)
	self.sha:set(addr)
end

function arpHeader:getHardwareSrc()
	return self.sha:get()
end

function arpHeader:setHardwareSrcString(addr)
	self.sha:setString(addr)
end

function arpHeader:getHardwareSrcString()
	return self.sha:getString()
end

function arpHeader:setHardwareDst(addr)
	self.tha:set(addr)
end

function arpHeader:getHardwareDst()
	return self.tha:get()
end

function arpHeader:setHardwareDstString(addr)
	self.tha:setString(addr)
end

function arpHeader:getHardwareDstString()
	return self.tha:getString()
end

function arpHeader:setProtoSrc(addr)
	self.spa:set(addr)
end

function arpHeader:getProtoSrc()
	return self.spa:get()
end

function arpHeader:setProtoSrcString(addr)
	self.spa:setString(addr)
end

function arpHeader:getProtoSrcString()
	return self.spa:getString()
end

function arpHeader:setProtoDst(addr)
	self.tpa:set(addr)
end

function arpHeader:getProtoDst()
	return self.tpa:get()
end

function arpHeader:setProtoDstString(addr)
	self.tpa:setString(addr)
end

function arpHeader:getProtoDstString()
	return self.tpa:getString()
end

function arpHeader:fill(args)
	args = args or {}
	
	self:setHardwareAddressType(args.arpHardwareAddressType)
	self:setProtoAddressType(args.arpProtoAddressType)
	self:setHardwareAddressLength(args.arpHardwareAddressLength)
	self:setProtoAddressLength(args.arpProtoAddressLength)
	self:setOperation(args.arpOperation)

	args.arpHardwareSrc = args.arpHardwareSrc or "01:02:03:04:05:06"
	args.arpHardwareDst = args.arpHardwareDst or "07:08:09:0a:0b:0c"
	args.arpProtoSrc = args.arpProtoSrc or "0.1.2.3"
	args.arpProtoDst = args.arpProtoDst or "4.5.6.7"
	
	-- if for some reason the address is in 'struct mac_address'/'union ipv4_address' format, cope with it
	if type(args.arpHardwareSrc) == "string" then
		self:setHardwareSrcString(args.arpHardwareSrc)
	else
		self:setHardwareSrc(args.arpHardwareSrc)
	end
	if type(args.arpHardwareDst) == "string" then
		self:setHardwareDstString(args.arpHardwareDst)
	else
		self:setHardwareDst(args.arpHardwareDst)
	end
	
	if type(args.arpProtoSrc) == "string" then
		self:setProtoSrcString(args.arpProtoSrc)
	else
		self:setProtoSrc(args.arpProtoSrc)
	end
	if type(args.arpProtoDst) == "string" then
		self:setProtoDstString(args.arpProtoDst)
	else
		self:setProtoDst(args.arpProtoDst)
	end
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see arpHeader:fill
function arpHeader:get()
	return { arpHardwareAddressType 	= self:getHardwareAddressType(),
			 arpProtoAddressType 		= self:getProtoAddressType(),
			 arpHardwareAddressLength	= self:getHardwareAddressLength(),
			 arpProtoAddressLength		= self:getProtoAddressLength(),
			 arpOperation				= self:getOperation(),
			 arpHardwareSrc				= self:getHardwareSrc(),
			 arpHardwareDst				= self:getHardwareDst(),
			 arpProtoSrc				= self:getProtoSrc(),
			 arpProtoDst				= self:getProtoDst() 
		 }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function arpHeader:getString()
	local str = "ARP hrd " 			.. self:getHardwareAddressTypeString() 
				.. " (hln " 		.. self:getHardwareAddressLengthString() 
				.. ") pro " 		.. self:getProtoAddressTypeString() 
				.. " (pln " 		.. self:getProtoAddressLength(String) 
				.. ") op " 			.. self:getOperationString()

	local op = self:getOperation()
	if op == arp.OP_REQUEST then
		str = str .. " who-has " 	.. self:getProtoDstString() 
				  .. " (" 			.. self:getHardwareDstString() 
				  .. ") tell " 		.. self:getProtoSrcString() 
				  .. " (" 			.. self:getHardwareSrcString() 
				  .. ")"
	elseif op == arp.OP_REPLY then
		str = str .. " " 			.. self:getProtoSrcString() 
				  .. " is-at " 		.. self:getHardwareSrcString() 
				  .. " (for " 		.. self:getProtoDstString() 
				  .. " @ " 			.. self:getHardwareDstString() 
				  .. ")"
	else
		str = str .. " " 			.. self:getHardwareSrcString() 
				  .. " > " 			.. self:getHardwareDstString() 
				  .. " " 			.. self:getProtoSrcString() 
				  .. " > " 			.. self:getProtoDstString()
	end

	return str
end

function arpHeader:resolveNextHeader()
	return nil
end

function arpHeader:setDefaultNamedArgs(namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end
	
---------------------------------------------------------------------------------
--- Packets
---------------------------------------------------------------------------------

pkt.getArpPacket = packetCreate("eth", "arp")


---------------------------------------------------------------------------------
--- ARP Handler Task
---------------------------------------------------------------------------------

--- Arp handler task, responds to ARP queries for given IPs and performs arp lookups
-- TODO implement garbage collection/refreshing entries
-- the current implementation does not handle large tables efficiently
-- TODO multi-NIC support
arp.arpTask = "__MG_ARP_TASK"

local arpTable = ns:get()

local function arpTask(rxQueue, txQueue, ips)
	arpTable.taskRunning = true
	if type(ips) ~= "table" then
		ips = { ips }
	end
	local ipToMac = {}
	for i, v in ipairs(ips) do
		if type(v) == "string" then
			v = parseIPAddress(v)
			ips[i] = v
		end
		ipToMac[v] = true -- TODO: support different MACs for different IPs
	end
	if rxQueue.dev ~= txQueue.dev then
		error("both queues must belong to the same device")
	end
	local arpSrcIP = ips[1] -- the source address for ARP requests

	local dev = rxQueue.dev
	local devMac = dev:getMac()
	local rxBufs = memory.createBufArray(1)
	local txMem = memory.createMemPool(function(buf)
		buf:getArpPacket():fill{ 
			ethSrc			= devMac,  
			arpOperation	= arp.OP_REPLY,
			arpHardwareSrc	= devMac,
			arpProtoSrc 	= devIP,
			pktLength		= 60
		}
	end)
	local txBufs = txMem:bufArray(1)
	dev:l2Filter(eth.TYPE_ARP, rxQueue)
	
	while dpdk.running() do
		rx = rxQueue:tryRecvIdle(rxBufs, 1000)
		assert(rx <= 1)
		if rx > 0 then
			local rxPkt = rxBufs[1]:getArpPacket()
			if rxPkt.eth:getType() == eth.TYPE_ARP then
				if rxPkt.arp:getOperation() == arp.OP_REQUEST then
					local ip = rxPkt.arp:getProtoDst()
					local mac = ipToMac[ip]
					if mac then
						if mac == true then
							mac = devMac
						end
						txBufs:alloc(60)
						-- TODO: a single-packet API would be nice for things like this
						local pkt = txBufs[1]:getArpPacket()
						pkt.eth:setDst(rxPkt.eth:getSrc())
						pkt.arp:setOperation(arp.OP_REPLY)
						pkt.arp:setHardwareDst(rxPkt.arp:getHardwareSrc())
						pkt.arp:setProtoDst(rxPkt.arp:getProtoSrc())
						pkt.arp:setProtoSrc(ip)
						txQueue:send(txBufs)
					end
				elseif rxPkt.arp:getOperation() == arp.OP_REPLY then
					-- learn from all arp replies we see (suspicable to arp cache poisoning but that doesn't matter here)
					local mac = rxPkt.arp:getHardwareSrcString()
					local ip = rxPkt.arp:getProtoSrcString()
					arpTable[tostring(parseIPAddress(ip))] = { mac = mac, timestamp = dpdk.getTime() }
				end
			end
			rxBufs:freeAll()
		end
		-- send outstanding requests
		arpTable:forEach(function(ip, value)
			-- TODO: refresh or GC old entries
			if value ~= "pending" then
				return
			end
			arpTable[ip] = "requested"
			-- TODO: the format should be compatible with parseIPAddress
			ip = tonumber(ip)
			txBufs:alloc(60)
			local pkt = txBufs[1]:getArpPacket()
			pkt.eth:setDstString(eth.BROADCAST)
			pkt.arp:setOperation(arp.OP_REQUEST)
			pkt.arp:setHardwareDstString(eth.BROADCAST)
			pkt.arp:setProtoDst(ip)
			pkt.arp:setProtoSrc(arpSrcIP)
			txQueue:send(txBufs)
		end)
		--dpdk.sleepMillisIdle(1)
	end
end

function arp.lookup(ip)
	if type(ip) == "string" then
		ip = parseIPAddress(ip)
	elseif type(ip) == "cdata" then
		ip = ip:get()
	end
	if not arpTable.taskRunning then
		error("ARP task is not running")
	end
	local mac = arpTable[tostring(ip)]
	if mac and mac ~= "pending" then
		return mac.mac, mac.timestamp
	end
	if mac ~= "requested" then
		arpTable[tostring(ip)] = "pending" -- FIXME: this needs a lock
	end
	return nil
end

function arp.blockingLookup(ip)
	error("NYI")
end

__MG_ARP_TASK = arpTask


---------------------------------------------------------------------------------
--- Metatypes
---------------------------------------------------------------------------------

ffi.metatype("struct arp_header", arpHeader)

return arp

