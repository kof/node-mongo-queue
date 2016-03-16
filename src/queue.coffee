# **mongo-queue** - a MongoDB job queue
#
# Jobs are stored in a collection and retrieved or updated using the
# findAndModify command. This allows multiple workers to concurrently
# access the queue. Each job has an expiration date, and once acquired by
# a worker, also a timeout. Old jobs and stuck workers can so be identified
# and dealt with appropriately.


#### Connection

# mongo-queue is backed by MongoDB
mongodb = require 'mongodb'
EventEmitter = require('events').EventEmitter

# The **Connection** class wraps the connection to MongoDB. It includes
# methods to manipulate (add, remove, clear, ...) jobs in the queues.
class exports.Connection extends EventEmitter

  # Initialize with a reference to the MongoDB and optional options
  # hash. Two options are currently supported: expires and timeout.
  constructor: (options) ->
    options or options = {}
    @expires = options.expires or 60 * 60 * 1000
    @timeout = options.timeout or 10 * 1000
    @maxAttempts = options.maxAttempts or 5
    @queue = []
    setImmediate () =>
      @ensureConnection options

  # Open a connection to the MongoDB server. Queries created while we are
  # connecting are queued and executed after the connection is established.
  ensureConnection: (opt) ->
    afterConnectionEstablished = (err) =>
      return @emit('error', err) if err

      # Make a lame read request to the database. This will return an error
      # if the client is not authorized to access it.
      db.collections (err) =>
        return @emit('error', err) if err

        db.collection 'queue', (err, collection) =>
          return @emit('error', err) if err

          @collection = collection
          fn(collection) for fn in @queue if @queue
          delete @queue

          collection.ensureIndex [ ['expires'], ['owner'], ['queue'] ], (err) =>
            if err then @emit('error', err) else @emit('connected')

    # Use an existing database connection if one is passed
    if opt.db instanceof mongodb.Db
      db = opt.db;
      return db.once('open', afterConnectionEstablished) unless db.serverConfig.isConnected()
      return afterConnectionEstablished null

    # TODO: support replica sets
    # TODO: support connection URIs

    url = "mongodb://"

    if opt.username and opt.password
      url += encodeURIComponent("#{opt.username}")+":"+encodeURIComponent("#{opt.password}") + '@'

    url += "#{opt.host || '127.0.0.1'}:#{opt.port || 27017}/#{opt.db || 'queue'}?w=1"

    mongodb.MongoClient.connect url, (err, _db) =>
      @emit('error', err) if err
      db = _db if _db
      afterConnectionEstablished null


  # Execute the given function if the connection to the database has been
  # established. If not, put it into a queue so it can be executed later.
  exec: (fn) ->
    @queue and @queue.push(fn) or fn(@collection)


  # Remove all jobs from the queue. This is a brute-force method, useful if
  # you want to reset queue, for example in a test environment. Note that it
  # resets only a single queue, and not all.
  clear: (queue, callback) ->
    @exec (collection) ->
      collection.remove { queue }, callback


  # Insert a new job into the queue. A job is just an array of arguments
  # which are inserted into a queue. What these arguments mean is entirely
  # up to the individual workers.
  enqueue: (queue, args..., callback)->
    @exec (collection) =>
      return callback(new Error('Last argument must be a callback')) if typeof callback isnt 'function'
      scheduledDate = queue.startDate if queue.startDate
      startDate = scheduledDate or Date.now()
      expires = new Date(+startDate + (queue.expires or @expires))
      attempts = 0
      queue = queue.queue or queue

      task = { queue, expires, args, attempts }
      task.startDate = scheduledDate if scheduledDate
      collection.insertOne task, callback


  # Fetch the next job from the queue. The owner argument is used to identify
  # the worker which acquired the job. If you use a combination of hostname
  # and process ID, you can later identify stuck workers.
  next: (queue, owner, callback) ->
    now = new Date; timeout = new Date(now.getTime() + @timeout)
    query =
      expires: { $gt: now }
      $or: [
        { startDate: { $lte: now } },
        { startDate: { $exists: false } },
      ]
      owner: null
      attempts:
        $lt: @maxAttempts

    update = { $set: { timeout, owner } }
    options = { sort: { expires: 1 }, returnOriginal: false }

    if queue then query.queue = queue
    @exec (collection) ->
      collection.findOneAndUpdate query, update, options, (err, result) -> callback err, result?.value


  # After you are done with the job, mark it as completed. This will remove
  # the job from MongoDB.
  complete: (doc, callback) ->
    @exec (collection) ->
      query = { _id: doc._id }
      options = { sort: { expires: 1 } }

      collection.findOneAndDelete query, options, (err, result) -> callback err, result?.value


  # You can also refuse to complete the job and leave it in the database
  # so that other workers can pick it up.
  release: (doc, callback) ->
    @exec (collection) ->
      query = { _id: doc._id }
      update = { $unset: { timeout: 1, owner: 1 }, $inc: {attempts: 1} }
      options = { sort: { expires: 1 }, returnOriginal: false }

      collection.findOneAndUpdate query, update, options, (err, result) -> callback err, result?.value


  # Release all timed out jobs, this makes them available for future
  # clients again. You should call this method regularly, possibly from
  # within the workers after every couple completed jobs.
  cleanup: (callback) ->
    @exec (collection) ->
      query = { timeout: { $lt: new Date } }
      update = { $unset: { timeout: 1, owner: 1 } }
      options = { multi: 1 }

      collection.update query, update, options, callback



#### Template

# Extend the **Template** class to define a job. You need to implement the
# `perform` method. That method will be called when there is work to be done.
# After you are done with the job, call `@complete` to signal the worker that
# it can process the next job.
class exports.Template
  constructor: (@worker, @doc) ->

  # Bind `this` to this instance in @perform and catch any exceptions.
  invoke: ->
    try
      @perform.apply @, @doc.args
    catch err
      @complete err

  # Implement this method. If you don't, kittens will die!
  perform: (args...) ->
    throw new Error 'Yo, you need to implement me!'


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
    @rotate = options.rotate or false
    @workers = options.workers or 3
    @pending = 0


  poll: ->
    return if @stopped

    # If there are too many pending jobs, sleep for a bit.
    if @pending >= @workers
      return @sleep()

    Template = @getTemplate()
    templateName = if Template then Template.name

    @connection.next templateName, @name, (err, doc) =>
      if err? and err.message isnt 'No matching object found'
        @emit 'error', err
      else if doc?
        ++@pending
        if !Template then Template = @getTemplate(doc.queue)
        if Template
          new Template(@, doc).invoke()
        else
          @emit 'error', new Error("Unknown template '#{ @name }'")
        process.nextTick =>
          @poll()
      else
        @emit 'drained' if @pending is 0

      @sleep()

  getTemplate: (name) ->
    Template = null
    if name
      @templates.some (_Template) =>
        if _Template.name == name
          Template = _Template
          true
    # Check the templates in round-robin order, one in each iteration.
    else if @rotate
      Template = @templates.shift()
      @templates.push Template
    Template

  # Sleep for a bit and then try to poll the queue again. If a timeout is
  # already active make sure to clear it first.
  sleep: ->
    clearTimeout @pollTimeout if @pollTimeout

    if not @stopped
      @pollTimeout = setTimeout =>
        @pollTimeout = null
        @poll()
      , @timeout


  complete: (err, doc) ->
    cb = =>
      --@pending
      @poll() if not @stopped
      @emit 'stopped' if @pending is 0

    if err?
      @emit 'error', err
      @connection.release doc, cb
    else
      @connection.complete doc, cb

  stop: () ->
    @stopped = true
    clearTimeout @pollTimeout
    @emit 'stopped' if @pending is 0

