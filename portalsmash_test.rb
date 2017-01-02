require "minitest/autorun"
require_relative 'portalsmash'

class TestPortalSmasher < Minitest::Unit::TestCase

  attr :dev, :sig, :known_networks, :exec, :go, :scanner, :smasher, :timer, :logger, :ps

  def setup
    @dev     = 'dev'
    @sig     = 'sig'
    @known_networks = {}
    @exec    = Exec.new
    @go      = Go.new(dev,sig,exec)
    @scanner = Scanner.new(dev,known_networks,exec)
    @smasher = Smasher.new
    @timer   = Timer.new
    @logger  = Log.new
    @ps = PortalSmasher.new(dev, scanner, smasher, go, timer, logger)
  end

  def test_can_create
    assert ps != nil
  end

end
