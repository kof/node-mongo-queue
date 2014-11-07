queue = require '..'

QUnit.module 'Template'

test 'perform throws if not implemented', () ->
  expect 1

  class Empty extends queue.Template

  empty = new Empty
  throws(
    () -> empty.perform()
    'Unimplemented template should throw an error on perform'
  )

test 'executes an addition', () ->
  expect 3

  class Addition extends queue.Template
    perform: (a, b) ->
      @worker.result = a + b
      @complete()

  worker =
    complete: (err, doc) ->
      equal err, undefined
      deepEqual doc.args, [1, 2]
      equal @result, 3

  addition = new Addition(worker, args: [1, 2])
  addition.invoke()

test 'crash the worker', () ->
  expect 2

  class Crash extends queue.Template
    perform: () ->
      ok true, 'should go through here'
      throw new Error

  worker =
    complete: (err) ->
      ok !!err

  crash = new Crash(worker, args: [])
  crash.invoke()
