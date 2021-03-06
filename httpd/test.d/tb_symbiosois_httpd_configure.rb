#
#
require 'test/unit'
require 'tmpdir'
require 'tempfile'
require 'symbiosis/domain'
require 'symbiosis/domain/http'
require 'symbiosis/host'

class TestSymbiosisHttpdConfigure < Test::Unit::TestCase

  def setup
    @root = Dir.mktmpdir()
    @prefix = File.join(@root,"srv")
    @apache2_dir = File.join(@root,"etc","apache2")
    @ip = Symbiosis::Host.primary_ipv4

    @verbose = (($VERBOSE or $DEBUG) ? " --verbose " : "")

    testd = File.dirname(__FILE__)

    @script = File.expand_path(File.join(testd,"..","sbin","symbiosis-httpd-configure"))
    @script = '/usr/sbin/symbiosis-httpd-configure' unless File.exist?(@script)
    @script += @verbose

    ENV["RUBYLIB"] = $:.join(":")

    FileUtils.mkdir_p(File.join(@root, "etc", "symbiosis", "apache.d"))
    FileUtils.mkdir_p(File.join(@apache2_dir,"sites-available"))
    FileUtils.mkdir_p(File.join(@apache2_dir,"sites-enabled"))
    FileUtils.mkdir_p(@prefix)

    #
    # We don't want to use root for this test where poss.
    #
    if 0 == Process.uid
      File.chown(1000,1000,@prefix)
    end

    %w(non_ssl.template.erb  ssl.template.erb zz-mass-hosting.ssl.template.erb  zz-mass-hosting.template.erb).each do |fn|
      FileUtils.cp(File.join(testd,"..","apache.d",fn), File.join(@root, "etc", "symbiosis", "apache.d"))
    end

  end

  def teardown
    unless $DEBUG
      #
      # Remove the @prefix directory
      #
      FileUtils.remove_entry_secure @root
    else
      puts "Files left at #{@root}"
    end
  end

  def test_new_site_with_and_without_mass_hosting
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name
    FileUtils.mkdir_p(domain.htdocs_dir)

    #
    # These are the files we expect to be in place.
    #
    domain_conf_fn = File.join(@apache2_dir, "sites-enabled", domain.name+".conf")
    mass_hosting_files = %w(zz-mass-hosting.ssl  zz-mass-hosting).collect do |fn|
      File.join(@apache2_dir,"sites-enabled",fn+".conf")
    end

    system("#{@script} --root-dir #{@root} --no-reload")

    assert_equal(0,$?.exitstatus,"#{@script} exited with a non-zero status")

    mass_hosting_files.each do |fn|
      assert(File.exist?(fn), "File #{fn} missing")
    end
    assert(!File.exist?(domain_conf_fn), "File #{domain_conf_fn} present when it should be covered by mass hosting.")

    #
    # Now disable mass hosting and try the same again.
    #
    FileUtils.touch("#{@root}/etc/symbiosis/apache.d/disabled.zz-mass-hosting")

    system("#{@script} --root-dir #{@root} --no-reload")

    assert_equal(0, $?.exitstatus, "#{@script} exited with a non-zero status")

    mass_hosting_files.each do |fn|
      assert(!File.exist?(fn), "File #{fn} still in place despite mass-hosting being disabled.")
    end

    assert(File.exist?(domain_conf_fn), "File #{domain_conf_fn} missing after mass hosting disabled")
  end

  def test_new_site_with_ip
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name
    FileUtils.mkdir_p(domain.htdocs_dir)
    Symbiosis::Utils.set_param( "ip", "10.0.0.1", domain.config_dir)

    snippet_files = ["zz-mass-hosting.ssl.conf",  "zz-mass-hosting.conf", domain.name + ".conf"].collect do |fn|
      File.join(@apache2_dir,"sites-enabled",fn)
    end

    system("#{@script} --root-dir #{@root} --no-reload")

    assert_equal(0, $?.exitstatus, "#{@script} exited with a non-zero status")

    snippet_files.each do |fn|
      assert(File.exist?(fn), "File #{fn} missing")
    end
  end

  def test_site_pruning
    #
    # This is a standard file in sites-available.  It should never be removed.
    #
    unmanaged_config = File.join(@apache2_dir,"sites-enabled","default")
    FileUtils.touch(unmanaged_config)

    #
    # This is another site that has been symlinked in.  Again shouldn't ever be removed.
    #
    symlinked_unmanaged_source = File.join(@apache2_dir, "sites-available", "other-domain.test.conf")
    symlinked_unmanaged_config = symlinked_unmanaged_source.sub("-available","-enabled")
    FileUtils.touch(symlinked_unmanaged_source)
    FileUtils.ln_s(symlinked_unmanaged_source, symlinked_unmanaged_config)

    [unmanaged_config, symlinked_unmanaged_config].each do |fn|
      assert(File.exist?(fn), "Missing config #{fn} before we even start!")
    end

    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name
    FileUtils.mkdir_p(domain.htdocs_dir)
    Symbiosis::Utils.set_param( "ip", "10.0.0.1", domain.config_dir)
    domain_conf_fn = File.join(@apache2_dir, "sites-enabled", domain.name+".conf")

    system("#{@script} --root-dir #{@root} --no-reload")

    assert_equal(0, $?.exitstatus, "#{@script} exited with a non-zero status")

    [unmanaged_config, symlinked_unmanaged_config].each do |fn|
      assert(File.exist?(fn), "Missing config #{fn} which should not have been removed")
    end

    assert(File.exist?(domain_conf_fn), "File #{domain_conf_fn} missing when it should have been generated.")

    FileUtils.remove_entry_secure(domain.directory)

    system("#{@script} --root-dir #{@root} --no-reload")

    [unmanaged_config, symlinked_unmanaged_config].each do |fn|
      assert(File.exist?(fn), "Missing config #{fn} which should not have been removed")
    end

    assert(!File.exist?(domain_conf_fn), "File #{domain_conf_fn} present when it should have been pruned.")

  end

  def test_bug_7593
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name

    #
    # Don't create a public/htdocs directory for this domain and
    # disable mass hosting
    #
    FileUtils.touch("#{@root}/etc/symbiosis/apache.d/disabled.zz-mass-hosting")

    #
    # We don't expect any files to be created, since the domain has no document
    # root, and mass hosting is disabled.
    #
    conf_files = [File.join(@apache2_dir, "sites-enabled", domain.name+".conf")]
    conf_files += %w(zz-mass-hosting.ssl  zz-mass-hosting).collect do |fn|
      File.join(@apache2_dir,"sites-enabled",fn+".conf")
    end

    system("#{@script} --root-dir #{@root} --no-reload")

    assert_equal(0,$?.exitstatus,"#{@script} exited with a non-zero status")

    conf_files.each do |fn|
      assert(!File.exist?(fn), "File #{fn} present, when it shouldn't be.")
    end

  end

  def test_domains_on_command_line
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name
    FileUtils.mkdir_p(domain.htdocs_dir)

    domain2 = Symbiosis::Domain.new(nil, @prefix)
    domain2.create
    name2 = domain2.name
    FileUtils.mkdir_p(domain2.htdocs_dir)

    #
    # These are the files we expect to be in place.
    #
    domain_conf_fn = File.join(@apache2_dir, "sites-enabled", domain.name+".conf")
    domain2_conf_fn = File.join(@apache2_dir, "sites-enabled", domain2.name+".conf")
    #
    # Don't create a public/htdocs directory for this domain and
    # disable mass hosting
    #
    FileUtils.touch("#{@root}/etc/symbiosis/apache.d/disabled.zz-mass-hosting")

    system("#{@script} --root-dir #{@root} --no-reload #{domain.name}")

    assert_equal(0,$?.exitstatus,"#{@script} exited with a non-zero status")

    assert(File.exist?(domain_conf_fn), "File #{domain_conf_fn} is not present when it was on the cmd line.")
    assert(!File.exist?(domain2_conf_fn), "File #{domain2_conf_fn} is present when it wasn't on the cmd line.")

    system("#{@script} --root-dir #{@root} --no-reload #{domain2.name}")

    assert(File.exist?(domain_conf_fn), "File #{domain_conf_fn} is not present when it was on the cmd line.")
    assert(File.exist?(domain2_conf_fn), "File #{domain2_conf_fn} is present when it wasn't on the cmd line.")

    system("#{@script} --root-dir #{@root} --no-reload #{domain2.name}")
  end

  def test_recreate_sites_enabled_links_if_missing
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name
    FileUtils.mkdir_p(domain.htdocs_dir)
    FileUtils.mkdir_p(domain.config_dir)
    Symbiosis::Utils.set_param( "ip", "10.0.0.1", domain.config_dir)

    #
    # These are the files we expect to be in place.
    #
    domain_conf_fn = File.join(@apache2_dir, "sites-enabled", domain.name+".conf")
    zz_mass_hosting_conf_fn = File.join(@apache2_dir, "sites-enabled", "zz-mass-hosting.conf")

    system("#{@script} --root-dir #{@root} --no-reload")

    assert_equal(0,$?.exitstatus,"#{@script} exited with a non-zero status")

    assert(File.exist?(domain_conf_fn), "File #{domain_conf_fn} is not present.")
    assert(File.exist?(zz_mass_hosting_conf_fn), "File #{zz_mass_hosting_conf_fn} is not present.")

    File.unlink(domain_conf_fn)

    system("#{@script} --root-dir #{@root} --no-reload")

    assert(!File.exist?(domain_conf_fn), "File #{domain_conf_fn} has been recreated after it had been manually disabled.")

    system("#{@script} --root-dir #{@root} --no-reload #{domain.name}")

    assert(File.exist?(domain_conf_fn), "File #{domain_conf_fn} is missing when it had been specified on the cmd line.")

    File.unlink(zz_mass_hosting_conf_fn)

    system("#{@script} --root-dir #{@root} --no-reload")

    assert(!File.exist?(zz_mass_hosting_conf_fn), "File #{zz_mass_hosting_conf_fn} has been recreated after it had been manually disabled.")

    system("#{@script} --root-dir #{@root} --no-reload zz-mass-hosting")

    assert(File.exist?(zz_mass_hosting_conf_fn), "File #{zz_mass_hosting_conf_fn} is not present.")

  end

end
