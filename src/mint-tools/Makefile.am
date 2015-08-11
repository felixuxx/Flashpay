# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-mint-keyup \
  taler-mint-keycheck \
  taler-mint-reservemod \
  taler-mint-sepa \
  taler-mint-dbinit

taler_mint_keyup_SOURCES = \
  taler-mint-keyup.c

taler_mint_keyup_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mintdb/libtalermintdb.la \
  -lgnunetutil $(XLIB)
taler_mint_keyup_LDFLAGS = $(POSTGRESQL_LDFLAGS)


taler_mint_sepa_SOURCES = \
  taler-mint-sepa.c
taler_mint_sepa_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil -ljansson $(XLIB)
taler_mint_sepa_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_mint_keycheck_SOURCES = \
  taler-mint-keycheck.c
taler_mint_keycheck_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/mintdb/libtalermintdb.la \
  -lgnunetutil  $(XLIB)
taler_mint_keycheck_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_mint_reservemod_SOURCES = \
  taler-mint-reservemod.c
taler_mint_reservemod_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mintdb/libtalermintdb.la \
  -lgnunetutil -ljansson $(XLIB)
taler_mint_reservemod_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)
taler_mint_reservemod_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)

taler_mint_dbinit_SOURCES = \
  taler-mint-dbinit.c
taler_mint_dbinit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mintdb/libtalermintdb.la \
  -lgnunetutil  $(XLIB)
taler_mint_dbinit_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)
taler_mint_dbinit_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)
