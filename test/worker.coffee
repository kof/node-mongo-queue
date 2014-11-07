_ = require 'lodash'
queue = require '..'
db = require './utils/db'

QUnit.module 'Worker',
  teardown: () ->
    stop()
    db.teardown () ->
      start()

test 'test worker with one task', () ->
  expect 12

  stop()

  db.connect 'mongodb://localhost:27017/test-worker', (err) ->
    ok !err, 'connection to mongodb failed'

    class Addition extends queue.Template
      perform: (a, b) ->
        ok true
        db.conn.collection('queue').findOne {}, (err, doc) =>
          ok !err, 'error finding the task'
          equal doc.queue, 'Addition'
          ok _.isDate(doc.expires)
          deepEqual doc.args, [1, 1]
          equal doc.attempts, 0
          ok _.isDate(doc.timeout)
          ok _.isString(doc.owner)
          @complete()

    conn = new queue.Connection(db: db.conn)
    conn.on 'error', (err) ->
      ok false, err

    conn.enqueue Addition.name, 1, 1, () ->
      ok true, 'should be called when enqueued'

    worker = new queue.Worker conn, [ Addition ]
    worker.on 'error', () ->
      ok false, 'there was an error on the worker'

    worker.once 'drained', () ->
      worker.once 'stopped', () ->
        db.conn.collection('queue').count (err, count) ->
          ok !err, 'error counting'
          equal count, 0
          start()
      worker.stop()

    worker.poll()

test 'test worker with a task erroring', () ->
  expect 9

  stop()

  db.connect 'mongodb://localhost:27017/test-worker', (err) ->
    ok !err, 'connection to mongodb failed'

    class Addition extends queue.Template
      perform: (a, b) ->
        @complete new Error('task error')

    conn = new queue.Connection(db: db.conn)
    conn.on 'error', (err) ->
      ok false, err

    conn.enqueue Addition.name, 1, 2, () ->
      ok true, 'should be called when enqueued'

    worker = new queue.Worker conn, [ Addition ]
    worker.on 'error', (err) ->
      equal err.message, 'task error'

    worker.once 'drained', () ->
      worker.once 'stopped', () ->
        db.conn.collection('queue').findOne {}, (err, doc) ->
          ok !err, 'error finding task'
          equal doc.attempts, 5
          start()
      worker.stop()

    worker.poll()
