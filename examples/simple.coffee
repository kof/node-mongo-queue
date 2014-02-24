
queue = require '../src/queue'

# Declare the job. Each time there is work to do, a new instance of this
# class will be created and the method `perform` called.
class Addition extends queue.Template
  perform: (args...) ->
    console.log arguments

    if Math.random() < 0.1
      @complete()
    else
      @release()


connection = new queue.Connection

# Insert the Addition job into the queue
connection.enqueue Addition.name, 3, 2, ->
connection.enqueue Addition.name, 3, 2, ->
connection.enqueue Addition.name, 3, 2, ->
connection.enqueue Addition.name, 3, 2, ->
connection.enqueue Addition.name, 3, 2, ->

# Create a worker which will process the Addition jobs
worker = new queue.Worker connection, [ Addition ]
worker.poll()
