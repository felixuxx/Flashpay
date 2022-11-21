SUBDIRS = .

tmplpkgdatadir = $(prefix)/share/taler/exchange/templates/

dist_tmplpkgdata_DATA = \
  persona-exchange-unauthorized.en.must \
  persona-load-failure.en.must \
  persona-exchange-unpaid.en.must \
  persona-logic-failure.en.must \
  persona-invalid-response.en.must \
  persona-network-timeout.en.must \
  persona-kyc-failed.en.must \
  persona-provider-failure.en.must

# %%.must: merchant-backoffice/%.html
# WTF: cp $< $@


# English (en)
tosendir=$(datadir)/taler/exchange/tos/en

# English (en)
ppendir=$(datadir)/taler/exchange/pp/en

rdatadir=$(datadir)/taler/exchange

tosen_DATA = \
  tos/en/*.txt \
  tos/en/*.pdf \
  tos/en/*.epub \
  tos/en/*.xml \
  tos/en/*.html

ppen_DATA = \
  pp/en/*.txt \
  pp/en/*.pdf \
  pp/en/*.epub \
  pp/en/*.xml \
  pp/en/*.html

rdata_DATA = \
  auditor-report.tex.j2

bin_SCRIPTS = \
  taler-bank-manage-testing \
  taler-nexus-prepare

EXTRA_DIST = \
  $(bin_SCRIPTS) \
  $(tosen_DATA) \
  $(ppen_DATA) \
  update-tos.sh \
  update-pp.sh \
  gana-update.sh \
  gana/gnu-taler-error-codes/registry.rec \
  gana/gnu-taler-error-codes/Makefile \
  tos/Makefile \
  tos/README \
  tos/bfh-v0.rst \
  tos/tos-v0.rst \
  tos/conf.py.in \
  tos/locale/de/LC_MESSAGES/tos.po \
  pp/Makefile \
  pp/README \
  pp/pp-v0.rst \
  pp/conf.py.in \
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
# This value should be modified whenever there is a substantive
# change in the original text (but not for the translations).
TOS_VERSION=tos-v0
PP_VERSION=pp-v0

update-tos:
	VERSION=$(TOS_VERSION) ./update-tos.sh $(TOS_LANGUAGES)
update-pp:
	VERSION=$(PP_VERSION) ./update-pp.sh $(PP_LANGUAGES)
