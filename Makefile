
.PHONY: test
test:
	coffee test/*.coffee


compile:
	./node_modules/.bin/coffee -c -o lib src/*.coffee

clean:
	rm -fr lib/


publish: compile
	npm publish

install: compile
	npm install


