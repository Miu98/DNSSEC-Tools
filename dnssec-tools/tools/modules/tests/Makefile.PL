#!/usr/bin/perl

open(MF,"> Makefile");

print MF <<EOF;
#
# Copyright 2004-2013 SPARTA, Inc.  All rights reserved.  See the COPYING
# file distributed with this software for details
#
# This is a makefile for the test directory of the DNSSEC-Tools perl modules.
#

TESTFILES=	portrigh.keyrec		\\
		dnssec-tools.conf	\\
		/tmp/test.rollrec

all:
	\@echo nothing to make

install:
	\@echo nothing to install

clean:
	\@rm -f \${TESTFILES}
EOF

exit(0);
