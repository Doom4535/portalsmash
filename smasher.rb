#!/usr/bin/ruby

require 'rubygems'
require 'mechanize'

class Smasher

  TESTPAGE = 'http://www.apple.com/library/test/success.html'

  def initialize()
    @page = nil
    @agent = Mechanize.new
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

end
