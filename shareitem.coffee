
redis = require "redis"
_  = require 'underscore'
_.mixin require 'underscore.string'

urlsortener = require "./urlsortener"

conn = require "./redisconnection"
client = conn.getClient()


exports.ShareItem = class ShareItem

  constructor: (settings) ->
    @id = settings?.id
    @data =
      views: 0
    @config = settings?.config
    if settings?.urlId
      @id urlsortener.decode settings.urlId

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
      console.log "loading", data
      for k, v of data
        @data[k] = v
      @data.views = parseInt @data.views, 10
      cb err, @data

  getUrlId: ->
    urlsortener.encode @id

  incrViews: (cb) ->
    @data.views = parseInt(@data.views, 10) || 0
    @data.views += 1
    @save()

  save: (cb) ->
    client.hmset @getRedisKey(), _.clone(@data), ->
      cb?.apply this, arguments

  set: (ob, cb) ->
    for k, v of ob
      console.log "setting", k, "to", v

      if typeof k is "object"
        console.log "warning object key", k
        continue
      if typeof v is "object"
        console.log "warning object value", v
        continue

      @data[k] = v

    @save ->
      console.log "SAVED!", ob
      cb?.apply this, arguments

  getFsPath: ->
    __dirname + "/public/img/#{ @data.filename }"

  getSmallFsPath: ->
    noext = @data.filename.split(".")[0]
    __dirname + "/public/img/#{ noext }.small.png"

  getUrl: ->
    @config.domain + @getUrlId()

  getImgUrl: ->
    "#{ @config.domain }img/#{ @data.filename }"

  getSmallImgUrl: ->
    noext = @data.filename.split(".")[0]
    "#{ @config.domain }img/#{ noext }.small.png"



exports.ShareImg = class ShareImg


if require.main is module
  fs = require "fs"
  config = JSON.parse fs.readFileSync "./config.json"
  s = new ShareItem id: 300, config: config
  s.load ->
    console.log s.data.filename
