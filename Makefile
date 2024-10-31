# John, 2015-11-04 Makefile for lab4 testsuite

goodhs=$(wildcard good/*.hs)
goodgolden=$(patsubst %.hs,%.golden,$(goodhs))

.PHONY: suite
suite : lab4-testsuite.tar.gz

lab4-testsuite.tar.gz : build-tarball.sh plt-test-lab4.cabal plt-test-lab4.hs bad/*.hs $(goodhs)
	./build-tarball.sh

.PHONY: test
test: test-stack test-cabal

.PHONY: test-cabal
test-cabal:
	cabal build all

.PHONY: test-stack
test-stack:
	stack build

# Test good tests for valid Haskell by running them.

.PHONY: good-haskell
good-haskell: $(goodgolden)

%.golden : %.hs
	runghc $< | tee $@

clean :
	rm -f $(goodgolden)

# EOF
