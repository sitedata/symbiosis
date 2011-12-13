#!/usr/bin/ruby
#
#  Simple FTP test - create a new domain and attempt to login with the
# new credentials.
#

require 'symbiosis/domain/ftp'
require 'net/ftp'
require 'test/unit'

class TestFTP < Test::Unit::TestCase

  def setup
    #
    #  Create the domain
    #
    @domain = Symbiosis::Domain.new()
    @domain.create()

    #
    #  Set the password to a random string.
    #
    @domain.ftp_password = Symbiosis::Utils.random_string()
  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domain.destroy()
  end

  def test_login
    #
    #  Attempt a login, and report on the success.
    #
    assert_nothing_raised("Login failed") do
      Net::FTP.open('localhost') do |ftp|
        ftp.login( @domain.name, @domain.ftp_password )
      end
    end
  end


  def test_quota
    quota_file = File.join(@domain.directory,"ftp-quota")
    [[1e6, "1M"],
     [2.5e9, "2.5G"],
     [300,"300 "]
     [300e6,"300 M"]
    ].each do |expected,contents|
      #
      # Make sure no quota has been set.
      #
      File.unlink(quota_file) if File.exists?(quota_file)

      File.open(quota_file,"a+") do |fh|
        fh.puts contents
      end
      assert_equal(expected, @domain.ftp_quota)
      #
      # Delete it again
      #
      File.unlink(quota_file)

      #
      # Set the contents
      #
      @domain.ftp_quota = contents

      new_contents = File.read(quota_file)
      assert_equal(contents, new_contents)
    end

  end

end
