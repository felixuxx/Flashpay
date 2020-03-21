#!/usr/bin/python3
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
              source = sys.stdin.read()
              return source, self.path, lambda: false


jsonFile1 = open (sys.argv[1], 'r')
jsonData1 = json.load(jsonFile1)

jsonFile2 = open (sys.argv[2], 'r')
jsonData2 = json.load(jsonFile2)

jsonFile3 = open (sys.argv[3], 'r')
jsonData3 = json.load(jsonFile3)

jsonFile4 = open (sys.argv[4], 'r')
jsonData4 = json.load(jsonFile4)

jsonFile5 = open (sys.argv[5], 'r')
jsonData5 = json.load(jsonFile5)


jinjaEnv = jinja2.Environment(loader=StdinLoader(),
                              lstrip_blocks=True,
                              trim_blocks=True,
                              undefined=jinja2.StrictUndefined,
                              autoescape=False)
tmpl = jinjaEnv.get_template('stdin');

print(tmpl.render(aggregation = jsonData1, coins = jsonData2, deposits = jsonData3, reserves = jsonData4, wire = jsonData5))
