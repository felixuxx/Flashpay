# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-exchange-wire-gateway-client \
  taler-fakebank-run

taler_fakebank_run_SOURCES = \
  taler-fakebank-run.c
taler_fakebank_run_LDADD = \
  libtalerfakebank.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil

taler_exchange_wire_gateway_client_SOURCES = \
  taler-exchange-wire-gateway-client.c
taler_exchange_wire_gateway_client_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson $(XLIB)

lib_LTLIBRARIES = \
  libtalerbank.la \
  libtalerfakebank.la

libtalerbank_la_LDFLAGS = \
  -version-info 1:0:0 \
  -no-undefined
libtalerbank_la_SOURCES = \
  bank_api_admin.c \
  bank_api_common.c bank_api_common.h \
  bank_api_credit.c \
  bank_api_debit.c \
  bank_api_transfer.c \
  bank_api_parse.c
libtalerbank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lcurl \
  $(XLIB)

libtalerfakebank_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerfakebank_la_SOURCES = \
  fakebank.c fakebank.h \
  fakebank_api_check.c \
  fakebank_common_lookup.c fakebank_common_lookup.h \
  fakebank_common_lp.c fakebank_common_lp.h \
  fakebank_common_make_admin_transfer.c fakebank_common_make_admin_transfer.h \
  fakebank_common_parser.c fakebank_common_parser.h \
  fakebank_common_transact.c fakebank_common_transact.h \
  fakebank_stop.c \
  fakebank_bank.c fakebank_bank.h \
  fakebank_bank_accounts_withdrawals.c fakebank_bank_accounts_withdrawals.h \
  fakebank_bank_get_accounts.c fakebank_bank_get_accounts.h \
  fakebank_bank_get_withdrawals.c fakebank_bank_get_withdrawals.h \
  fakebank_bank_get_root.c fakebank_bank_get_root.h \
  fakebank_bank_post_accounts_withdrawals.c fakebank_bank_post_accounts_withdrawals.h \
  fakebank_bank_post_withdrawals_abort.c fakebank_bank_post_withdrawals_abort.h \
  fakebank_bank_post_withdrawals_confirm.c fakebank_bank_post_withdrawals_confirm.h \
  fakebank_bank_post_withdrawals_id_op.c fakebank_bank_post_withdrawals_id_op.h \
  fakebank_bank_testing_register.c fakebank_bank_testing_register.h \
  fakebank_tbr.c fakebank_tbr.h \
  fakebank_tbr_get_history.c fakebank_tbr_get_history.h \
  fakebank_tbr_get_root.c fakebank_tbr_get_root.h \
  fakebank_tbi.c fakebank_tbi.h \
  fakebank_tbi_get_withdrawal_operation.c fakebank_tbi_get_withdrawal_operation.h \
  fakebank_tbi_post_withdrawal_operation.c fakebank_tbi_post_withdrawal_operation.h \
  fakebank_twg.c fakebank_twg.h \
  fakebank_twg_admin_add_incoming.c fakebank_twg_admin_add_incoming.h \
  fakebank_twg_get_root.c fakebank_twg_get_root.h \
  fakebank_twg_history.c fakebank_twg_history.h \
  fakebank_twg_transfer.c fakebank_twg_transfer.h
libtalerfakebank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lcurl \
  -lmicrohttpd \
  -lpthread \
  $(XLIB)

check_SCRIPTS = \
  test_bank.sh

TESTS = \
  $(check_SCRIPTS)

EXTRA_DIST = \
  $(check_SCRIPTS) \
  test_bank.conf
