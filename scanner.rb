#!/usr/bin/ruby

require 'rubygems'
require_relative 'log'

class Scanner

  attr_reader :number_of_networks, :exec

  CONFPATH = '/tmp/portalsmash.conf'

  def initialize(dev, known_networks, exec)
    @exec = exec
    @logger = Log.new
    @number_of_networks = 0
    @device = dev
    @known_networks = known_networks
  end

  def network_string(net,ssid,enc)
    str = ""
    str += "network={\n"
    str += "ssid=\"#{ssid}\"\n"
    str += "scan_ssid=1\n"
    if (enc == "on")
      # This is just a brutal hack.
      # I can be a lot more precise-- specifying CCMP and the like-- but it doesn't matter, weirdly.

      key = @known_networks[ssid]['key']
      if net =~ /WPA/
        if (key) #Then it's WPA-PSK
          str += "key_mgmt=WPA-PSK\n"
          str += "psk=\"#{key}\"\n"
        else #Then it's WPAE
          str += "key_mgmt=WPA-EAP\n"
          str += "identity=\"#{@known_networks[ssid]['username']}\"\n"
          str += "password=\"#{@known_networks[ssid]['password']}\"\n"
        end
      else #WEP
        str += "key_mgmt=NONE\n"
        str += "wep_tx_keyidx=0\n"
        str += "wep_key0=\"#{key}\"\n"
      end

    else
      str += "key_mgmt=NONE\n"
    end
    str += "}\n"
  end

  def networks
    networklist = exec.iwlist(@device)

    if (exec.exitstatus != 0)
      return [] #iwlist didn't work right.
    end

    cells = networklist.split(/Cell \d{2}/); #This will give us cell 1 in @networks[1], as [0] will hold junk
    cells.delete_at(0)
    cells
  end

  def write_config(encnets,unencnets)
    File.open(CONFPATH, "w") do |f|
      f.puts "ctrl_interface=DIR=/var/run/wpa_supplicant"

      log "Encnets: #{encnets.size} Unencnets: #{unencnets.size}"

      encnets.each do |s|
        f.puts s
      end

      unencnets.each do |s|
        f.puts s
      end

    end
  end

  def scan
    log "Scanning"

    encnets = []
    unencnets = []
    usednetworks = {}

    networks.each do |net|
      data = net.split(/\n/)
      bssid = data[0].match(/([A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2})/)[1]
      ssid = data[5].match(/ESSID\:\"(.*)\"/)[1]
      enc = data[4].match(/Encryption key:(.+)/)[1]

      #So, only proceed if either we know the network, or if there's no encryption -- and either way, only
      #if we haven't done this network before (to prevent trying to connect to 80 different instances of
      #the same WiFi network)
      if (!usednetworks[ssid] and ((enc == "off") or (@known_networks[ssid])))
        str = network_string(net,ssid,enc)
        usednetworks[ssid] = 1

        if @known_networks[ssid]
          encnets.push(str)
        else
          unencnets.push(str)
        end

      end
    end

    write_config(encnets,unencnets)
    @number_of_networks = encnets.size + unencnets.size
    @number_of_networks != 0
  end

  def log(message)
    @logger.log message
  end

end
