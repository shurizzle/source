Package.define('vim', '7.3.162') {
  arch     '~x86', '~amd64'
  kernel   'linux'
  compiler 'gcc'
  libc     'glibc'

  autotools.version :autoconf, '2.6'
}
