#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
#
#  This file is part of TALER
#  Copyright (C) 2014, 2015, 2016, 2017 GNUnet e.V. and Inria
#
#  TALER is free software; you can redistribute it and/or modify it under the
#  terms of the GNU General Public License as published by the Free Software
#  Foundation; either version 3, or (at your option) any later version.
#
#  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
#  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
#  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License along with
#  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/license>
#
#
AC_PREREQ([2.69])
AC_INIT([taler-exchange], [0.5.0], [taler-bug@gnunet.org])
AC_CONFIG_SRCDIR([src/util/util.c])
AC_CONFIG_HEADERS([taler_config.h])
# support for non-recursive builds
AM_INIT_AUTOMAKE([subdir-objects 1.9 tar-pax])

# pretty build rules
AM_SILENT_RULES([yes])

AC_CONFIG_MACRO_DIR([m4])

LT_INIT

DX_INIT_DOXYGEN([taler-exchange],,,
DX_PS_FEATURE(OFF),
DX_PDF_FEATURE(OFF),
DX_RTF_FEATURE(OFF),
DX_CHI_FEATURE(OFF),
DX_XML_FEATURE(OFF))

AC_MSG_CHECKING([whether to compile documentation ONLY])
AC_ARG_ENABLE([only-doc],
  [AS_HELP_STRING([--enable-only-doc], [only compile Taler documentation])],
  [doc_only=${enableval}],
  [doc_only=no])
AC_MSG_RESULT($doc_only)
AM_CONDITIONAL([DOC_ONLY], [test "$doc_only" = "yes"])

if test "$doc_only" != yes
then

# Checks for programs.

AC_PROG_CC
AC_PROG_CC_C99


CFLAGS="-Wall $CFLAGS"

# Checks for header files.
AC_CHECK_HEADERS([stdint.h stdlib.h string.h unistd.h])


# should the build process be restricted to the code required
# for GNU Taler wallets?
AC_MSG_CHECKING([whether to compile GNU Taler Wallet library ONLY])
AC_ARG_ENABLE([wallet],
   [AS_HELP_STRING([--enable-wallet], [only compile for Taler wallet])],
   [wallet_only=${enableval}],
   [wallet_only=no])
AC_MSG_RESULT($wallet_only)
AM_CONDITIONAL([WALLET_ONLY], [test "x$wallet_only" = "xyes"])


# Require minimum libgcrypt version
need_libgcrypt_version=1.6.1
AC_DEFINE_UNQUOTED([NEED_LIBGCRYPT_VERSION], ["$need_libgcrypt_version"],
                                             [minimum version of libgcrypt required])
AM_PATH_LIBGCRYPT([$need_libgcrypt_version])


# should expensive tests be run?
AC_MSG_CHECKING(whether to run expensive tests)
AC_ARG_ENABLE([expensivetests],
   [AS_HELP_STRING([--enable-expensivetests], [enable running expensive testcases])],
   [enable_expensive=${enableval}],
   [enable_expensive=no])
AC_MSG_RESULT($enable_expensive)
AM_CONDITIONAL([HAVE_EXPENSIVE_TESTS], [test "x$enable_expensive" = "xyes"])


if test "$wallet_only" != yes
then


# Check for GNUnet's libgnunetutil.
libgnunetutil=0
AC_MSG_CHECKING([for libgnunetutil])
AC_ARG_WITH(gnunet,
            [AS_HELP_STRING([--with-gnunet=PFX], [base of GNUnet installation])],
            [AC_MSG_RESULT([given as $with_gnunet])],
            [AC_MSG_RESULT(not given)
             with_gnunet=yes])
AS_CASE([$with_gnunet],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-gnunet is required])],
        [LDFLAGS="-L$with_gnunet/lib $LDFLAGS"
         CPPFLAGS="-I$with_gnunet/include $CPPFLAGS"])
AC_CHECK_HEADERS([gnunet/platform.h gnunet/gnunet_util_lib.h],
 [AC_CHECK_LIB([gnunetutil], [GNUNET_SCHEDULER_run], libgnunetutil=1)],
  [], [#ifdef HAVE_GNUNET_PLATFORM_H
        #include <gnunet/platform.h>
       #endif])
AS_IF([test $libgnunetutil != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetutil to build this program.
*** This library is part of GNUnet, available at
***   https://gnunet.org
*** ]])])


# Check for GNUnet's libgnunetjson.
libgnunetjson=0
AC_MSG_CHECKING([for libgnunetjson])
AC_ARG_WITH(gnunet,
            [AS_HELP_STRING([--with-gnunet=PFX], [base of GNUnet installation])],
            [AC_MSG_RESULT([given as $with_gnunet])],
            [AC_MSG_RESULT(not given)
             with_gnunet=yes])
AS_CASE([$with_gnunet],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-gnunet is required])],
        [LDFLAGS="-L$with_gnunet/lib $LDFLAGS"
         CPPFLAGS="-I$with_gnunet/include $CPPFLAGS"])
AC_CHECK_HEADERS([gnunet/platform.h gnunet/gnunet_json_lib.h],
 [AC_CHECK_LIB([gnunetjson], [GNUNET_JSON_parse], libgnunetjson=1)],
  [], [#ifdef HAVE_GNUNET_PLATFORM_H
        #include <gnunet/platform.h>
       #endif])
AS_IF([test $libgnunetjson != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetjson to build this program.
*** Make sure you have libjansson installed while
*** building GNUnet.
*** ]])])


# libcurl-gnutls
LIBCURL_CHECK_CONFIG(,7.34.0,[curl=true],[curl=false])
if test "x$curl" = xtrue
then
 LDFLAGS="-L$with_libcurl/lib $LDFLAGS"
 CPPFLAGS="-I$with_libcurl/include $CPPFLAGS"
 AC_CHECK_HEADERS([curl/curl.h],
   AC_CHECK_DECLS(CURLINFO_TLS_SESSION,[curl=true],[curl=false],[[#include <curl/curl.h>]]),
   [curl=false])
 # need libcurl-gnutls.so, everything else is not acceptable
 AC_CHECK_LIB([curl-gnutls],[curl_easy_getinfo],,[curl=false])
 # cURL must support CURLINFO_TLS_SESSION, version >= 7.34

fi
if test x$curl = xfalse
then
	AM_CONDITIONAL(HAVE_LIBCURL, false)
if test "$gnurl" = 0
then
	AC_MSG_WARN([GNUnet requires libcurl-gnutls  >= 7.34])
fi
else
	AM_CONDITIONAL(HAVE_LIBCURL, true)
	AC_DEFINE([HAVE_LIBCURL],[1],[Have CURL])
fi


# Check for curl/curl.h and gnurl/curl.h so we can use #ifdef
# HAVE_CURL_CURL_H later (the above LIBCURL_CHECK_CONFIG accepted
# *either* header set).
AC_CHECK_HEADERS([curl/curl.h],,
  curl=false
  AC_CHECK_HEADERS([gnurl/curl.h],,
  gnurl=false))


# libgnurl
if test "x$gnurl" = "x0"
then
  if test "x$curl" = "x0"
  then
    AC_MSG_NOTICE([NOTICE: libgnurl not found.  http client support will not be compiled.])
    AC_MSG_WARN([ERROR: libgnurl not found.  hostlist daemon will not be compiled, and you probably WANT the hostlist daemon])
  else
    AC_MSG_NOTICE([WARNING: libgnurl not found, trying to use libcurl-gnutls instead.])
  fi
fi



# Check for GNUnet's libgnunetcurl.
libgnunetcurl=0
AC_MSG_CHECKING([for libgnunetcurl])
AC_ARG_WITH(gnunet,
            [AS_HELP_STRING([--with-gnunet=PFX], [base of GNUnet installation])],
            [AC_MSG_RESULT([given as $with_gnunet])],
            [AC_MSG_RESULT(not given)
             with_gnunet=yes])
AS_CASE([$with_gnunet],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-gnunet is required])],
        [LDFLAGS="-L$with_gnunet/lib $LDFLAGS"
         CPPFLAGS="-I$with_gnunet/include $CPPFLAGS"])
AC_CHECK_HEADERS([gnunet/platform.h gnunet/gnunet_curl_lib.h],
 [AC_CHECK_LIB([gnunetcurl], [GNUNET_CURL_get_select_info], libgnunetcurl=1)],
  [], [#ifdef HAVE_GNUNET_PLATFORM_H
        #include <gnunet/platform.h>
       #endif])
AS_IF([test $libgnunetcurl != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetcurl to build this program.
*** Make sure you have libcurl or libgnurl installed while
*** building GNUnet.
*** ]])])



# Check for GNUnet's libgnunetpq.
libgnunetpq=0
AC_MSG_CHECKING([for libgnunetpq])
AC_ARG_WITH(gnunet,
            [AS_HELP_STRING([--with-gnunet=PFX], [base of GNUnet installation])],
            [AC_MSG_RESULT([given as $with_gnunet])],
            [AC_MSG_RESULT(not given)
             with_gnunet=yes])
AS_CASE([$with_gnunet],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-gnunet is required])],
        [LDFLAGS="-L$with_gnunet/lib $LDFLAGS"
         CPPFLAGS="-I$with_gnunet/include $CPPFLAGS"])
AC_CHECK_HEADERS([gnunet/platform.h gnunet/gnunet_pq_lib.h],
 [AC_CHECK_LIB([gnunetpq], [GNUNET_PQ_result_spec_string], libgnunetpq=1)],
  [], [#ifdef HAVE_GNUNET_PLATFORM_H
        #include <gnunet/platform.h>
       #endif])
AS_IF([test $libgnunetpq != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetpq to build this program.
*** Make sure you have Postgres installed while
*** building GNUnet (and that your GNUnet version
*** is recent!)
*** ]])])


# check for libmicrohttpd
microhttpd=0
AC_MSG_CHECKING([for microhttpd])
AC_ARG_WITH([microhttpd],
            [AS_HELP_STRING([--with-microhttpd=PFX], [base of microhttpd installation])],
            [AC_MSG_RESULT([given as $with_microhttpd])],
            [AC_MSG_RESULT([not given])
             with_microhttpd=yes])
AS_CASE([$with_microhttpd],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-microhttpd is required])],
        [LDFLAGS="-L$with_microhttpd/lib $LDFLAGS"
         CPPFLAGS="-I$with_microhttpd/include $CPPFLAGS"])
AC_CHECK_LIB(microhttpd,MHD_start_daemon,
  [AC_CHECK_HEADER([microhttpd.h],[microhttpd=1])])
AC_CHECK_DECL([MHD_DAEMON_INFO_CURRENT_CONNECTIONS],,[microhttpd=0],[[#include <microhttpd.h>]])
AS_IF([test $microhttpd = 0],
  [AC_MSG_ERROR([[
***
*** You need libmicrohttpd >= 0.9.39 to build this program.
*** ]])])

# check for libjansson (Jansson JSON library)
jansson=0
AC_MSG_CHECKING([for jansson])
AC_ARG_WITH([jansson],
            [AS_HELP_STRING([--with-jansson=PFX], [base of jansson installation])],
            [AC_MSG_RESULT([given as $with_jansson])],
            [AC_MSG_RESULT([not given])
             with_jansson=yes])
AS_CASE([$with_jansson],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-jansson is required])],
        [LDFLAGS="-L$with_jansson/lib $LDFLAGS"
         CPPFLAGS="-I$with_jansson/include $CPPFLAGS"])
AC_CHECK_LIB(jansson,json_pack,
  [AC_CHECK_HEADER([jansson.h],[jansson=1])])
AS_IF([test $jansson = 0],
  [AC_MSG_ERROR([[
***
*** You need libjansson to build this program.
*** ]])])


# test for postgres
AX_LIB_POSTGRESQL([9.3])
if test "$found_postgresql" = "yes"; then
  postgres=true
fi

else

# Check for GNUnet's libgnunetutil_taler_wallet.

CFLAGS_SAVE=$CFLAGS
LDFLAGS_SAVE=$LDFLAGS
CFLAGS="$CFLAGS $LIBGCRYPT_CFLAGS"
LDFLAGS="$LDFLAGS $LIBGCRYPT_LDFLAGS"
LIBS_SAVE="$LIBS"
LIBS="-lgcrypt -lgpg-error $LIBS"


libgnunetutil_taler_wallet=0
AC_MSG_CHECKING([for libgnunetutil_taler_wallet])
AC_ARG_WITH(gnunet,
            [AS_HELP_STRING([--with-gnunet=PFX], [base of GNUnet installation])],
            [AC_MSG_RESULT([given as $with_gnunet])],
            [AC_MSG_RESULT(not given)
             with_gnunet=yes])
AS_CASE([$with_gnunet],
        [yes], [],
        [no], [AC_MSG_ERROR([--with-gnunet is required])],
        [LDFLAGS="-L$with_gnunet/lib $LDFLAGS"
         CPPFLAGS="-I$with_gnunet/include $CPPFLAGS"])
AC_CHECK_HEADERS([gnunet/platform.h gnunet/gnunet_util_taler_wallet_lib.h],
 [AC_CHECK_LIB([gnunetutil_taler_wallet], [GNUNET_CRYPTO_hash_context_start], libgnunetutil_taler_wallet=1)],
  [], [#ifdef HAVE_GNUNET_PLATFORM_H
        #include <gnunet/platform.h>
       #endif])
AS_IF([test $libgnunetutil_taler_wallet != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetutil_taler_wallet to build this program.
*** This library is part of GNUnet, available at
***   https://gnunet.org/
*** Run GNUnet's configure with --enable-taler-wallet as well!
*** ]])])

CFLAGS=$CFLAGS_SAVE
LDFLAGS=$LDFLAGS_SAVE
LIBS=$LIBS_SAVE


# end of wallet/no-wallet specific logic
fi

TALER_LIB_LDFLAGS="-export-dynamic -no-undefined"
TALER_PLUGIN_LDFLAGS="-export-dynamic -avoid-version -module -no-undefined"

AC_SUBST(TALER_LIB_LDFLAGS)
AC_SUBST(TALER_PLUGIN_LDFLAGS)

CFLAGS_SAVE=$CFLAGS
LDFLAGS_SAVE=$LDFLAGS
LIBS_SAVE="$LIBS"


AM_CONDITIONAL(HAVE_POSTGRESQL, test x$postgres = xtrue)

# check for libgnurl
# libgnurl
LIBGNURL_CHECK_CONFIG(,7.34.0,gnurl=1,gnurl=0)
if test "$gnurl" = 1
then
        LDFLAGS="-L$with_libgnurl/lib $LDFLAGS"
        CPPFLAGS="-I$with_libgnurl/include $CPPFLAGS"
	AM_CONDITIONAL(HAVE_LIBGNURL, [true])
	AC_DEFINE([HAVE_LIBGNURL],[1],[Have libgnurl])
else
	AM_CONDITIONAL(HAVE_LIBGNURL, [false])
fi

CFLAGS=$CFLAGS_SAVE
LDFLAGS=$LDFLAGS_SAVE
LIBS=$LIBS_SAVE

# check for libtalertwistertesting
twistertesting=0
AC_MSG_CHECKING([for talerwtistertesting])
AC_ARG_WITH([twister],
            [AS_HELP_STRING([--with-twister=PFX], [base of libtalertwistertesting])],
            [AC_MSG_RESULT([given as $with_twister])],
            [AC_MSG_RESULT([not given])
             with_twister=yes])
AS_CASE([$with_twister],
        [yes], [],
        [no], [AC_MSG_WARN([no twister-testing will be compiled])],
        [LDFLAGS="-L$with_twister/lib $LDFLAGS"
         CPPFLAGS="-I$with_twister/include $CPPFLAGS"])
AC_CHECK_LIB(talertwistertesting,TALER_TESTING_run_twister,
  [AC_CHECK_HEADER([taler/taler_twister_testing_lib.h],[twistertesting=1],,
                   [#ifdef HAVE_GNUNET_PLATFORM_H
                      #include <gnunet/platform.h>
                    #endif
                    ])]
  ,,[-ltalerexchange -ltalerbank])

AM_CONDITIONAL(HAVE_TWISTER, test x$twistertesting = x1)

# should developer logic be compiled (not-for-production code)?
AC_MSG_CHECKING(whether to compile developer logic)
AC_ARG_ENABLE([developer-mode],
   [AS_HELP_STRING([--enable-developer-mode], [enable compiling developer code])],
   [enable_developer=${enableval}],
   [enable_developer=yes])
AC_MSG_RESULT($enable_developer)
AM_CONDITIONAL([HAVE_DEVELOPER], [test "x$enable_developer" = "xyes"])
enable_dev=1
AS_IF([test "x$enableval" = "xno"], [enable_dev=0])
# developer-logic requires a more recent MHD than usual.
AC_CHECK_DECL([MHD_OPTION_NOTIFY_CONNECTION],,[enable_dev=0],[[#include <microhttpd.h>]])
AC_DEFINE_UNQUOTED([HAVE_DEVELOPER],[$enable_dev],[1 if developer logic is enabled, 0 otherwise])



# Adam shostack suggests the following for Windows:
# -D_FORTIFY_SOURCE=2 -fstack-protector-all
AC_ARG_ENABLE(gcc-hardening,
   AS_HELP_STRING(--enable-gcc-hardening, enable compiler security checks),
[if test x$enableval = xyes; then
    CFLAGS="$CFLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -fstack-protector-all"
    CFLAGS="$CFLAGS -fwrapv -fPIE -Wstack-protector"
    CFLAGS="$CFLAGS --param ssp-buffer-size=1"
    LDFLAGS="$LDFLAGS -pie"
fi])


# Linker hardening options
# Currently these options are ELF specific - you can't use this with MacOSX
AC_ARG_ENABLE(linker-hardening,
  AS_HELP_STRING(--enable-linker-hardening, enable linker security fixups),
[if test x$enableval = xyes; then
   LDFLAGS="$LDFLAGS -z relro -z now"
fi])


# logging
extra_logging=0
AC_ARG_ENABLE([logging],
   AS_HELP_STRING([--enable-logging@<:@=value@:>@],[Enable logging calls. Possible values: yes,no,verbose ('yes' is the default)]),
   [AS_IF([test "x$enableval" = "xyes"], [],
          [test "x$enableval" = "xno"], [AC_DEFINE([GNUNET_CULL_LOGGING],[],[Define to cull all logging calls])],
          [test "x$enableval" = "xverbose"], [extra_logging=1]
          [test "x$enableval" = "xveryverbose"], [extra_logging=2])
   ], [])
AC_DEFINE_UNQUOTED([GNUNET_EXTRA_LOGGING],[$extra_logging],[1 if extra logging is enabled, 2 for very verbose extra logging, 0 otherwise])

# gcov compilation
AC_MSG_CHECKING(whether to compile with support for code coverage analysis)
AC_ARG_ENABLE([coverage],
              AS_HELP_STRING([--enable-coverage],
                             [compile the library with code coverage support]),
              [use_gcov=${enableval}],
              [use_gcov=no])
AC_MSG_RESULT($use_gcov)
AM_CONDITIONAL([USE_COVERAGE], [test "x$use_gcov" = "xyes"])

# version info
AC_PATH_PROG(gitcommand, git)
AC_MSG_CHECKING(for source being under a VCS)
git_version=
AS_IF([test ! "X$gitcommand" = "X"],
[
  git_version=$(cd $srcdir ; git rev-list --full-history --all --abbrev-commit | head -n 1 2>/dev/null)
])
AS_IF([test "X$git_version" = "X"],
  [
    vcs_name="no"
    vcs_version="\"release\""
  ],
  [
    vcs_name="yes, git-svn"
    vcs_version="\"git-$git_version\""
  ])
AC_MSG_RESULT($vcs_name)

AC_MSG_CHECKING(VCS version)
AC_MSG_RESULT($vcs_version)
AC_DEFINE_UNQUOTED(VCS_VERSION, [$vcs_version], [VCS revision/hash or tarball version])


# Checks for typedefs, structures, and compiler characteristics.
AC_TYPE_PID_T
AC_TYPE_SIZE_T
AC_TYPE_UINT16_T
AC_TYPE_UINT32_T
AC_TYPE_UINT64_T
AC_TYPE_INTMAX_T
AC_TYPE_UINTMAX_T

# Checks for library functions.
AC_CHECK_FUNCS([strdup])


AC_ARG_ENABLE([[doc]],
  [AS_HELP_STRING([[--disable-doc]], [do not build any documentation])], ,
    [enable_doc=yes])
test "x$enable_doc" = "xno" || enable_doc=yes
AM_CONDITIONAL([ENABLE_DOC], [test "x$enable_doc" = "xyes"])


else

# logic if doc_only is set, make sure conditionals are still defined
AM_CONDITIONAL([HAVE_EXPENSIVE_TESTS], [false])
AM_CONDITIONAL([WALLET_ONLY], [false])
AM_CONDITIONAL([HAVE_POSTGRESQL], [false])
AM_CONDITIONAL([HAVE_LIBCURL], [false])
AM_CONDITIONAL([HAVE_LIBGNURL], [false])
AM_CONDITIONAL([HAVE_DEVELOPER], [false])
AM_CONDITIONAL([USE_COVERAGE], [false])
AM_CONDITIONAL([ENABLE_DOC], [true])
AM_CONDITIONAL([HAVE_TWISTER], [false])

# end of 'doc_only'
fi

AC_CONFIG_FILES([Makefile
                 doc/Makefile
                 src/Makefile
                 src/auditor/Makefile
                 src/auditordb/Makefile
                 src/bank-lib/Makefile
                 src/exchange/Makefile
                 src/exchangedb/Makefile
                 src/exchange-tools/Makefile
                 src/exchange-lib/Makefile
                 src/benchmark/Makefile
                 src/include/Makefile
                 src/json/Makefile
                 src/pq/Makefile
                 src/util/Makefile
                 src/util/taler-config
                 src/wire/Makefile
                 src/wire-plugins/Makefile
                 ])
AC_OUTPUT
