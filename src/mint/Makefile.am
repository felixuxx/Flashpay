AM_CPPFLAGS = -I$(top_srcdir)/src/include $(POSTGRESQL_CPPFLAGS)

lib_LTLIBRARIES = \
  libtalermint_common.la

libtalermint_common_la_SOURCES = \
  key_io.c key_io.h \
  mint_db.c

libtalermint_common_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -lpq

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
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lpq \
  -lgnunetutil
taler_mint_keyup_LDFLAGS = $(POSTGRESQL_LDFLAGS)


taler_mint_keycheck_SOURCES = \
  taler-mint-keycheck.c

taler_mint_keycheck_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lgnunetutil \
  -lpq
taler_mint_keycheck_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_mint_reservemod_SOURCES = \
  taler-mint-reservemod.c
taler_mint_reservemod_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
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
  taler-mint-httpd_keys.c \
  taler-mint-httpd_deposit.c \
  taler-mint-httpd_withdraw.c \
  taler-mint-httpd_refresh.c
taler_mint_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
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
  $(top_builddir)/src/mint/libtalermint_common.la \
  -lpq \
  -lgnunetutil
taler_mint_dbinit_LDFLAGS = $(POSTGRESQL_LDFLAGS)

check_PROGRAMS = \
  test-mint-deposits \
  test-mint-common

test_mint_deposits_SOURCES = \
  test_mint_deposits.c
test_mint_deposits_LDADD = \
  libtalermint_common.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -lpq

test_mint_common_SOURCES = \
  test_mint_common.c
test_mint_common_LDADD = \
  libtalermint_common.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil
