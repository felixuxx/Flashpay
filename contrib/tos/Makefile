# Makefile for Sphinx documentation
#
# You can set these variables from the command line.
SPHINXOPTS    =
SPHINXBUILD   = sphinx-build
PAPER         =
BUILDDIR      = _build

# User-friendly check for sphinx-build
ifeq ($(shell which $(SPHINXBUILD) >/dev/null 2>&1; echo $$?), 1)
$(error The '$(SPHINXBUILD)' command was not found. Make sure you have Sphinx installed, then set the SPHINXBUILD environment variable to point to the full path of the '$(SPHINXBUILD)' executable. Alternatively you can add the directory with the executable to your PATH. If you don't have Sphinx installed, grab it from http://sphinx-doc.org/)
endif

# Internal variables.
PAPEROPT_a4     = -D latex_paper_size=a4
PAPEROPT_letter = -D latex_paper_size=letter
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) .
# the i18n builder cannot share the environment and doctrees with the others
I18NSPHINXOPTS  = $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) .

.PHONY: help clean html json epub latex latexpdf text man doctest gettext

help:
	@echo "Please use \`make <target>' where <target> is one of"
	@echo "  html       to make a single large HTML file"
	@echo "  json       to make JSON files"
	@echo "  epub       to make an epub"
	@echo "  latex      to make LaTeX files, you can set PAPER=a4 or PAPER=letter"
	@echo "  pdf        to make LaTeX files and run them through pdflatex"
	@echo "  txt        to make text files"
	@echo "  man        to make manual pages"
	@echo "  texinfo    to make Texinfo files"
	@echo "  info       to make Texinfo files and run them through makeinfo"
	@echo "  gettext    to make PO message catalogs"
	@echo "  xml        to make Docutils-native XML files"
	@echo "  pseudoxml  to make pseudoxml-XML files for display purposes"
	@echo "  doctest    to run all doctests embedded in the documentation (if enabled)"

clean:
	rm -rf $(BUILDDIR)/*


# The html-linked builder does not support caching, so we
# remove all cached state first.
html:
	$(SPHINXBUILD) -b html $(ALLSPHINXOPTS) $(BUILDDIR)/html
	@echo
	@echo "Build finished. The HTML page is in $(BUILDDIR)/html."

json:
	$(SPHINXBUILD) -b json $(ALLSPHINXOPTS) $(BUILDDIR)/json
	@echo
	@echo "Build finished; now you can process the JSON files."

epub:
	$(SPHINXBUILD) -b epub $(ALLSPHINXOPTS) $(BUILDDIR)/epub
	@echo
	@echo "Build finished. The epub file is in $(BUILDDIR)/epub."

latex:
	$(SPHINXBUILD) -b latex $(ALLSPHINXOPTS) $(BUILDDIR)/latex
	@echo
	@echo "Build finished; the LaTeX files are in $(BUILDDIR)/latex."
	@echo "Run \`make' in that directory to run these through (pdf)latex" \
	      "(use \`make latexpdf' here to do that automatically)."

pdf:
	$(SPHINXBUILD) -b latex $(ALLSPHINXOPTS) $(BUILDDIR)/pdf
	@echo "Running LaTeX files through pdflatex..."
	$(MAKE) -C $(BUILDDIR)/pdf all-pdf
	@echo "pdflatex finished; the PDF files are in $(BUILDDIR)/pdf."

txt:
	$(SPHINXBUILD) -b text $(ALLSPHINXOPTS) $(BUILDDIR)/txt
	@echo
	@echo "Build finished. The text files are in $(BUILDDIR)/txt."

man:
	$(SPHINXBUILD) -b man $(ALLSPHINXOPTS) $(BUILDDIR)/man
	@echo
	@echo "Build finished. The manual pages are in $(BUILDDIR)/man."

texinfo:
	$(SPHINXBUILD) -b texinfo $(ALLSPHINXOPTS) $(BUILDDIR)/texinfo
	@echo
	@echo "Build finished. The Texinfo files are in $(BUILDDIR)/texinfo."
	@echo "Run \`make' in that directory to run these through makeinfo" \
	      "(use \`make info' here to do that automatically)."

info:
	$(SPHINXBUILD) -b texinfo $(ALLSPHINXOPTS) $(BUILDDIR)/info
	@echo "Running Texinfo files through makeinfo..."
	make -C $(BUILDDIR)/texinfo info
	@echo "makeinfo finished; the Info files are in $(BUILDDIR)/info."

gettext:
	$(SPHINXBUILD) -b gettext $(I18NSPHINXOPTS) $(BUILDDIR)/locale
	@echo
	@echo "Build finished. The message catalogs are in $(BUILDDIR)/locale."

doctest:
	$(SPHINXBUILD) -b doctest $(ALLSPHINXOPTS) $(BUILDDIR)/doctest
	@echo "Testing of doctests in the sources finished, look at the " \
	      "results in $(BUILDDIR)/doctest/output.txt."

xml:
	$(SPHINXBUILD) -b xml $(ALLSPHINXOPTS) $(BUILDDIR)/xml
	@echo
	@echo "Build finished. The XML files are in $(BUILDDIR)/xml."
