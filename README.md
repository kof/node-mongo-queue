mojo -- a MongoDB job queue
===========================

**WARNING** API is subject to change.

Mojo is a job queue inspired by Resque, but is trying to improve certain
shortcomings of Resque's design. In particular, mojo makes it impossible
to loose jobs. Jobs are kept in the database until workers have successfully
completed them and only then are they removed from the database.

Even if your host or application crashes hard (without chance to catch the
exception in the application's runtime), no jobs are lost.



Example
-------

    mojo = require 'mojo'

    # First declare your job by extending mojo.Template
    class Addition extends mojo.Template
      perform: (a, b) ->
        console.log a + ' + ' + b + ' = ' + (a + b)
        @complete()

    # Create a connection to the database
    options = host: 'localhost', port: 27017, db: 'test'
    connection = new mojo.Connection options

    # Put some jobs into the queue
    connection.enqueue Addition.name, 1, 1
    connection.enqueue Addition.name, 2, 4
    connection.enqueue Addition.name, 3, 6
    connection.enqueue Addition.name, 4, 8

    # Now you need a worker who will process the jobs
    worker = new mojo.Worker connection, [ Addition ]
    worker.poll()



Bugs
----

Lots of them. Probably. I haven't checked though.
