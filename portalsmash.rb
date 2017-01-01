#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
require_relative 'exec'
require_relative 'scanner'
require_relative 'smasher'
require_relative 'timer'
require_relative 'log'

#State Machine

# States:
#   Start    - we know nothing.
#   List     - We have the scanned list, written to a file.
#   Attached - We've gotten an attached note from WPA_CLI.
#   HasIP    - We have an IP address from dhclient.
#   Breaker  - We're running the breaker.
#   Monitor  - Connection is solid, we'll periodically check it.

# State     Transition    -> New State

# Start     ScanSuccess   -> List
#           ScanFail      -> Start
# List      AttachSuccess -> Attached
#           AttachFail    -> List
# Attached  DHCPSuccess   -> HasIP
#           DHCPFail      -> List
# HasIP     CCSuccess     -> Monitor
#           CCFail        -> Breaker
# Breaker   CCSuccess     -> Monitor
#           CCFail        -> List
# Monitor   CCSuccess     -> Monitor
#           CCFail        -> Start

class PortalSmasher

  attr_reader :state, :attach_state, :dhcp_success, :scanner, :smasher, :exec

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
    @timer = Timer.new
    @logger = Log.new
  end

  def scan
    scanner.scan
  end

  def number_of_networks
    scanner.number_of_networks
  end

  def attach
    if (@net_counter.to_i >= number_of_networks.to_i)
      log "I'm out of networks to which I can attach."
      return ATTACH_OUT
    end
    log "Attaching to Network #{@net_counter+1} of #{number_of_networks}."

    exec.wpa_cli_select(@net_counter)

    @net_counter += 1

    snooze 5
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
    log "DCHP-ing"
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
        log "I was given a PID file to tell, but I don't see it."
      end
      if !pid.nil?
        exec.kill(pid)
      end
    end
  end

  def run
    while true
      log ""
      log "State: #{@state}"
      check_state
      snooze 2
    end
  end

  def start
    killthings
    if scan
      @state = :list
      if startwpa == false
        @state = :start
        log "Failed to start wpa_supplicant. Are you root?"
      end
    else
      @state = :start
      log "Scan failed using #{@device}."
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
    if conncheck
      sendsig
      @state = :monitor
    else
      @state = :breaker
    end
  end

  def breaker
    smasher.runbreak
    if conncheck
      sendsig
      @state = :monitor
    else
      @state = :list
    end
  end

  def monitor
    @state = conncheck ? :monitor : :start
  end

  def conncheck
    smasher.conncheck
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

  def snooze(amount)
    @timer.snooze amount
  end

  def log(message)
    @logger.log message
  end

end
