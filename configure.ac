#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
#
#  This file is part of TALER
#  Copyright (C) 2014-2024 Taler Systems SA
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
AC_INIT([taler-exchange],[0.14.1],[taler-bug@gnunet.org])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_SRCDIR([src/util/util.c])
AC_CONFIG_HEADERS([taler_config.h])
AC_CANONICAL_TARGET
AC_CANONICAL_HOST
AC_CANONICAL_BUILD
# support for non-recursive builds
AM_INIT_AUTOMAKE([subdir-objects 1.9 tar-pax])

# pretty build rules
AM_SILENT_RULES([yes])

AC_CONFIG_MACRO_DIR([m4])
AC_PROG_AWK
AC_PROG_CC
AC_PROG_OBJC
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_MAKE_SET
AM_PROG_CC_C_O

LT_INIT([disable-static dlopen])

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
AM_CONDITIONAL([DOC_ONLY], [test "x$doc_only" = "xyes"])


# Not indented, as most of the file falls under this one...
AS_IF([test "x$doc_only" != xyes],[

# Force some CFLAGS
CFLAGS="-Wall -Wno-address-of-packed-member $CFLAGS"

TALER_LIB_LDFLAGS="-export-dynamic -no-undefined"
TALER_PLUGIN_LDFLAGS="-export-dynamic -avoid-version -module -no-undefined"

AC_SUBST(TALER_LIB_LDFLAGS)
AC_SUBST(TALER_PLUGIN_LDFLAGS)


# Checks for header files.
AC_CHECK_HEADERS([stdint.h stdlib.h string.h unistd.h sys/socket.h sys/un.h netinet/in.h netinet/ip.h])

AX_PYTHON_MODULE([jinja2],true)


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


AC_MSG_CHECKING(whether to enable epoll)
AC_ARG_ENABLE([[epoll]],
  [AS_HELP_STRING([[--enable-epoll[=ARG]]], [enable epoll support (yes, no, auto) [auto]])],
    [enable_epoll=${enableval}],
    [enable_epoll='auto']
  )
AC_MSG_RESULT($enable_epoll)
AM_CONDITIONAL([MHD_HAVE_EPOLL], [test "x$enable_epoll" = "xyes"])

AS_IF([test "$enable_epoll" != "no"],
      [AX_HAVE_EPOLL
       AS_IF([test "${ax_cv_have_epoll}" = "yes"],
          [AC_DEFINE([[EPOLL_SUPPORT]],[[1]],[Define to 1 to enable epoll support])
           enable_epoll='yes'],
       [AS_IF([test "$enable_epoll" = "yes"],
              AC_MSG_ERROR([[Support for epoll was explicitly requested but cannot be enabled on this platform.]]))
        enable_epoll='no'])])


AS_IF([test "x$enable_epoll" = "xyes"],
  AC_CACHE_CHECK([for epoll_create1()],
                 [mhd_cv_have_epoll_create1], [
    AC_LINK_IFELSE([
      AC_LANG_PROGRAM([[
#include <sys/epoll.h>
        ]], [[
int fd;
fd = epoll_create1(EPOLL_CLOEXEC);]])],
      [mhd_cv_have_epoll_create1=yes],
      [mhd_cv_have_epoll_create1=no])])
  AS_IF([test "x$mhd_cv_have_epoll_create1" = "xyes"],[
    AC_DEFINE([[HAVE_EPOLL_CREATE1]], [[1]], [Define if you have epoll_create1 function.])]))


# check for libmicrohttpd
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
MHD_VERSION_AT_LEAST([0.9.71])

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
AC_CHECK_LIB(jansson,json_dumpb,
  [AC_CHECK_HEADER([jansson.h],[jansson=1])])
AS_IF([test $jansson = 0],
  [AC_MSG_ERROR([[
***
*** You need libjansson >= 2.10 to build this program.
*** ]])])


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
AC_CHECK_HEADERS([gnunet/gnunet_util_lib.h],
 [AC_CHECK_LIB([gnunetutil], [GNUNET_SCHEDULER_run], libgnunetutil=1)])
AS_IF([test $libgnunetutil != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetutil >= 0.21.1 to build this program.
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
AC_CHECK_HEADERS([gnunet/gnunet_json_lib.h],
 [AC_CHECK_LIB([gnunetjson], [GNUNET_JSON_parse], libgnunetjson=1)])
AS_IF([test $libgnunetjson != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetjson to build this program.
*** Make sure you have libjansson installed while
*** building GNUnet.
*** ]])])

# check for gettext
AM_GNU_GETTEXT([external])
AM_GNU_GETTEXT_VERSION([0.19.8])


# Save before checking libcurl
CFLAGS_SAVE=$CFLAGS
LDFLAGS_SAVE=$LDFLAGS
LIBS_SAVE=$LIBS

# check for libcurl
LIBCURL_CHECK_CONFIG(,7.34.0,[curl=1],[curl=0])

# cURL must support CURLINFO_TLS_SESSION, version >= 7.34
AS_IF([test "x$curl" = x1],[
 AC_CHECK_HEADER([curl/curl.h],
  [AC_CHECK_DECLS(CURLINFO_TLS_SESSION,[curl=1],[curl=0],[[#include <curl/curl.h>]])],
  [curl=0])
])

# libcurl should be mutually exclusive
AS_IF([test "$curl" = 1],
      AM_CONDITIONAL(HAVE_LIBCURL, true)
      AC_DEFINE([HAVE_LIBCURL],[1],[Have libcurl])
      [LIBCURL_LIBS="-lcurl"],
      [AC_MSG_ERROR([FATAL: No libcurl])])

AC_SUBST([LIBCURL_LIBS])

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
AC_CHECK_HEADERS([gnunet/gnunet_curl_lib.h],
 [AC_CHECK_LIB([gnunetcurl], [GNUNET_CURL_get_select_info], libgnunetcurl=1)])
AS_IF([test $libgnunetcurl != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetcurl to build this program.
*** Make sure you have libcurl installed while
*** building GNUnet.
*** ]])])


# Restore after curl checks messed up these values
CFLAGS=$CFLAGS_SAVE
LDFLAGS=$LDFLAGS_SAVE
LIBS=$LIBS_SAVE

# test for postgres
AX_LIB_POSTGRESQL([15.0])
AS_IF([test "x$found_postgresql" = "xyes"],
  [SAVE_CPPFLAGS="$CPPFLAGS"
   CPPFLAGS="$POSTGRES_CPPFLAGS $CPPFLAGS"
   AC_CHECK_HEADERS([libpq-fe.h], [postgres=1], [postgres=0])])
AS_IF([test "x$postgres" != "x1"],
  [AC_MSG_ERROR([[
***
*** You need libpq(-dev) >= 15.0 to build this program.
*** ]])])
AM_CONDITIONAL([HAVE_POSTGRESQL], [test "x$postgres" = "x1"])
AC_DEFINE_UNQUOTED([HAVE_POSTGRESQL], [$postgres],
                   [Define to 1 if Postgres is available])

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
         CPPFLAGS="-I$with_gnunet/include ${CPPFLAGS}"])
CPPFLAGS="${CPPFLAGS} ${POSTGRESQL_CPPFLAGS}"
AC_CHECK_HEADERS([gnunet/gnunet_pq_lib.h],
 [AC_CHECK_LIB([gnunetpq], [GNUNET_PQ_query_param_blinded_sig], libgnunetpq=1)])
AS_IF([test $libgnunetpq != 1],
  [AC_MSG_ERROR([[
***
*** You need libgnunetpq version >= 8:0:3 to build this program.
*** Make sure you have Postgres installed while
*** building GNUnet (and that your GNUnet version is recent!)
*** ]])])

CFLAGS_SAVE=$CFLAGS
LDFLAGS_SAVE=$LDFLAGS
LIBS_SAVE="$LIBS"

# Check for GNUnet's libgnunetsq
libgnunetsq=0
AC_MSG_CHECKING([for libgnunetsq])
AC_CHECK_HEADERS([gnunet/gnunet_sq_lib.h],
 [AC_CHECK_LIB([gnunetsq], [GNUNET_SQ_result_spec_string], libgnunetsq=1)])



CFLAGS=$CFLAGS_SAVE
LDFLAGS=$LDFLAGS_SAVE
LIBS=$LIBS_SAVE

# test for sqlite
sqlite=false
AC_MSG_CHECKING(for SQLite)
AC_ARG_WITH(sqlite,
  [  --with-sqlite=PFX       base of SQLite installation],
  [AC_MSG_RESULT("$with_sqlite")
   AS_CASE([$with_sqlite],
     [no],[],
     [yes],[
      AC_CHECK_HEADERS(sqlite3.h,
      sqlite=true)],
     [
    LDFLAGS="-L$with_sqlite/lib $LDFLAGS"
    CPPFLAGS="-I$with_sqlite/include $CPPFLAGS"
    AC_CHECK_HEADERS(sqlite3.h,
     EXT_LIB_PATH="-L$with_sqlite/lib $EXT_LIB_PATH"
     SQLITE_LDFLAGS="-L$with_sqlite/lib"
     SQLITE_CPPFLAGS="-I$with_sqlite/include"
     sqlite=true)
    LDFLAGS=$SAVE_LDFLAGS
    CPPFLAGS=$SAVE_CPPFLAGS
    ])
  ],
  [AC_MSG_RESULT([--with-sqlite not specified])
    AC_CHECK_HEADERS(sqlite3.h, sqlite=true)])
AM_CONDITIONAL(HAVE_SQLITE, [test x$sqlite = xtrue] && [test $libgnunetsq = 1])
AC_SUBST(SQLITE_CPPFLAGS)
AC_SUBST(SQLITE_LDFLAGS)

# check for libtalertwistertesting
talertwister=0
AC_MSG_CHECKING([for talertwister])
AC_ARG_WITH([twister],
            [AS_HELP_STRING([--with-twister=PFX], [base of libtalertwister])],
            [AC_MSG_RESULT([given as $with_twister])],
            [AC_MSG_RESULT([not given])
             with_twister=yes])
AS_CASE([$with_twister],
        [yes], [],
        [no], [AC_MSG_WARN([no twister-testing will be compiled])],
        [LDFLAGS="-L$with_twister/lib $LDFLAGS"
         CPPFLAGS="-I$with_twister/include $CPPFLAGS"])

AC_CHECK_HEADERS([taler/taler_twister_service.h],
 [AC_CHECK_LIB([talertwister], [TALER_TWISTER_connect], talertwister=1)])
AM_CONDITIONAL(HAVE_TWISTER, test x$talertwister = x1)

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

AC_PATH_PROG([JQ], [jq], [no])
if test "$JQ" = "no"; then
  AC_MSG_ERROR([jq is required but not found. Please install jq.])
fi



# Adam shostack suggests the following for Windows:
# -D_FORTIFY_SOURCE=2 -fstack-protector-all
AC_ARG_ENABLE(gcc-hardening,
   AS_HELP_STRING(--enable-gcc-hardening, enable compiler security checks),
[AS_IF([test x$enableval = xyes],[
    CFLAGS="$CFLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -fstack-protector-all"
    CFLAGS="$CFLAGS -fwrapv -fPIE -Wstack-protector"
    CFLAGS="$CFLAGS --param ssp-buffer-size=1"
    LDFLAGS="$LDFLAGS -pie"])])


# Linker hardening options
# Currently these options are ELF specific - you can't use this with MacOSX
AC_ARG_ENABLE(linker-hardening,
  AS_HELP_STRING(--enable-linker-hardening, enable linker security fixups),
  [AS_IF([test x$enableval = xyes],[LDFLAGS="$LDFLAGS -z relro -z now"])])


AC_ARG_ENABLE(sanitizer,
  AS_HELP_STRING(--enable-sanitizer, enable Address Sanitizer and Undefined Behavior Sanitizer),
[AS_IF([test x$enableval = xyes],[
   LDFLAGS="$CFLAGS -fsanitize=address,undefined -fno-omit-frame-pointer"
 ])])

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
  git_version=$(cd $srcdir ; git rev-list -n 1 --abbrev-commit HEAD 2>/dev/null)
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


],[  # This is the big test "$doc_only" on top of the file!


# logic if doc_only is set, make sure conditionals are still defined
AM_CONDITIONAL([HAVE_EXPENSIVE_TESTS], [false])
AM_CONDITIONAL([MHD_HAVE_EPOLL], [false])
AM_CONDITIONAL([HAVE_POSTGRESQL], [false])
AM_CONDITIONAL([HAVE_SQLITE], [false])
AM_CONDITIONAL([HAVE_LIBCURL], [false])
AM_CONDITIONAL([HAVE_DEVELOPER], [false])
AM_CONDITIONAL([USE_COVERAGE], [false])
AM_CONDITIONAL([ENABLE_DOC], [true])
AM_CONDITIONAL([HAVE_TWISTER], [false])

# end of 'doc_only'
])

AC_CONFIG_FILES([Makefile
                 contrib/Makefile
                 doc/Makefile
                 doc/doxygen/Makefile
                 po/Makefile.in
                 src/Makefile
                 src/auditor/Makefile
                 src/auditordb/Makefile
                 src/bank-lib/Makefile
                 src/curl/Makefile
                 src/exchange/Makefile
                 src/exchangedb/Makefile
                 src/exchange-tools/Makefile
                 src/extensions/Makefile
                 src/extensions/age_restriction/Makefile
                 src/lib/Makefile
                 src/kyclogic/Makefile
                 src/testing/Makefile
                 src/benchmark/Makefile
                 src/include/Makefile
                 src/json/Makefile
                 src/mhd/Makefile
                 src/pq/Makefile
                 src/sq/Makefile
                 src/templating/Makefile
                 src/util/Makefile
                 ])
AC_OUTPUT
