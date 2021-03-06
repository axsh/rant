
require 'test/unit'
require 'rant/rantlib'
require 'tutil'
require 'fileutils'

# Ensure we run in testproject directory.
$testDir ||= File.expand_path(File.dirname(__FILE__))

class TestDirTask < Test::Unit::TestCase
    Directory = Rant::Generators::Directory
    def setup
	Dir.chdir($testDir) unless Dir.pwd == $testDir
	@rac = Rant::RantApp.new
	@cx = @rac.context
    end
    def teardown
	FileUtils.rm_rf Dir["*.t"]
    end
    def args(*args)
	@rac.args.replace(args.flatten)
    end
    def test_return
	dt = @cx.gen Directory, "a.t/b.t"
	assert(Rant::Node === dt)
	assert_equal("a.t/b.t", dt.name,
	    "`gen Directory' should return task for last directory")
	args "--quiet", "a.t/b.t"
	@rac.run
	assert(test(?d, "a.t"))
	assert(test(?d, "a.t/b.t"))
    end
    def test_4_levels
	@cx.gen Directory, "1.t/2/3/4"
	args "-q", "1.t/2/3/4"
	assert_equal(0, @rac.run)
	assert(test(?d, "1.t/2/3/4"))
    end
    def test_basedir_no_create
	out, err = capture_std do
	    assert_equal(1, Rant::RantApp.new.run("basedir.t"))
	end
	assert_match(/\[ERROR\].*basedir\.t/, err)
	assert(!test(?e, "basedir.t"))
    end
    def test_basedir_fail_no_basedir
	out, err = capture_std do
	    assert_equal(1, Rant::RantApp.new.run("basedir.t/a"))
	end
	assert(!test(?e, "basedir.t"))
	assert(!test(?e, "a"))
    end
    def test_basedir_a
	FileUtils.mkdir "basedir.t"
	assert_rant("basedir.t/a")
	assert(test(?d, "basedir.t/a"))
	assert_rant("clean")
	assert(!test(?e, "basedir.t"))
    end
    def test_basedir_a_b
	FileUtils.mkdir "basedir.t"
	assert_rant("basedir.t/a/b")
	assert(test(?d, "basedir.t/a/b"))
	assert_rant("clean")
    end
    def test_basdir_no_b
	FileUtils.mkdir "basedir.t"
	assert_rant(:fail, "basedir.t/b")
	assert_rant("clean")
    end
    def test_description
	FileUtils.mkdir "basedir.t"
	out, err = assert_rant("--tasks")
	assert_match(%r{basedir.t/a/b\s*#.*Make some path}, out)
	assert_rant("clean")
    end
    def test_basedir_with_slash
        open "dir_with_slash.t", "w" do |f|
            f << <<-EOF
            import "autoclean"
            file "a.t/b/c" => "a.t/b" do |t|
                sys.touch t.name
            end
            gen Directory, "a.t/", "b"
            gen AutoClean
            EOF
        end
        assert_rant(:fail, "-fdir_with_slash.t")
        assert(!test(?e, "a.t"))
        FileUtils.mkdir "a.t"
        assert_rant("-fdir_with_slash.t")
        assert(test(?f, "a.t/b/c"))
        out, err = assert_rant("-fdir_with_slash.t")
        assert(out.empty?)
        assert(err.empty?)
        assert_rant("-fdir_with_slash.t", "autoclean")
        assert(test(?d, "a.t"))
        assert(!test(?e, "a.t/b"))
    end
    def test_with_slash
        open "dir_with_slash.t", "w" do |f|
            f << <<-EOF
            import "autoclean"
            file "a.t/b" => "a.t" do |t|
                sys.touch t.name
            end
            gen Directory, "a.t/"
            gen AutoClean
            EOF
        end
        assert_rant("-fdir_with_slash.t")
        assert(test(?f, "a.t/b"))
        out, err = assert_rant("-fdir_with_slash.t")
        assert(out.empty?)
        assert(err.empty?)
        assert_rant("-fdir_with_slash.t", "autoclean")
        assert(!test(?e, "a.t"))
    end
end
