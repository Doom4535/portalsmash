#!/usr/bin/ruby

require 'rubygems'
require 'yaml'

class Scanner

  #Variables for seeing what it's doing right now - not modifiable outside the class
  attr_reader :number_of_networks, :net_counter, :exec

  CONFPATH = '/tmp/portalsmash.conf'

  def initialize(dev, file, exec)
    @exec = exec

    @number_of_networks = 0
    @net_counter = 0

    #Storage variables internal to the class (No accessors)
    @device = dev
    @knownnetworks = {}

    if file
      @knownnetworks = YAML.load_file(file)
    end
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

end
