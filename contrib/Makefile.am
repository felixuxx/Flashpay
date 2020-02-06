SUBDIRS = . pp

# English (en)
tosendir=$(pkgdatadir)/tos/en

# English (en)
ppendir=$(pkgdatadir)/pp/en

tosen_DATA = \
  tos/en/0.txt \
  tos/en/0.pdf \
  tos/en/0.epub \
  tos/en/0.xml \
  tos/en/0.html

bin_SCRIPTS = \
  taler-bank-manage-testing \
  taler-exchange-revoke

EXTRA_DIST = \
  $(bin_SCRIPTS) \
  $(tosen_DATA) \
  update-tos.sh \
  tos/Makefile \
  tos/README \
  tos/tos.rst \
  tos/conf.py \
  tos/locale/de/LC_MESSAGES/tos.po \
  auditor-report.tex.j2 \
  coverage.sh \
  gnunet.tag \
  microhttpd.tag \
  render.py

# Change the set of supported languages here. You should
# also update tos'XX'data and EXTRA_DIST accordingly.
TOS_LANGUAGES="en de"

# Change the terms-of-service version (Etag) to generate here!
# This value should be incremented whenever there is a substantive
# change in the original text (but not for the translations).
TOS_VERSION=0

update-tos:
	VERSION=$(TOS_VERSION) ./update-tos.sh $(TOS_LANGUAGES)
