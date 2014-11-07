testRunner = require 'qunit'
fs = require 'fs'
path = require 'path'

tests = fs.readdirSync(__dirname).
            map((file) -> path.join __dirname, file).
            filter((file) -> /\.js/.test(file) and file isnt __filename)

options = testRunner.options
options.coverage = true

log = options.log
log.assertions = false
log.tests = false
log.summary = false

testRunner.run(
  { code: path.join(__dirname, '../lib/queue.js'), tests }
  (err) -> console.error(err) if err
)