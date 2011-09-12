
mojo = require '../src/mojo'
connection = new mojo.Connection db: 'test'

# Keep track of the jobs / s we process
numCompleted = 0
lastReport = new Date().getTime()

class Noop extends mojo.Template
  perform: ->
    @complete()

    ++numCompleted
    now = new Date().getTime()
    diff = now - lastReport
    if diff > 1000
      console.log(Math.round(numCompleted / diff * 1000) + ' jobs/s')
      numCompleted = 0
      lastReport = now

# Add 100k jobs to the queue
numAdded = 0
producer = ->
  numThisRound = 0
  while numThisRound < 100 and ++numAdded < 100000
    connection.enqueue Noop.name, null, ->
    ++numThisRound

  if numAdded < 100000
    process.nextTick producer

producer()

# Create a worker which will process the jobs
worker = new mojo.Worker connection, [ Noop ], workers: 9
worker.poll()

