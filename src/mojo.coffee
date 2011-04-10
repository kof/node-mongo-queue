
# **mojo** - a MongoDB job queue
#
# Jobs are stored in a collection and retreived or updated using the
# findAndModify command. This allows multiple workers to concurrently
# access the queue. Each job has an expiration date, and once acquired by
# a worker, also a timeout. Old jobs and stuck workers can so be identified
# and dealed with appropriately.


#### Connection

# Mojo is backed by MongoDB
mongodb = require 'mongodb'


# The **Connection** class wraps the connection to MongoDB. It includes
# methods to manipulate (add, remove, clear, ...) jobs in the queues.
class exports.Connection

  # Initialize with a reference to the MongoDB and optional options
  # hash. Two opitions are currently supported: expires and timeout.
  constructor: (options) ->
    options or options = {}
    @ensureConnection options

    @expires = options.expires or 60 * 60 * 1000
    @timeout = options.timeout or 10 * 1000


  # Open a connection to the MongoDB server. Queries created while we are
  # connecting are queued and executed after the connection is established.
  ensureConnection: (opt) ->
    @queue = []

    # TODO: support replica sets
    server = new mongodb.Server opt.host || '127.0.0.1', opt.port || 27017
    new mongodb.Db(opt.db, server, {}).open (err, db) =>
      db.collection 'mojo', (err, collection) =>
        @mojo = collection

        fn(collection) for fn in @queue if @queue
        delete @queue

        collection.ensureIndex [ ['queue'], ['expires'], ['owner'] ], ->


  # Execute the given function if the connection to the database has been
  # established. If not, put it into a queue so it can be executed later.
  exec: (fn) ->
    @queue and @queue.push(fn) or fn(@mojo)


  # Remove all jobs from the queue. This is a brute-force method, useful if
  # you want to reset mojo, for example in a test environment. Note that it
  # resets only a single queue, and not all.
  clear: (queue, callback) ->
    @exec (mojo) ->
      mojo.remove { queue }, callback


  # Insert a new job into the queue. A job is just an array of arguments
  # which are inserted into a queue. What these arguments mean is entirely
  # up to the individual workers.
  enqueue: (queue, args..., callback)->
    expires = new Date new Date().getTime() + @expires
    @exec (mojo) ->
      mojo.insert { queue, expires, args }, callback


  # Fetch the next job from the queue. The owner argument is used to identify
  # the worker which acquired the job. If you use a combination of hostname
  # and process ID, you can later identify stuck workers.
  next: (queue, owner, callback) ->
    now = new Date; timeout = new Date(now.getTime() + @timeout)
    @exec (mojo) ->
      mojo.findAndModify { queue, expires: { $gt: now }, owner: null },
        'expires', { $set: { timeout, owner } }, { new: 1 }, callback


  # After you are done with the job, mark it as completed. This will remove
  # the job from MongoDB.
  complete: (doc, callback) ->
    @exec (mojo) ->
      mojo.findAndModify { _id: doc._id },
        'expires', {}, { remove: 1 }, callback


  # You can also refuse to complete the job and leave it in the database
  # so that other workers can pick it up.
  release: (doc, callback) ->
    @exec (mojo) ->
      mojo.findAndModify { _id: doc._id },
        'expires', { $unset: { timeout: 1, owner: 1 } }, { new: 1 }, callback


  # Release all timed out jobs, this makes them available for future
  # clients again. You should call this method regularly, possibly from
  # within the workers after every couple completed jobs.
  cleanup: (queue, callback) ->
    @exec (mojo) ->
      mojo.update { timeout: { $lt: new Date } },
          { $unset: { timeout: 1, owner: 1 } }, { multi: 1 }, callback



#### Template

# Extend the **Template** class to define a job. You need to implement the
# `perform` method. That method will be called when there is work to be done.
# After you are done with the job, call `@complete` to signal the worker that
# it can process the next job.
class exports.Template
  constructor: (@worker, @doc) ->

  # Only here to bind `this` to this instance in @perform.
  invoke: ->
    @perform.apply(@, @doc.args)

  perform: (args...) ->
    throw new Error('Yo, you need to implement me!')

  # As per unwritten standard, first argument in callbacks is an error
  # indicator. So you can pass this method around as a completion callback.
  complete: (err) ->
    @worker.complete err, @doc



#### Worker

# A worker polls for new jobs and executes them.
class exports.Worker extends require('events').EventEmitter
  constructor: (@connection, @templates, options) ->
    options or options = {}

    @name = [ require('os').hostname(), process.pid ].join ':'
    @timeout = options.timeout or 1000

    @workers = options.workers or 3
    @pending = 0


  poll: ->
    # If there are too many pending jobs, sleep for a bit.
    if @pending >= @workers
      return @sleep()

    # Check the templates in round-robin order, one in each iteration.
    template = @templates.shift()
    @templates.push template

    @connection.next template.name, @name, (err, doc) =>
      if doc is undefined
        if err
          @emit 'error', err
        @sleep()
      else
        ++@pending
        new template(@, doc).invoke()
        process.nextTick =>
          @poll()


  # Sleep for a bit and then try to poll the queue again. If a timeout is
  # already active make sure to clear it first.
  sleep: ->
    clearTimeout @pollTimeout if @pollTimeout
    @pollTimeout = setTimeout =>
      @pollTimeout = null
      @poll()
    , @timeout


  complete: (err, doc) ->
    cb = => --@pending; @poll()
    if err?
      @connection.release(doc, cb)
    else
      @connection.complete(doc, cb)

