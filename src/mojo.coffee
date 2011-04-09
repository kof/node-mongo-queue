
# **mojo** - a MongoDB job queue
#
# Jobs are stored in a collection and retreived or updated using the
# findAndModify command. This allows multiple workers to concurrently
# access the queue. Each job has an expiration date, and once acquired by
# a worker, also a timeout. Old jobs and stuck workers can so be identified
# and dealed with appropriately.


#### Connection

# The **Connection** class wraps the connection to MongoDB. It includes
# methods to manipulate (add, remove, clear, ...) jobs in the queues.
class exports.Connection
  # Initialize with a reference to the MongoDB and optional options
  # hash. Two opitions are currently supported: expires and timeout.
  constructor: (@db, options) ->
    @db.collection 'mojo', (err, collection) =>
      @mojo = collection

    @expires = options.expires or 60 * 60 * 1000
    @timeout = options.timeout or 10 * 1000


  # Remove all jobs from the queue. This is a brute-force method, useful if
  # you want to reset mojo, for example in a test environment. Note that it
  # resets only a single queue, and not all.
  clear: (queue, callback) ->
    @mojo.remove { queue }, callback


  # Insert a new job into the queue. A job is just an array of arguments
  # which are inserted into a queue. What these arguments mean is entirely
  # up to the individual workers.
  insert: (queue, args..., callback)->
    expires = new Date new Date().getTime() + @expires
    @mojo.insert { queue, expires, args }, callback


  # Fetch the next job from the queue. The owner argument is used to identify
  # the worker which acquired the job. If you use a combination of hostname
  # and process ID, you can later identify stuck workers.
  next: (queue, owner, callback) ->
    now = new Date; timeout = new Date(now.getTime() + @timeout)
    @mojo.findAndModify { queue, expires: { $gt: now }, owner: null },
      'expires', { $set: { timeout, owner } }, { new: 1 }, callback


  # After you are done with the job, mark it as completed. This will remove
  # the job from MongoDB.
  complete: (doc, callback) ->
    @mojo.findAndModify { _id: doc._id, owner: doc.owner },
      'expires', {}, { remove: 1 }, callback


  # You can also refuse to complete the job and leave it in the database
  # so that other workers can pick it up.
  release: (doc, callback) ->
    @mojo.findAndModify { _id: doc._id, owner: doc.owner },
      'expires', { $unset: { timeout: 1, owner: 1 } }, { new: 1 }, callback


  # Release all timed out jobs, this makes them available for future
  # clients again. You should call this method regularly, possibly from
  # within the workers after every couple completed jobs.
  cleanup: (queue, callback) ->
    @mojo.update { timeout: { $lt: new Date } },
        { $unset: { timeout: 1, owner: 1 } }, { multi: 1 }, callback


# Generate a number of random characters. Uses the crypto module.
crypto = require 'crypto'
random = (num) ->
  crypto.createHash('sha').update('' + new Date).digest('hex').substr(1, num)

hostname = ->
  require('os').hostname()

#### Worker

# Extend the **Worker* class to create your own workers. All you need to
# implement is the `process` method, it will be called when a new job
# needs to be processed.
class exports.Worker extends require('events').EventEmitter
  constructor: (@connection, @queues, options) ->
    @name = [ hostname(), process.pid, random(7) ].join ':'
    @timeout = options.timeout or 1000

    @maxPending = options.poolSize or 3
    @pending = 0

  process: (job) ->
    @emit 'error', new Error('You need to implement the perform method')

  poll: ->
    if @pending >= @count
      return @sleep

    # Check the queues in round-robin order, one in each iteration.
    queue = @queues.shift()
    @queues.push queue

    @connection.next queue, @name, (err, doc) =>
      if doc is null
        if err
          @emit 'error', err
        @sleep
      else
        ++@pending
        @process doc

  # Sleep for a bit and then try to poll the queue again.
  sleep: ->
    setTimeout =>
      @poll
    , @timeout

  complete: (doc) ->
    @connection.complete doc, =>
      --@pending
      @poll

  release: (doc) ->
    @connection.release doc, =>
      --@pending
      @poll

