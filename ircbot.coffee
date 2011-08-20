fs = require "fs"

kue = require "kue"
redis = require "redis"
irc = require "irc"

config = JSON.parse fs.readFileSync "./config.json"

kue.redis.createClient = ->
  client = redis.createClient(config.redis.port, config.redis.host)
  if config.redis.pass?
    client.auth config.redis.pass
  client

jobs = kue.createQueue()
db = jobs.client

retry = (id, cb) ->
  kue.Job.get id, (err, job) ->
    return cb err if err
    job.inactive()
    job.attempt ->
      job.update (err) ->
        cb err, job
        console.log "retrying job", id, job.type

retryAll = (ids) ->
  id = ids.pop()
  return if not id?
  retry id, (err) ->
    throw err if err
    retryAll ids


class IRCPoster
  constructor: (@networkName, @address) ->
    @networkName = @networkName.toLowerCase()
    nick = config.botnick
    @registered = false

    @client = new irc.Client @address, nick,
      userName: nick
      realName: "http://ircshare.com/"
      autoConnect: false
    @client.on "connect", =>
      console.log "Connected to #{ @networkName } (#{ @address })"

    @client.on "registered", =>
      console.log "Registered to #{ @networkName } (#{ @address })"
      @registered = true
      @startJobProcessor()
      chan = "#ircshare.com"
      @client.join chan, =>
        console.log "joined #{ chan }"
        @client.say chan, "Epeli: IRCShare.com is online on #{ @networkName }"
        @retryJobs()


    @client.on "message", (from, to, msg) =>
      console.log from, msg, to

    @client.on "pm", (from, msg) =>
      [cmd, deviceid] = msg.split(" ")
      return unless cmd is "register"
      userid = @userId from, deviceid

      db.set userid, true, =>
        @retryJobs()

    @client.on "error", (err) ->
      console.log "IRC ERRIR", err

  retryJobs: ->
    jobs.failed (err, ids) ->
      throw err if err
      retryAll ids

  userId: (nick, deviceid) ->
    "reg:#{ nick }@#{ @networkName }:#{ deviceid }"

  askToRegister: (nick, data) ->
    msg = "
 Somebody is trying to post a picture from #{ data.devicename } with caption
 \" #{ data.caption }\" to
 #{ data.channel } in your nickname. This nickname is not registered with that
 device on ircshare.com. If this is you: type \"register #{ data.deviceid }\"
 without quotes to register it. This will be asked only once per device, nick
 and irc network. Otherwise just ignore this."
    @client.say nick, msg

  startJobProcessor: ->
    jobs.process "irc-#{ @networkName }", (job, done) =>

      msg =   "<#{ job.data.nick }> #{ job.data.caption } #{ job.data.url }"
      userid = @userId(job.data.nick, job.data.deviceid)

      db.get userid, (err, registered) =>
        console.log "process", err, registered
        return done err if err
        if registered
          @sayAndPart job.data.channel, msg, ->
            console.log "done", msg
            done()
        else
          done new Error "#{ userid  } is not registered yet. Device #{ job.data.devicename }"
          @askToRegister job.data.nick, job.data


  start: ->
    @client.connect()

  sayAndPart: (channel, msg, cb) ->
    msg = msg.replace "\n", " "
    if /^[#!‚]/.test channel
      @client.join channel, =>
        @client.say channel, msg
        @client.part channel, cb
    else
        @client.say channel, msg
        cb?()



# setTimeout ->
#   jobs.failed (err, ids) ->
#     throw err if err
#     retryAll ids
# , 2000


for network in config.irc
  new IRCPoster(network.name, network.host).start()





