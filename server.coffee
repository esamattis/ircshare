fs = require "fs"
path = require "path"
qs = require "querystring"

express = require "express"
redis = require "redis"
form = require('connect-form')
addCodeSharingTo = require("express-share").addCodeSharingTo

kue = require "kue"
config = JSON.parse fs.readFileSync "./config.json"

kue.redis.createClient = ->
  client = redis.createClient(config.redis.port, config.redis.host)
  if config.redis.pass?
    client.auth config.redis.pass
  client

kueui = express.createServer()
kueui.use(express.basicAuth(config.kueui.user, config.kueui.pass))
kueui.use kue.app


jobs = kue.createQueue()

app = express.createServer()

app.configure ->
  app.use form
    keepExtensions: true
    uploadDir: __dirname + '/public/img'
  app.use express.static __dirname + '/public'

addCodeSharingTo app

app.shareFs __dirname + "/client/vendor/jquery.js"
app.shareFs __dirname + "/client/vendor/dumbformstate.js"
app.shareFs __dirname + "/client/main.coffee"

app.get "/#{ config.uploadpath }", (req, res) ->
  res.render "upload.jade"
  # res.header('Content-Type', 'text/html')
  # res.end '''
  # <form action="" method="post" accept-charset="utf-8"  enctype="form-data/multipart">
  # <input type="text" name="nick" value="nick" />
  # <input type="text" name="channel" value="channel" />
  # <input type="text" name="caption" value="caption" />
  # <input type="text" name="network" value="network" />
  # <input type="file" name="picdata" />
  # <input type="hidden" name="device_id" value="" />
  # <p><input type="submit" value="Continue &rarr;"></p>
  # </form>
  # '''

app.post "/#{ config.uploadpath }", (req, res) ->

  req.form.complete (err, fields, files) ->
    if err then throw err

    for k, v of fields
      fields[k] = qs.unescape v

    fields.url = "#{ config.imgurl }#{ path.basename files.picdata.path }"
    fields.title = "#{ fields.nick } is posting '#{ fields.caption }' to #{ fields.channel }@#{ fields.network }"

    console.log fields.title

    job = jobs.create "irc-#{ fields.network.toLowerCase() }", fields
    job.save()

    res.end(fields.url)


app.listen config.port
kueui.listen 3000
