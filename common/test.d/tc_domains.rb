require 'test/unit'
require 'tmpdir'
require 'symbiosis/domains'

class TestDomain < Test::Unit::TestCase

 include Symbiosis

  def setup
    @prefix = Dir.mktmpdir("srv")
    File.lchown(1000,1000,@prefix) if 0 == Process.uid
    @prefix.freeze
  end

  def teardown
    FileUtils.rm_rf(@prefix) if File.directory?(@prefix)
  end

  def test_all
    domains = []
    5.times do
      d = Symbiosis::Domain.new(nil, @prefix)
      d.create
      domains << d
    end
    assert_equal(5, domains.length, "Wrong number of domains created (how?!)")

    all = Symbiosis::Domains.all(@prefix)

    assert_equal(5, all.length)
    assert(all.all?{|d| d.is_a?(Domain)}, "Domains#all returned something other than a Domain.")
    assert_equal(domains.collect{|d| d.name}.sort, all.collect{|d| d.name}.sort)
  end

  def test_find
    found = Domains.find("does-not-exist.org")
    assert_nil(found, "Domains#find found a domain when nothing should exist.")

    found = Domains.find(".")
    assert_nil(found, "Domains#find found a domain when nothing should exist.")

    #
    # Test finding evil domains
    #
    found = Domains.find('$(/bin/ls > /tmp/ls)')
    assert_nil(found, "Domains#find found a domain when nothing should exist.")

    found = Domains.find('`/bin/ls > /tmp/ls`')
    assert_nil(found, "Domains#find found a domain when nothing should exist.")

    #
    # Now create a domain and test that.
    #
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    assert_equal(1, Symbiosis::Domains.all(@prefix).length, "Wrong number of domains returned by Domains#all)")

    found = Domains.find(domain.name, @prefix)
    assert_kind_of(Domain, found, "Domains#find returned the wrong class")
    assert_equal(domain.name, found.name, "Domains#find found a domain other than the one were were looking for.")

    #
    # Try to find the same domain again, except with a "www." prefix.
    #
    found = Domains.find("www."+domain.name, @prefix)
    assert_kind_of(Domain, found, "Domains#find returned the wrong class")
    assert_equal(domain.name, found.name, "Domains#find found a domain other than the one were were looking for.")

    #
    # Now create the domain with a www. prefix, and see if find returns that ok.
    #
    www_domain = Symbiosis::Domain.new("www."+domain.name, @prefix)
    www_domain.create
    www_found = Domains.find(www_domain.name, @prefix)

    assert_equal(2, Symbiosis::Domains.all(@prefix).length, "Wrong number of domains returned by Domains#all)")

    assert_kind_of(Domain, www_found, "Domains#find returned the wrong class")
    assert_equal(www_domain.name, www_found.name, "Domains#find found a domain other than the one were were looking for.")
    
    #
    # Try to find the same domain again, except without the "www." prefix.
    #
    found = Domains.find(domain.name, @prefix)
    assert_kind_of(Domain, found, "Domains#find returned the wrong class")
    assert_equal(domain.name, found.name, "Domains#find found a domain other than the one were were looking for.")

    #
    # Try to find a domain with a random prefix.
    #
    random_prefix = Symbiosis::Utils.random_string(5).downcase
    random_www_domain = ((random_prefix+".")*10)+www_domain.name
    random_www_found = Domains.find(random_www_domain, @prefix)

    #
    # We should get the same answers as before
    #
    assert_equal(2, Symbiosis::Domains.all(@prefix).length, "Wrong number of domains returned by Domains#all)")

    assert_kind_of(Domain, random_www_found, "Domains#find returned the wrong class")
    assert_equal(www_domain.name, www_found.name, "Domains#find found a domain other than the one were were looking for.")

    #
    # Try and find one that is an alias.
    #
    symlink_domain = "www2."+domain.name
    File.symlink(domain.directory, File.join(@prefix, symlink_domain))
    found = Domains.find(symlink_domain, @prefix)

    assert_equal(3, Symbiosis::Domains.all(@prefix).length, "Wrong number of domains returned by Domains#all)")
    assert_equal(symlink_domain, found.name, "Domains#find found a domain other than the one were were looking for.")
    assert(found.aliases.include?(domain.name), "Domains#find did not return a domain with the correct aliases")
  end

  def test_include?
    # TODO
  end
end
