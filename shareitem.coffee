
redis = require "redis"
_  = require 'underscore'
_.mixin require 'underscore.string'
winston = require "winston"

urlshortener = require "./urlshortener"

conn = require "./redisconnection"
client = conn.getClient()

matcher = /\.\w+$/
swapExtension = (file, ext) ->
  if matcher.test file
    file.replace matcher, ".#{ ext }"
  else
    file + ".#{ ext }"

exports.ShareItem = class ShareItem

  constructor: (settings) ->
    @id = settings?.id
    @data =
      views: 0
    @config = settings?.config
    if settings?.urlId
      @id urlshortener.decode settings.urlId

  getRedisKey: -> "share:#{ @id }"

  load: (cb) ->
    if not @id
      client.incr "sharecount", (err, id) =>
        return cb err if err
        @id = id
        @data.created = new Date().getTime()
        @fetchData cb
    else
      @fetchData cb

  fetchData: (cb) ->
    client.hgetall @getRedisKey(), (err, data) =>
      for k, v of data
        @data[k] = v
      @data.views = parseInt @data.views, 10
      cb err, @data

  getUrlId: ->
    urlshortener.encode @id

  incrViews: (cb) ->
    @data.views = parseInt(@data.views, 10) || 0
    @data.views += 1
    @save()

  save: (cb) ->
    client.hmset @getRedisKey(), _.clone(@data), ->
      cb?.apply this, arguments

  set: (ob, cb) ->
    for k, v of ob

      if typeof k is "object"
        winston.warn  "warning object key", k
        continue
      if typeof v is "object"
        winston.warn  "warning object value", v
        continue

      @data[k] = v

    @save ->
      cb?.apply this, arguments

  getFsPath: ->
    __dirname + "/public/img/#{ @data.filename }"

  getSmallImgPath: ->
    swapExtension @data.filename, "small.jpg"

  getSmallFsPath: ->
    __dirname + "/public/img/#{ @getSmallImgPath() }"

  getSmallImgUrl: ->
    "http://#{ @config.domain }/img/#{ @getSmallImgPath()}"

  getUrl: ->
    "http://#{ @config.domain }/i/#{ @getUrlId() }"

  getImgUrl: ->
    "http://#{ @config.domain }/img/#{ @data.filename }"




exports.ShareImg = class ShareImg


if require.main is module
  fs = require "fs"
  config = JSON.parse fs.readFileSync "./config.json"
  s = new ShareItem id: 300, config: config
  s.load ->
    console.log s.data.filename
