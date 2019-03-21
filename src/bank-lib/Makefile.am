# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

noinst_PROGRAMS = \
  taler-bank-transfer

noinst_PROGRAMS = \
  taler-fakebank-run

taler_fakebank_run_SOURCES = \
  taler-fakebank-run.c
taler_fakebank_run_LDADD = \
  libtalerfakebank.la \
  -lgnunetutil

taler_bank_transfer_SOURCES = \
  taler-bank-transfer.c
taler_bank_transfer_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson $(XLIB)

lib_LTLIBRARIES = \
  libtalerbank.la \
  libtalerfakebank.la \
  libtalerbanktesting.la

libtalerbank_la_LDFLAGS = \
  -version-info 1:0:0 \
  -no-undefined

libtalerbank_la_SOURCES = \
  bank_api_admin.c \
  bank_api_common.c bank_api_common.h \
  bank_api_history.c \
  bank_api_reject.c \
  bank_api_parse.c

libtalerbank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

libtalerfakebank_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerfakebank_la_SOURCES = \
  fakebank.c

libtalerfakebank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lmicrohttpd \
  $(XLIB)

libtalerbanktesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerbanktesting_la_SOURCES = \
  testing_api_cmd_history.c \
  testing_api_cmd_reject.c \
  testing_api_helpers.c

libtalerbanktesting_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lmicrohttpd \
  $(XLIB)

if HAVE_LIBCURL
libtalerbank_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerbank_la_LIBADD += -lgnurl
endif
endif

check_PROGRAMS = \
  test_bank_api \
  test_bank_api_new \
  test_bank_api_with_fakebank \
  test_bank_api_with_fakebank_new

if HAVE_TWISTER
check_PROGRAMS += \
  test_bank_api_twisted \
  test_bank_api_with_fakebank_twisted

test_bank_api_with_fakebank_twisted_SOURCES = \
  test_bank_api_with_fakebank_twisted.c
test_bank_api_with_fakebank_twisted_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  libtalerbank.la \
  libtalerbanktesting.la \
  libtalerfakebank.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  -ltalertwistertesting \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson
endif

test_bank_api_twisted_SOURCES = \
  test_bank_api_twisted.c
test_bank_api_twisted_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  libtalerbank.la \
  libtalerbanktesting.la \
  libtalerfakebank.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  -ltalertwistertesting \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

TESTS = \
  $(check_PROGRAMS)

test_bank_api_SOURCES = \
  test_bank_interpreter.c test_bank_interpreter.h \
  test_bank_api.c
test_bank_api_LDADD = \
  libtalerbank.la \
  libtalerfakebank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_bank_api_new_SOURCES = \
  test_bank_api_new.c

test_bank_api_new_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  $(top_builddir)/src/json/libtalerjson.la \
  libtalerbanktesting.la \
  -ltalerexchange \
  -lgnunetutil \
  libtalerbank.la

test_bank_api_with_fakebank_SOURCES = \
  test_bank_interpreter.c test_bank_interpreter.h \
  test_bank_api_with_fakebank.c
test_bank_api_with_fakebank_LDADD = \
  libtalerbank.la \
  libtalerfakebank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_bank_api_with_fakebank_new_SOURCES = \
  test_bank_api_with_fakebank_new.c

test_bank_api_with_fakebank_new_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  libtalerbanktesting.la \
  -ltalerexchange \
  -lgnunetutil \
  libtalerbank.la

EXTRA_DIST = \
  bank.conf
