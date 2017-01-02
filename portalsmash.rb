#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
require_relative 'go'
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

  attr_reader :state, :scanner, :smasher, :go

  ATTACH_SUCCESS = 0
  ATTACH_FAIL    = 1
  ATTACH_OUT     = 2

  def initialize(dev, scanner, smasher, go, timer, logger)
    @state       = :start
    @net_counter = 0
    @device  = dev
    @scanner = scanner
    @smasher = smasher
    @go      = go
    @timer   = timer
    @logger  = logger
  end

  def scan
    scanner.scan
  end

  def number_of_networks
    scanner.number_of_networks
  end

  def attach
    if (out_of_networks_to_attach_to)
      log "I'm out of networks to which I can attach."
      return ATTACH_OUT
    end
    go.try_attaching_to(@net_counter)
    @net_counter += 1
    snooze 5
    attach_status
  end

  def attach_status
    if (go.attach_successful)
      return ATTACH_SUCCESS
    elsif (out_of_networks_to_attach_to)
      return ATTACH_OUT
    else
      return ATTACH_FAIL
    end
  end

  def out_of_networks_to_attach_to
    @net_counter.to_i >= number_of_networks.to_i
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
    go.kill_things
    if scan
      @state = :list
      if start_wpa == false
        @state = :start
        log "Failed to start wpa_supplicant. Are you root?"
      end
    else
      @state = :start
      log "Scan failed using #{@device}."
    end
  end

  def list
    case attach
      when ATTACH_SUCCESS
        @state = :attached
      when ATTACH_FAIL
        @state = :list
      when ATTACH_OUT
        @state = :start
    end
  end

  def attached
    @state = dhcp ? :has_ip : :attached
  end

  def has_ip
    if connection_ok
      go.send_sig
      @state = :monitor
    else
      @state = :breaker
    end
  end

  def breaker
    smasher.login
    if connection_ok
      go.send_sig
      @state = :monitor
    else
      @state = :list
    end
  end

  def monitor
    @state = connection_ok ? :monitor : :start
  end

  def connection_ok
    smasher.connection_ok
  end

  def check_state
    case @state
      when :start
        start
      when :list
        list
      when :attached
        attached
      when :has_ip
        has_ip
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
