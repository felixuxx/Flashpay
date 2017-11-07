#!/usr/bin/python
# This file is in the public domain.

"""Expand Jinja2 templates based on JSON input.

First command-line argument must be the JSON input from taler-auditor.
Second command-line argument must be the JSON input from the
taler-wire-auditor.

The tool then reads the template from stdin and writes the expanded
output to stdout.

TODO: proper installation, man page, error handling, --help option.

@author Christian Grothoff

"""

import sys
import json
import jinja2
from jinja2 import BaseLoader


class StdinLoader(BaseLoader):
     def __init__ (self):
         self.path = '-'
     def get_source(self, environment, template):
              source = sys.stdin.read().decode('utf-8')
              return source, self.path, lambda: false


jsonFile1 = open (sys.argv[1], 'r')
jsonData1 = json.load(jsonFile)

jsonFile2 = open (sys.argv[2], 'r')
jsonData2 = json.load(jsonFile)

jinjaEnv = jinja2.Environment(loader=StdinLoader(),
                              lstrip_blocks=True,
                              trim_blocks=True,
                              undefined=jinja2.StrictUndefined,
                              autoescape=False)
tmpl = jinjaEnv.get_template('stdin');

print(tmpl.render(data = jsonData1, wire = jsonData2))
