#!/usr/bin/ruby

require 'rubygems'
require_relative 'exec'
require_relative 'log'

class Go

  attr_reader :exec

  def initialize(dev, sig, exec)
    @exec = exec
    @device = dev
    @sig = sig
    @logger = Log.new
  end

  def try_attaching_to(network)
    log "Attaching to Network #{@net_counter+1} of #{number_of_networks}."
    exec.wpa_cli_select(@net_counter)
  end

  def attach_successful
    stat = exec.wpa_cli_status
    stat =~ /COMPLETED/
  end

  def dhcp
    log "DCHP-ing"
    exec.dhclient_release(@device)
    exec.dhclient(@device)
    exec.exitstatus == 0
  end

  def kill_things
    exec.pkill_wpa_supplicant
    exec.pkill_dhclient
    exec.ifconfig_up(@device)
  end

  def start_wpa
    exec.wpa_supplicant(device)
    exec.exitstatus == 0
  end

  def send_sig
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

  def log(message)
    @logger.log message
  end

end
