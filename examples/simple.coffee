
mongodb = require('mongodb');
server = new mongodb.Server("127.0.0.1", 27017, {});

mojo = require('../src/mojo');

class Addition extends mojo.Worker
  constructor: (connection) ->
    super connection, [ 'jobs' ], {}
    @on 'error', (err) ->
      console.log err

  process: (doc) ->
    console.log 'process ' + doc
    @complete doc

db = new mongodb.Db 'test', server, {}
db.open (error, client) ->
  connection = new mojo.Connection client, {}
  worker = new MyWorker connection

  connection.cleanup('jobs')
  connection.insert 'jobs', 'arg1', 42, ->
    console.log('inserted a new job');
    worker.poll()

