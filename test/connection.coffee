_ = require 'lodash'
queue = require '..'
db = require './utils/db'

QUnit.module 'Connection',
  teardown: () ->
    stop()
    db.teardown () ->
      start()

test 'test connection with defaults', () ->
  expect 3

  stop()

  db.connect 'mongodb://localhost:27017/queue', (err) ->
    ok !err, 'connection to mongodb failed'
    conn = new queue.Connection
    conn.once 'connected', () ->
      db.conn.collection('queue').indexes (err, indexes) ->
        ok !err, 'getting indexes failed'
        equal indexes.length, 2
        start()

test 'providing a connection', () ->
  expect 3

  stop()

  db.connect 'mongodb://localhost:27017/test-queue', (err) ->
    ok !err, 'connection to mongodb failed'
    conn = new queue.Connection(db: db.conn)
    conn.once 'connected', () ->
      db.conn.collection('queue').indexes (err, indexes) ->
        ok !err, 'getting indexes failed'
        equal indexes.length, 2
        start()

test 'enqueue a task', () ->
  expect 7

  stop()

  db.connect 'mongodb://localhost:27017/test-queue', (err) ->
    ok !err, 'connection to mongodb failed'
    conn = new queue.Connection(db: db.conn)
    conn.once 'connected', () ->
      conn.enqueue 'Addition', () ->
        db.conn.collection('queue').find().toArray (err, docs) ->
          ok !err, 'error retrieving documents'
          equal docs.length, 1
          doc = docs[0]
          equal doc.queue, 'Addition'
          ok _.isDate(doc.expires)
          equal doc.args.length, 0
          equal doc.attempts, 0
          start()

test 'enqueue a task overriding its settings', () ->
  expect 5

  stop()

  db.connect 'mongodb://localhost:27017/test-queue', (err) ->
    ok !err, 'connection to mongodb failed'
    conn = new queue.Connection(db: db.conn)
    conn.once 'connected', () ->
      task =
        queue: 'Testing',
        startDate: new Date(0),
        expires: 90 * 60 * 1000
      conn.enqueue task, () ->
        db.conn.collection('queue').find().toArray (err, docs) ->
          ok !err, 'error retrieving documents'
          equal docs.length, 1
          doc = docs[0]
          equal doc.queue, 'Testing'
          equal +doc.expires, +new Date(90 * 60 * 1000)
          start()