
fs = require "fs"
redis = require "redis"

config = JSON.parse fs.readFileSync "./config.json"

exports.getClient = ->
  client = redis.createClient(config.redis.port, config.redis.host)
  if config.redis.pass?
    client.auth config.redis.pass
  client
