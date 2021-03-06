Package.define('gcc') { type 'compiler'
  tags 'application', 'compiler', 'system', 'development', 'gnu'

  description 'The GNU Compiler Collection'
  homepage    'http://gcc.gnu.org/'
  license     'GPL-3', 'LGPL-3'

  maintainer 'meh. <meh@paranoici.org>'

  source 'gnu://gcc/#{version}'

  flavor {
    multilib {
      before :configure do |conf|
        conf.enable 'multilib', enabled?
      end
    }

    hardened {

    }
  }

  features {
    ada {
      before :build do |pkg|
        pkg.languages << 'ada' if enabled?
      end
    }

    cxx { enabled!
      before :build do |pkg|
        pkg.languages << 'c++' if enabled?
      end
    }

    fortran {
      before :build do |pkg|
        pkg.languages << 'fortran' if enabled?
      end
    }

    java {
      before :build do |pkg|
        pkg.languages << 'java' if enabled?
      end
    }
    
    objc {
      before :build do |pkg|
        pkg.languages << 'objc' if enabled?
      end
    }

    objcxx {
      before :build do |pkg|
        pkg.languages << 'objcp' if enabled?
      end
    }

    optimizations { enabled!
      before :configure do |conf|
        conf.enable 'altivec', (enabled? && ['ppc', '~ppc'].member?(package.environment[:ARCH]))
        conf.enable 'fixed-point', (enabled? && ['mips', '~mips'].member?(package.environment[:ARCH]))
      end
    }

    nls {
      before :configure do |conf|
        if enabled?
          conf.enable 'nls'
          conf.disable 'included-gettext'
        else
          conf.disable 'nls'
        end
      end
    }

    openmp {

    }
  }

  after :initialize do
    package.languages = ['c']
  end

  after :initialized do
  end

  before :dependencies do |deps|
    if target.kernel == 'cygwin'
      if host != target
        deps << "library/system/development/cygwin%#{target}!"
      else
        deps << 'library/system/development/cygwin!'
      end
    end
  end

  before :configure do |conf|
    if host != target
      env[:CPP] = "cpp --sysroot /usr/#{host}/#{target}"

      conf.with 'sysroot', "/usr/#{host}/#{target}"
      conf.with 'as',      "/usr/bin/#{target}-as"
      conf.with 'ld',      "/usr/bin/#{target}-ld"

      env[:CXXFLAGS] = env[:CFLAGS] = '-O2 -pipe'

      middle = "#{host}/#{target}"
    else
      env[:CXXFLAGS].replace '-O.', '-O2'
      env[:CFLAGS].replace   '-O.', '-O2'

      middle = target.to_s
    end

    Do.dir "#{workdir}/build"
    Do.cd  "#{workdir}/build"

    conf.path = "#{workdir}/gcc-#{version}/configure"

    env[:GCC_LANG]      = package.languages.join(',')
    env[:PREFIX]        = (env![:INSTALL_PATH] + '/usr').cleanpath
    env[:BINPATH]       = (env![:INSTALL_PATH] + "/usr/#{middle}/gcc-bin/#{version}").cleanpath
    env[:LIBPATH]       = (env![:INSTALL_PATH] + "/usr/lib/gcc/#{middle}/#{version}").cleanpath
    env[:DATAPATH]      = (env![:INSTALL_PATH] + "/usr/share/gcc-data/#{middle}/#{version}").cleanpath
    env[:STDCXX_INCDIR] = (env![:INSTALL_PATH] + "/usr/lib/gcc/#{middle}/#{version}/include/g++v4").cleanpath
    
    conf.set 'prefix',  "/usr"
    conf.set 'bindir',  "/usr/#{middle}/gcc-bin/#{version}"
    conf.set 'datadir', "/usr/share/gcc-data/#{middle}/#{version}"
    conf.set 'mandir',  "/usr/share/gcc-data/#{middle}/#{package.version}/man"
    conf.set 'infodir', "/usr/share/gcc-data/#{middle}/#{package.version}/info"

    conf.with 'gxx-include-dir', "/usr/lib/gcc/#{middle}/#{version}/include/g++v4"
    conf.with 'python-dir',      "/usr/share/gcc-data/#{middle}/#{version}/python"

    conf.enable  ['secureplt', 'shared']
    conf.disable ['werror', 'libmudflap', 'libssp', 'libgomp', 'bootstrap']
    conf.with    ['system-zlib']
    conf.without ['ppl', 'cloog']

    # c, c++, fortran, ada, java, objc, objcp
    conf.enable 'languages', package.languages.join(',')

    conf.enable 'checking',   'release'
    conf.with   'pkgversion', "Distrø #{version}"

    # Various conditional configurations

    case host
      when 'mingw*', '*-mingw*', '*-cygwin'
        conf.enable 'threads', 'win32'

      when '*-mint*'
        conf.disable 'threads'

      else
        conf.enable 'threads', 'posix'
    end

    if target.kernel == 'darwin'
      conf.enable 'version-specific-runtime-libs'
    end

    if target.kernel == 'freebsd' || target.misc == 'gnu' || target.kernel == 'solaris'
      conf.enable '__cxa_atexit'
    else
      conf.disable '__cxa_atexit'
    end

    if target.misc == 'gnu'
      conf.enable 'clocale', 'gnu'
    end

    if environment[:LIBC] == 'newlib'
      conf.with 'newlib'
    end
  end

  before :compile do
    autotools.make "-j#{env[:MAKE_JOBS] || 1}",
      "LDFLAGS=#{env[:LDFLAGS]}",
      "STAGE1_CFLAGS=#{env[:STAGE1_CFLAGS] || env[:CFLAGS]}",
      "BOOT_CFLAGS=#{env[:BOOT_CFLAGS] || env[:CFLAGS]}"

    skip
  end

  before :pack do
    remove = []

    `gcc -print-multi-lib`.split("\n").map {|dir|
      dir.split(';').first
    }.each {|dir|
      multidir    = `gcc "#{dir}" --print-multi-directory`.strip
      multidir_os = `gcc "#{dir}" --print-multi-os-directory`.strip
      todir       = "#{package.distdir}/#{env[:LIBPATH]}/#{multidir}"

      Do.dir(todir)

      ["#{env[:LIBPATH]}/#{multidir}", "#{env[:LIBPATH]}/../#{multidir_os}",
       "#{env[:PREFIX]}/lib/#{multidir_os}", "#{env[:PREFIX]}/#{target}/lib/#{multidir_os}",
       "#{env[:PREFIX]}/lib/#{multidir}"
      ].map {|dir|
        "#{package.distdir}/#{dir}"
      }.each {|dir|
        next if dir == todir || !File.directory?(dir)

        Do.cp Dir.glob("#{dir}/*").map {|file|
          next if File.directory?(file)

          remove << file

          file
        }.compact, todir
      }
    }

    remove.each {|file|
      Do.rm file
    }
  end
}

__END__
$$$

$$$ patches/libstdc++-v3/crossconfig.patch $$$

--- crossconfig.m4.orig	2010-12-07 02:47:04.951291393 +0000
+++ crossconfig.m4	2010-12-07 02:48:51.926279025 +0000
@@ -193,7 +193,7 @@
 	;;
     esac
     ;;
-  *-linux* | *-uclinux* | *-gnu* | *-kfreebsd*-gnu | *-knetbsd*-gnu)
+  *-linux* | *-uclinux* | *-gnu* | *-kfreebsd*-gnu | *-knetbsd*-gnu | *-cygwin*)
     AC_CHECK_HEADERS([nan.h ieeefp.h endian.h sys/isa_defs.h \
       machine/endian.h machine/param.h sys/machine.h sys/types.h \
       fp.h float.h endian.h inttypes.h locale.h float.h stdint.h \
