#!/usr/bin/ruby

class Exec

  CONFPATH = '/tmp/portalsmash.conf'
  DHCP_CONFIG = File.dirname(__FILE__)+'/dhclient.conf'

  def exitstatus
    $?.exitstatus
  end

  def iwlist(device)
    `iwlist #{device} scan`;
  end

  def wpa_cli_select(net_counter)
    `wpa_cli select #{net_counter}`
  end

  def wpa_cli_status
    `wpa_cli status`
  end

  def dhcpclient_release(device)
    #DHCP Release, and tells any old DHClients to let go of @device
    `dhclient #{device} -cf #{DHCP_CONFIG} -r`
  end

  def dhcpclient(device)
    #Try just once, with timeout specified in DHCP_CONFIG
    `dhclient #{device} -cf #{DHCP_CONFIG} -1`
  end

  def pkill_wpa_supplicant
    `pkill -KILL wpa_supplicant`
  end

  def pkill_dhclient
    `pkill -KILL dhclient`
  end

  def ifconfig_up(device)
    #because when we've killed this, sometimes it stays down.
    `ifconfig #{device} up`
  end

  def wpa_supplicant(device)
    `wpa_supplicant -B -i #{device} -c #{CONFPATH}`
  end

  def kill(pid)
    `kill -s SIGUSR1 #{pid}`
  end

end
