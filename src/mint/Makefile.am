# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

plugindir = $(libdir)/taler

plugin_LTLIBRARIES = \
  libtaler_plugin_mintdb_postgres.la

EXTRA_DIST = plugin_mintdb_common.c

libtaler_plugin_mintdb_postgres_la_SOURCES = \
  plugin_mintdb_postgres.c
libtaler_plugin_mintdb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_mintdb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  -lpq \
  -lgnunetutil

lib_LTLIBRARIES = \
  libtalermint_common.la

libtalermint_common_la_SOURCES = \
  key_io.c key_io.h \
  plugin.c plugin.h \
  taler_mintdb_plugin.h

libtalermint_common_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil

libtalermint_common_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined


bin_PROGRAMS = \
  taler-mint-keyup \
  taler-mint-keycheck \
  taler-mint-reservemod \
  taler-mint-httpd \
  taler-mint-dbinit

taler_mint_keyup_SOURCES = \
  taler-mint-keyup.c

taler_mint_keyup_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lpq \
  -lgnunetutil
taler_mint_keyup_LDFLAGS = $(POSTGRESQL_LDFLAGS)


taler_mint_keycheck_SOURCES = \
  taler-mint-keycheck.c

taler_mint_keycheck_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lgnunetutil \
  -lpq
taler_mint_keycheck_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_mint_reservemod_SOURCES = \
  taler-mint-reservemod.c
taler_mint_reservemod_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lpq \
  -lgnunetutil
taler_mint_reservemod_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)

taler_mint_httpd_SOURCES = \
  taler-mint-httpd.c \
  taler-mint-httpd_keystate.c taler-mint-httpd_keystate.h \
  taler-mint-httpd_db.c taler-mint-httpd_db.h \
  taler-mint-httpd_parsing.c taler-mint-httpd_parsing.h \
  taler-mint-httpd_responses.c taler-mint-httpd_responses.h \
  taler-mint-httpd_mhd.c \
  taler-mint-httpd_deposit.c \
  taler-mint-httpd_withdraw.c \
  taler-mint-httpd_refresh.c
taler_mint_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lpq \
  -lmicrohttpd \
  -ljansson \
  -lgnunetutil \
  -lpthread
taler_mint_httpd_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)


taler_mint_dbinit_SOURCES = \
  taler-mint-dbinit.c
taler_mint_dbinit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lpq \
  -lgnunetutil
taler_mint_dbinit_LDFLAGS = $(POSTGRESQL_LDFLAGS)

check_PROGRAMS = \
  test-mint-deposits \
  test-mint-common \
  test-mint-db-postgres

test_mint_deposits_SOURCES = \
  test_mint_deposits.c
test_mint_deposits_LDADD = \
  libtalermint_common.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil \
  -ljansson \
  -lpq

test_mint_common_SOURCES = \
  test_mint_common.c
test_mint_common_LDADD = \
  libtalermint_common.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil

test_mint_db_postgres_SOURCES = \
  test_mint_db.c
test_mint_db_postgres_LDADD = \
  libtalermint_common.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil -ljansson
EXTRA_test_mint_db_postgres_DEPENDENCIES = \
  libtaler_plugin_mintdb_postgres.la
