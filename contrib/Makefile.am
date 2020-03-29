SUBDIRS = .

# English (en)
tosendir=$(pkgdatadir)/tos/en

# English (en)
ppendir=$(pkgdatadir)/pp/en

rdatadir=$(pkgdatadir)

tosen_DATA = \
  tos/en/0.txt \
  tos/en/0.pdf \
  tos/en/0.epub \
  tos/en/0.xml \
  tos/en/0.html

ppen_DATA = \
  pp/en/0.txt \
  pp/en/0.pdf \
  pp/en/0.epub \
  pp/en/0.xml \
  pp/en/0.html

rdata_DATA = \
  auditor-report.tex.j2

bin_SCRIPTS = \
  taler-bank-manage-testing \
  taler-exchange-revoke

EXTRA_DIST = \
  $(bin_SCRIPTS) \
  $(tosen_DATA) \
  $(ppen_DATA) \
  update-tos.sh \
  update-pp.sh \
  tos/Makefile \
  tos/README \
  tos/tos.rst \
  tos/conf.py \
  tos/locale/de/LC_MESSAGES/tos.po \
  pp/Makefile \
  pp/README \
  pp/pp.rst \
  pp/conf.py \
  pp/locale/de/LC_MESSAGES/pp.po \
  $(rdata_DATA) \
  coverage.sh \
  gnunet.tag \
  microhttpd.tag

# Change the set of supported languages here. You should
# also update tos'XX'data and EXTRA_DIST accordingly.
TOS_LANGUAGES="en de"
PP_LANGUAGES="en de"

# Change the terms-of-service version (Etag) to generate here!
# This value should be incremented whenever there is a substantive
# change in the original text (but not for the translations).
TOS_VERSION=0
PP_VERSION=0

update-tos:
	VERSION=$(TOS_VERSION) ./update-tos.sh $(TOS_LANGUAGES)
update-pp:
	VERSION=$(PP_VERSION) ./update-pp.sh $(PP_LANGUAGES)
