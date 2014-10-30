.PHONY: test compile-test compile clean publish install

test: compile compile-test run-test clean

compile-test:
	@./node_modules/.bin/coffee -c test/*.coffee test/**/*.coffee

clean-test:
	@rm -fr test/*.js test/**/*.js

run-test:
	@node test/tests.js

compile:
	@./node_modules/.bin/coffee -c -o lib src/*.coffee

clean: clean-test
	@rm -fr lib/

publish: compile
	npm publish

install: compile
	npm install
