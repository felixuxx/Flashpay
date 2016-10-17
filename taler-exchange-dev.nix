{ stdenv, makeWrapper, pkgconfig, autoconf, automake, libtool, ccache, ccache_dir ? ""
, gnunet-dev, postgresql, jansson, libgcrypt, libgnurl, libmicrohttpd }:

stdenv.mkDerivation rec {
  src = ./.;
  name = "taler-exchange-dev";

  buildInputs = [
    makeWrapper pkgconfig autoconf automake libtool ccache
    gnunet-dev postgresql jansson libgcrypt libgnurl libmicrohttpd
  ];

  patchPhase = ''
    if [ -e Makefile ]; then
      make distclean
    fi
  '';

  NIX_CFLAGS_COMPILE = "-ggdb -O0";

  configureFlags = [
    "--enable-gcc-hardening"
    "--enable-linker-hardening"

    "--enable-logging=verbose"
    "--enable-poisoning"
  ];

  preConfigure = ''
    ./bootstrap

    if [ -n "${ccache_dir}" ]; then
      export CC='ccache gcc'
      export CCACHE_COMPRESS=1
      export CCACHE_DIR="${ccache_dir}"
      export CCACHE_UMASK=007
    fi
  '';

  doCheck = false;

  postInstall = ''
    # Tests can be run this way
    #export GNUNET_PREFIX="$out"
    #export PATH="$out/bin:$PATH"
    #make -k check
  '';

  meta = with stdenv.lib; {
    description = "Exchange for GNU Taler";

    longDescription = ''
    '';

    homepage = https://taler.net/;

    license = licenses.gpl3Plus;
    platforms = platforms.gnu;
    maintainers = with maintainers; [ ];
  };
}
