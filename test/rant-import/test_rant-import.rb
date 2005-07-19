
require 'test/unit'
require 'rant/rantlib'
require 'tutil'
require 'fileutils'

$testRantImportDir ||= File.expand_path(File.dirname(__FILE__))

class TestRantImport < Test::Unit::TestCase
    def setup
	# Ensure we run in test directory.
	Dir.chdir($testRantImportDir)
    end
    def teardown
	Dir.chdir($testRantImportDir)
	FileUtils.rm_f Dir["ant*"]
	FileUtils.rm_f Dir["make*"]
	FileUtils.rm_rf Dir["*.t"]
    end
    def test_no_import
	run_import("--quiet", "make.rb")
	assert(test(?f, "make.rb"))
	assert(!test(?f, "action.t"))
	assert_equal(run_rant("hello"), run_ruby("make.rb", "hello"))
	assert(test(?f, "action.t"))
    end
    def test_import_from_custom_lib
	FileUtils.mkpath "mylib.t/rant/import"
	open("mylib.t/rant/import/mygen.rb", "w") { |f|
	    f << <<-EOF
	    mygen = Object.new
	    def mygen.rant_gen(rac, ch, args, &block)
		tn = args.first || "mygen"
		rac.task(:__caller__ => ch, tn => []) do |t|
		    puts "Greetings from `" + t.name + "', generated by MyGen."
		    rac.cx.sys.touch t.name
		end
	    end
	    Rant::Generators::MyGen = mygen
	    EOF
	}
	open("mygen.rf.t", "w") { |f|
	    f << <<-EOF
	    $:.unshift "mylib.t"
	    import "mygen"
	    desc "task created by mygen"
	    gen MyGen
	    EOF
	}
	out, err = capture_std do
	    assert_equal(0, Rant::RantApp.new.run("-fmygen.rf.t"))
	end
	assert_match(/Greetings.*mygen/, out)
	assert(test(?f, "mygen"))
	FileUtils.rm_f "mygen"
	assert(!test(?e, "mygen"))
	run_import("--quiet", "-fmygen.rf.t", "ant")
	assert(test(?f, "ant"))
	FileUtils.rm_r "mylib.t"
	out = run_ruby("ant", "-fmygen.rf.t")
	assert_match(/Greetings.*mygen/, out)
	assert(test(?f, "mygen"))
    ensure
	FileUtils.rm_f "mygen"
    end
    def test_import_subdir
	old_pwd = Dir.pwd
	FileUtils.mkdir "sub.t"
	Dir.chdir "sub.t"
	FileUtils.mkpath "lib.t/rant/import/sub"
	open("lib.t/rant/import/sub/t.rb", "w") { |f|
	    f << <<-EOF
	    module Rant::Generators
		module Sub
		    class T
			def self.rant_gen(rac, ch, args, &blk)
			    raise "no ch" unless Hash === ch
			    rac.cx.task args.first do |t|
				puts args
				puts "block_given" if block_given?
			    end
			end
		    end
		end
	    end
	    EOF
	}
	open("Rantfile.rb", "w") { |f|
	    f << <<-EOF
	    $:.unshift "lib.t"
	    import "sub/t"
	    gen Sub::T, "hello", "test" do end
	    EOF
	}
	out, err = assert_rant
	assert_match(/.*hello.*\n.*test.*\n.*block_given/, out)
	run_import("--quiet", "--auto", "ant")
	assert(test(?f, "ant"))
	FileUtils.rm_r "lib.t"
	out = run_ruby("ant")
	assert_match(/.*hello.*\n.*test.*\n.*block_given/, out)
    ensure
	Dir.chdir old_pwd
	FileUtils.rm_rf "sub.t"
    end
    def test_import_marked_require
	old_pwd = Dir.pwd
	FileUtils.mkdir "sub2.t"
	Dir.chdir "sub2.t"
	FileUtils.mkpath "lib.t/rant/import/sub2"
	FileUtils.mkdir "lib.t/misc"
	open("lib.t/misc/printer.rb", "w") { |f|
	    f << <<-EOF
	    def misc_print(*args)
		puts args.flatten.join('')
	    end
	    EOF
	}
	open("lib.t/rant/import/sub2/t.rb", "w") { |f|
	    f << <<-EOF
	    require 'misc/printer' # rant-import
	    module Rant::Generators
		module Sub2
		    class T
			def self.rant_gen(rac, ch, args, &blk)
			    rac.cx.task args.first do |t|
				misc_print(args)
			    end
			end
		    end
		end
	    end
	    EOF
	}
	open("rantfile.rb", "w") { |f|
	    f << <<-EOF
	    $:.unshift "lib.t"
	    import "sub2/t"
	    gen Sub2::T, "hello", "test" do end
	    EOF
	}
	out, err = assert_rant
	assert_match(/hellotest/, out)
	run_import("--quiet", "--auto", "ant.rb")
	assert(test(?f, "ant.rb"))
	FileUtils.rm_r "lib.t"
	out = run_ruby("ant.rb")
	assert_match(/hellotest/, out)
    ensure
	Dir.chdir old_pwd
	FileUtils.rm_rf "sub2.t"
    end
    def test_sys_shun
	FileUtils.mkdir "a.t"
	FileUtils.mkdir "b.t"
	FileUtils.touch %w(a.t/1.s.t a.t/2.s.t a.t/xy.s.t b.t/b.s.t)
	out = run_rant("-q", "sys_shun_demo")
	files = out.strip.split "\n"
	assert_equal(1, files.size)
	assert(files.include?("b.t/b.s.t"))
	run_import("-q", "--auto", "ant")
	assert(test(?f, "ant"))
	out = run_ruby("ant", "-q", "sys_shun_demo")
	files = out.strip.split "\n"
	assert_equal(1, files.size)
	assert(files.include?("b.t/b.s.t"))
    end
    def test_loaded_features
        FileUtils.mkdir "features.t"
        Dir.chdir "features.t"
        FileUtils.mkpath "rant/import"
        open "rant/import/t_loaded_features_foo.rb", "w" do |f|
            f << <<-EOF
            def t_loaded_features_foo
                puts "t_loaded_features_foo"
            end
            EOF
        end
        open "Rantfile", "w" do |f|
            f << <<-EOF
            import "t_loaded_features_foo"
            require 'rant/import/t_loaded_features_foo'
            task :default do
                t_loaded_features_foo
            end
            EOF
        end
        out, err = assert_rant
        assert_match(/t_loaded_features_foo/, out)
        assert(err.empty?)
        run_import("-q", "--auto", "make.rb")
        assert_exit
        assert(test(?f, "make.rb"))
        out = run_ruby("make.rb")
        assert_exit
        assert_match(/t_loaded_features_foo/, out)
        FileUtils.rm_rf "rant"
        out = run_ruby("make.rb")
        assert_exit
        assert_match(/t_loaded_features_foo/, out)
    end
    def test_init_import
        FileUtils.mkdir "init.t"
        Dir.chdir "init.t"
        FileUtils.mkpath "rant/import"
        open "rant/import/t_init_import_foo.rb", "w" do |f|
            f << <<-EOF
            module Rant
                def self.init_import_t_init_import_foo(rac, *rest)
                    puts "init import t_init_import_foo"
                    rac.cx.var["t_init_import_foo"] = "t_init_import_foo init"
                end
            end
            EOF
        end
        open "Rantfile", "w" do |f|
            f << <<-EOF
            import "t_init_import_foo"
            task :a do |t|
                puts var[:t_init_import_foo]
            end
            import "t_init_import_foo"
            EOF
        end
        out, err = assert_rant
        assert_match(/\Ainit import t_init_import_foo\nt_init_import_foo init\n\n?\Z/m, out)
        assert(err.empty?)
        run_import("-q", "--auto", "make.rb")
        assert_exit
        assert(test(?f, "make.rb"))
        out = run_ruby("make.rb")
        assert_exit
        assert_match(/\Ainit import t_init_import_foo\nt_init_import_foo init\n\n?\Z/m, out)
        FileUtils.rm_rf "rant"
        out = run_ruby("make.rb")
        assert_exit
        assert_match(/\Ainit import t_init_import_foo\nt_init_import_foo init\n\n?\Z/m, out)
    end
end
