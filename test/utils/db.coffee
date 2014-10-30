mongodb = require 'mongodb'

exports.conn = null

exports.connect = (connStr, callback) ->
  mongodb.MongoClient.connect connStr, (err, db) ->
    callback(err) if err
    db.dropDatabase (err) ->
      callback(err) if err
      exports.conn = db
      callback()

exports.teardown = (callback) ->
  exports.conn.dropDatabase () ->
    exports.conn.close true, () ->
      exports.conn = null
      callback()