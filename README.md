# A MongoDB job queue

[![Build Status](https://secure.travis-ci.org/kof/node-mongo-queue.svg)](http://travis-ci.org/kof/node-mongo-queue)

Its is a job queue inspired by Resque, but is trying to improve certain
shortcomings of Resque's design. In particular, mongo-queue makes it impossible
to loose jobs. Jobs are kept in the database until workers have successfully
completed them and only then are they removed from the database.

Even if your host or application crashes hard (without chance to catch the
exception in the application's runtime), no jobs are lost.


# API

## Connection

An object that will hold the MongoDB connection and allow manipulation of the job queue.

### constructor([options])

Options are :

- `expires`: time in milliseconds until a job is no more valid. Defaults to 1h.
- `timeout`: time in milliseconds allowed to workers before a job goes back to the queue to be processed by another worker. Defaults to 10s.
- `maxAttempts`: maximum number of attempts to run the job. Defaults to 5.
- `host`: hostname for the MongoDB database. Defaults to '127.0.0.1'.
- `port`: port for the MongoDB database. Defaults to 27017.
- `db`: either a [MongoDB connection](http://mongodb.github.io/node-mongodb-native/1.4/api-generated/db.html) or a string for the database name. Defaults to 'queue'.
- `username`: login for an authenticated MongoDB database.
- `password`: password for an authenticated MongoDB database.

### Methods

#### enqueue(queue, args..., callback)

Adds a job to the queue.

- `queue`: either a string with the name of the queue, or an object containing :
  - `queue`: the name of the queue.
  - `expires`: override the `expires` of the connection for this job.
  - `startDate`: a Date object defining a future point in time when the job should execute.
- `args...`: any number of arguments your job should take.
- `callback(err, job)`: provides the feedback from the database after the job is inserted.

### Events

#### error(err)

Emitted in case of a connection error.

#### connected

Emitted when the [`Connection`](#connection) object is ready to work.

## Template

Base class to create your own job templates, you need to inherit from it.

### Methods

#### perform([...])

Function containing your job's code. You can define any arguments you need.

Any synchronous exception thrown will be caught and the job will go back to the queue.

#### complete([err])

You need to call this function when you are done with the job.

You can provide an error in case anything went wrong.

## Worker

Worker object that will watch out for new jobs and run them.

### constructor(connection, templates, options)

You need to provide a [`Connection`](#connection) object and an array of [`Worker`](#worker) classes.

Options are :

- `timeout`: time in milliseconds for the database polling. Defaults to 1s.
- `rotate`: boolean, indicates if you want job types to be processed in a round-robin fashion or sequentially, meaning all jobs of type A would have to done before jobs of type B. Defaults to false.
- `workers`: integer indicating the maximum number of jobs to execute in parallel. Defaults to 3.

### Methods

#### poll()

Starts the polling of the database.

#### stop()

Stops the worker, it will not interrupt an ongoing job.

### Events

#### error(err)

Emitted on polling errors, unknown template definitions or job error.

#### drained

Emitted when the queue has no more job to process or if there is no job to run on a poll.

#### stopped

Emitted after a call to `stop()` and once all the jobs are stopped.

# Example

    queue = require 'mongo-queue'

    # First declare your job by extending queue.Template
    class Addition extends queue.Template
      perform: (a, b) ->
        console.log a + ' + ' + b + ' = ' + (a + b)
        @complete()

    # Create a connection to the database
    options = host: 'localhost', port: 27017, db: 'test'
    connection = new queue.Connection options

    # Listen to connection errors
    connection.on 'error', console.error

    # Put some jobs into the queue
    connection.enqueue Addition.name, 1, 1, (err, job) -> if err then console.log(err) else console.log('Job added :', job)
    connection.enqueue Addition.name, 2, 4, (err, job) -> if err then console.log(err) else console.log('Job added :', job)
    connection.enqueue Addition.name, 3, 6, (err, job) -> if err then console.log(err) else console.log('Job added :', job)
    connection.enqueue Addition.name, 4, 8, (err, job) -> if err then console.log(err) else console.log('Job added :', job)

    # Now you need a worker who will process the jobs
    worker = new queue.Worker connection, [ Addition ]
    worker.on 'error', console.error
    worker.poll()
