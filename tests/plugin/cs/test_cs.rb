
require 'test/unit'
require 'rant'
require 'rant/plugin/cs'

$testPluginCsDir = File.expand_path(File.dirname(__FILE__))

class TestPluginCs < Test::Unit::TestCase
    def setup
	# Ensure we run in test directory.
	cd($testPluginCsDir) unless Dir.pwd == $testPluginCsDir
    end
    def teardown
	assert(Rant.run("clean"), 0)
    end
    # Try to compile the "hello world" program. Requires cscc, csc
    # or mcs to be on your PATH.
    def test_hello
	assert_equal(Rant.run([]), 0,
	    "first target, `hello.exe', should be compiled")
	assert(File.exist?("hello.exe"))
	if Env.on_windows?
	    assert_equal(`hello.exe`.chomp, "Hello, world!",
		"hello.exe should print `Hello, world!'")
	elsif (ilrun = Env.find_bin("ilrun"))
	    assert_equal(`#{ilrun} hello.exe`.chomp, "Hello, world!",
		"hello.exe should print `Hello, world!'")
	elsif (mono = Env.find_bin("mono"))
	    assert_equal(`#{mono} hello.exe`.chomp, "Hello, world!",
		"hello.exe should print `Hello, world!'")
	else
	    $stderr.puts "Can't run hello.exe for testing."
	end
    end
    def test_opts
	assert_equal(Rant.run("AB.dll"), 0)
	assert(File.exist?("hello.exe"),
	    "AB.dll depends on hello.exe")
	assert(File.exist?("AB.dll"))
    end
    def test_cscc
	old_csc = AssemblyTask.csc
	cscc = Env.find_bin("cscc")
	unless cscc
	    $stderr.puts "cscc not on path, will not test cscc"
	    return
	end
	AssemblyTask.csc = cscc
	test_opts
	AssemblyTask.csc = old_csc
    end
end
