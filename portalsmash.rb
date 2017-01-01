#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
require_relative 'exec'
require_relative 'scanner'
require_relative 'smasher'

#State Machine

# States:
#   Start - we know nothing.
#   List - We have the scanned list, written to a file.
#   Attached - We've gotten an attached note from WPA_CLI.
#   HasIP - We have an IP address from dhclient.
#   Breaker - We're running the breaker.
#   Monitor - Connection is solid, we'll periodically check it.

# State, Transition, New State

# Start, ScanSuccess, List
# Start, ScanFail, Start
# List, AttachSuccess, Attached
# List, AttachFail, List
# Attached, DHCPSuccess, HasIP
# Attached, DHCPFail, List
# HasIP, CCSuccess, Monitor
# HasIP, CCFail, Breaker
# Breaker, CCSuccess, Monitor
# Breaker, CCFail, List
# Monitor, CCSuccess, Monitor
# Monitor, CCFail, Start

class PortalSmasher

  attr_reader :state, :scan_success, :attach_state, :dhcp_success, :cc_success, :scanner, :smasher, :exec

  CONFPATH = '/tmp/portalsmash.conf'

  ATTACH_SUCCESS = 0
  ATTACH_FAIL = 1
  ATTACH_OUT = 2

  def initialize(dev, file, sig, exec)
    @exec = exec
    @state = :start
    @net_counter = 0
    @device = dev
    @scanner = Scanner.new(dev,file,exec)
    @smasher = Smasher.new
    @sig = sig
  end

  def scan
    scanner.scan
  end

  def number_of_networks
    scanner.number_of_networks
  end

  def attach
    if (@net_counter.to_i >= number_of_networks.to_i)
      puts "I'm out of networks to which I can attach."
      return ATTACH_OUT
    end
    puts "Attaching to Network #{@net_counter+1} of #{number_of_networks}."

    exec.wpa_cli_select(@net_counter)

    @net_counter += 1

    sleep(5)
    stat = @exec.wpa_cli_status

    if (stat =~ /COMPLETED/)
      return ATTACH_SUCCESS
    elsif (@net_counter.to_i >= number_of_networks.to_i)
      return ATTACH_OUT
    else
      return ATTACH_FAIL
    end

  end

  def dhcp
    puts "DCHP-ing"
    exec.dhclient_release(@device)
    exec.dhclient(@device)
    exec.exitstatus == 0
  end

  def killthings
    exec.pkill_wpa_supplicant
    exec.pkill_dhclient
    exec.ifconfig_up(@device)
  end

  def startwpa
    exec.wpa_supplicant(device)
    exec.exitstatus == 0
  end

  def sendsig
    if !@sig.nil?
      begin
        pid = File.read @sig
      rescue => e
        puts "I was given a PID file to tell, but I don't see it."
      end
      if !pid.nil?
        exec.kill(pid)
      end
    end
  end

  def run
    while true
      puts ""
      puts "State: #{@state}"
      check_state
      sleep 2
    end
  end

  def start
    killthings
    @scan_success = scan
    if @scan_success
      @state = :list
      if startwpa == false
        @state = :start
        puts "Failed to start wpa_supplicant. Are you root?"
      end
    else
      @state = :start
      puts "Scan failed using #{@device}."
    end
  end

  def list
    @attach_state = attach
    case @attach_state
    when ATTACH_SUCCESS
      @state = :attached
    when ATTACH_FAIL
      @state = :list
    when ATTACH_OUT
      @state = :start
    end
  end

  def attached
    @dhcp_success = dhcp
    @state = @dhcp_success ? :hasip : :attached
  end

  def hasip
    conncheck
    if cc_success
      sendsig
      @state = :monitor
    else
      @state = :breaker
    end
  end

  def breaker
    smasher.runbreak
    conncheck
    if cc_success
      sendsig
      @state = :monitor
    else
      @state = :list
    end
  end

  def monitor
    conncheck
    @state = cc_success ? :monitor : :start
  end

  def conncheck
    @cc_success = smasher.conncheck
  end

  def check_state
    case @state
      when :start
        start
      when :list
        list
      when :attached
        attached
      when :hasip
        hasip
      when :breaker
        breaker
      when :monitor
        monitor
    end
  end

end
