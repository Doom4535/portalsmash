#!/usr/bin/ruby

require 'rubygems'
require 'mechanize'
require 'yaml'
require_relative 'exec'

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

  #Variables for seeing what it's doing right now - not modifiable outside the class
  attr_reader :state, :running, :scan_success, :attach_state, :dhcp_success, :cc_success, :number_of_networks, :net_counter, :exec

  TESTPAGE = 'http://www.apple.com/library/test/success.html'
  CONFPATH = '/tmp/portalsmash.conf'

  ATTACH_SUCCESS = 0
  ATTACH_FAIL = 1
  ATTACH_OUT = 2

  def initialize(dev, file, sig, exec)
    @exec = exec
    @state = :start
    @running = true

    @number_of_networks = 0
    @net_counter = 0

    #Storage variables internal to the class (No accessors)
    @device = dev
    @list_count = 0
    @page = nil
    @agent = Mechanize.new
    @knownnetworks = {}
    @sig = sig

    if file
      @knownnetworks = YAML.load_file(file)
    end
  end

  def stop
    @running = false
  end

  def scan
    puts "Scanning"

    encnets = []
    unencnets = []

    File.open(CONFPATH, "w") do |f|
      f.puts "ctrl_interface=DIR=/var/run/wpa_supplicant"

      networklist = exec.iwlist(@device)

      if (exec.exitstatus != 0)
        return false #iwlist didn't work right.
      end

      networks = networklist.split(/Cell \d{2}/); #This will give us cell 1 in @networks[1], as [0] will hold junk
      networks.delete_at(0)

      usednetworks = {}

      networks.each do |net|
        data = net.split(/\n/)
        bssid = data[0].match(/([A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2})/)[1]
        ssid = data[5].match(/ESSID\:\"(.*)\"/)[1]
        enc = data[4].match(/Encryption key:(.+)/)[1]

        #So, only proceed if either we know the network, or if there's no encryption -- and either way, only
        #if we haven't done this network before (to prevent trying to connect to 80 different instances of
        #the same WiFi network)7888888
        if (!usednetworks[ssid] and ((enc == "off") or (@knownnetworks[ssid])))
          str = ""
          str += "network={\n"
          str += "ssid=\"#{ssid}\"\n"
          str += "scan_ssid=1\n"
          if (enc == "on")
            # This is just a brutal hack. I can be a lot more precise-- specifying CCMP and the like-- but it doesn't matter, weirdly.

            if net =~ /WPA/
              if (@knownnetworks[ssid]['key']) #Then it's WPA-PSK
                str += "key_mgmt=WPA-PSK\n"
                str += "psk=\"#{@knownnetworks[ssid]['key']}\"\n"
              else #Then it's WPAE
                str += "key_mgmt=WPA-EAP\n"
                str += "identity=\"#{@knownnetworks[ssid]['username']}\"\n"
                str += "password=\"#{@knownnetworks[ssid]['password']}\"\n"
              end
            else #WEP
              str += "key_mgmt=NONE\n"
              str += "wep_tx_keyidx=0\n"
              str += "wep_key0=\"#{@knownnetworks[ssid]['key']}\"\n"
            end

          else
            str += "key_mgmt=NONE\n"
          end
          str += "}\n"

          usednetworks[ssid] = 1

          if @knownnetworks[ssid]
            encnets.push(str)
          else
            unencnets.push(str)
          end

        end
      end

      puts "Encnets: #{encnets.size} Unencnets: #{unencnets.size}"

      encnets.each do |s|
        f.puts s
      end

      unencnets.each do |s|
        f.puts s
      end

    end

    @net_counter = 0
    @number_of_networks = encnets.size + unencnets.size
    if (@number_of_networks == 0)
      return false
    end

    true

    #exit(0)
  end

  def attach
    if (@net_counter.to_i >= @number_of_networks.to_i)
      puts "I'm out of networks to which I can attach."
      return ATTACH_OUT
    end
    puts "Attaching to Network #{@net_counter+1} of #{@number_of_networks}."

    exec.wpa_cli_select(@net_counter)

    @net_counter += 1

    sleep(5)
    stat = @exec.wpa_cli_status

    if (stat =~ /COMPLETED/)
      return ATTACH_SUCCESS
    elsif (@net_counter.to_i >= @number_of_networks.to_i)
      return ATTACH_OUT
    else
      return ATTACH_FAIL
    end

  end

  def dhcp
    puts "DCHP-ing"

    exec.dhclient_release(@device)
    exec.dhclient(@device)

    if @exec.exitstatus != 0
      return false
    else
      return true
    end

  end

  def conncheck
    puts "Checking Connection"
    begin
      @page = @agent.get(TESTPAGE)
      if (@page.title == "Success") #Could add other checks here.
        true
      else
        false
      end
    rescue => e
      puts "Crash during connection checking, so that's a no."
      false
    end
  end

  def runbreak
    puts "Portal Breaking"
    return if @page.nil?
    if (@page.forms.size == 1 && @page.forms[0].buttons.size == 1)
      f = @page.forms[0]
      f.submit(f.buttons[0])
    elsif (@page.forms.size == 1 && @page.forms[0].buttons.size == 0)
      p2 = @page.forms[0].submit
      if (p2.forms[0].buttons.size == 1)
        #WanderingWifi
        #This is sick, but truthfully this works. Shocking.
        f2 = p2.forms[0]
        p3 = f2.submit(f2.buttons[0])
        p4 = p3.forms[0].submit
        p5 = p4.forms[0].submit
        p6 = p5.forms[0].submit
        p7 = p6.forms[0].submit
        p8 = agent.get('http://portals.wanderingwifi.com:8080/session.asp')
      end
    end
  end

  def killthings
    exec.pkill_wpa_supplicant
    exec.pkill_dhclient
    exec.ifconfig_up(@device)
  end

  def startwpa
    exec.wpa_supplicant(device)
    if exec.exitstatus != 0
      return false
    else
      return true
    end
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
    while @running
      #sleep 1
      puts ""
      puts "State: #{@state}"
      case @state
      when :start
        killthings
        @scan_success = scan
        if @scan_success
          @state = :list
          if startwpa == false
            @state = :start
            puts "Failed to start wpa_supplicant. Are you root?"
            sleep(2)
          end
        else
          @state = :start
          puts "Scan failed using #{@device}."
          sleep(2)
        end
      when :list
        @attach_state = attach
        case @attach_state
        when ATTACH_SUCCESS
          @state = :attached
        when ATTACH_FAIL
          @state = :list
        when ATTACH_OUT
          @state = :start
        end
      when :attached
        @dhcp_success = dhcp
        if @dhcp_success
          @state = :hasip
        else
          @state = :attached
        end
      when :hasip
        @cc_success = conncheck
        if @cc_success
          sendsig
          @state = :monitor
        else
          @state = :breaker
        end
      when :breaker
        runbreak
        @cc_success = conncheck
        if @cc_success
          sendsig
          @state = :monitor
        else
          @state = :list
        end
      when :monitor
        sleep 2
        @cc_success = conncheck
        if @cc_success
          @state = :monitor
        else
          @state = :start
        end
      end
    end
  end
end
