# mhd.m4

#  This file is part of TALER
#  Copyright (C) 2022 Taler Systems SA
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

# serial 1

dnl MHD_VERSION_AT_LEAST([VERSION])
dnl
dnl Check that microhttpd.h can be used to build a program that prints out
dnl the MHD_VERSION tuple in X.Y.Z format, and that X.Y.Z is greater or equal
dnl to VERSION.  If not, display message and cause the configure script to
dnl exit failurefully.
dnl
dnl This uses AX_COMPARE_VERSION to do the job.
dnl It sets shell var mhd_cv_version, as well.
dnl
AC_DEFUN([MHD_VERSION_AT_LEAST],
[AC_CACHE_CHECK([libmicrohttpd version],[mhd_cv_version],
 [AC_LINK_IFELSE([AC_LANG_PROGRAM([[
  #include <stdio.h>
  #include <microhttpd.h>
]],[[
  int v = MHD_VERSION;
  printf ("%x.%x.%x\n",
          (v >> 24) & 0xff,
          (v >> 16) & 0xff,
          (v >>  8) & 0xff);
]])],
  [mhd_cv_version=$(./conftest)],
  [mhd_cv_version=0])])
AX_COMPARE_VERSION([$mhd_cv_version],[ge],[$1],,
  [AC_MSG_ERROR([[
***
*** You need libmicrohttpd >= $1 to build this program.
*** ]])])])

# mhd.m4 ends here
