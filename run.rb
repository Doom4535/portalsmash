#!/usr/bin/ruby

require 'rubygems'
require 'trollop'
require_relative 'portalsmash'
require_relative 'exec'

opts = Trollop::options do
  version "Version 0.01, (c) 2013 Malice Afterthought, Inc."
  banner <<-HEREBEDRAGONS

PortalSmash is a program that gets you through "captive portals" and other
annoyances. It connects to any open WiFi and attempts to get an IP and make
sure it works. If it works, it keeps rechecking every few seconds,
reconnecting (or finding a new connection) if it drops.

Sig:
If you wish, you may specify a path that contains a PID for PortalSmash to
send a SIGUSR1 to. This will be sent whenever PortalSmash connects to a new
network. If the PID changes over time, that's fine; PortalSmash will read
the file again each time it sends a SIGUSR1.

Netfile format:
PortalSmash allows a network key file to be specified that includes, well, keys
for networks. The file must be in YAML, and formatted approximately as so:

---
NetName:
	key: ohboyitsakey
HypotheticalWPAE:
	username: foo
	password: bar

This will allow the program to connect to WiFi for which you have been given
credentials (e.g., your home WiFi network).

Usage:
  portalsmash [options]
where [options] are:

HEREBEDRAGONS

  opt :device, "Device to connect", :type => :string, :default => "wlan0" # string --name <device>, default to wlan0
  opt :netfile, "Network key file in YAML format, as detailed above", :type => :io #io --netfile <path>
  opt :sig, "Path which will contain a PID for PortalSmash to send a SIGUSR1 to", :type => :string, :default => nil
end


dev  = opts[:device]
sig  = opts[:sig]
file = opts[:netfile]
exec    = Exec.new
go      = Go.new(dev,sig,exec)
scanner = Scanner.new(dev,file,exec)
smasher = Smasher.new
timer   = Timer.new
logger  = Log.new

ps = PortalSmasher.new(dev, scanner, smasher, go, timer, logger)
ps.run
