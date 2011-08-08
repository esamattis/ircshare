
kue = require "kue"
irc = require "irc"

jobs = kue.createQueue()

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
    nick = "AndroidIRCSHare"
    @registered = false

    @client = new irc.Client @address, nick,
      userName: nick
      realName: "http://github.com/epeli/androidircshare"
      autoConnect: false
    @client.on "connect", =>
      console.log "Connected to #{ @networkName } (#{ @address })"

    @client.on "registered", =>
      console.log "Registered to #{ @networkName } (#{ @address })"
      @registered = true


    @client.on "error", (err) ->
      console.log err


  start: ->
    @client.connect()
    jobs.process "irc-#{ @networkName.toLowerCase() }", (job, done) =>
      if not @registered
        done new Error("Not registered")
        return

      msg =   "<#{ job.data.nick }> #{ job.data.caption } #{ job.data.url }"
      console.log msg
      @sayAndPart job.data.channel, msg, ->
        console.log "done"
        done()

  sayAndPart: (channel, msg, cb) ->
    msg = msg.replace "\n", " "
    if /^[#!‚]/.test channel
      @client.join channel, =>
        @client.say channel, msg
        @client.part channel, cb
    else
        @client.say channel, msg
        cb?()



setTimeout ->
  jobs.failed (err, ids) ->
    throw err if err
    retryAll ids
, 2000


new IRCPoster("ircnet", "irc.jyu.fi").start()
new IRCPoster("freenode", "irc.freenode.net").start()





