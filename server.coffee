fs = require "fs"
path = require "path"
qs = require "querystring"

express = require "express"
cluster = require "cluster"
redis = require "redis"
form = require('connect-form')
stylus = require "stylus"
nib = require "nib"

_  = require 'underscore' 
_.mixin require 'underscore.string' 

addCodeSharingTo = require("express-share").addCodeSharingTo

urlsortener = require "./urlsortener"

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
db = jobs.client

app = express.createServer()

app.configure ->
  app.use form
    keepExtensions: true
    uploadDir: __dirname + '/public/img'
  app.use express.static __dirname + '/public'

  app.use stylus.middleware
    force: true
    src: __dirname + "/public"
    compile: (str, path) ->
      console.log path
      stylus(str).set("filename", path).use(nib())

  addCodeSharingTo app


app.shareFs __dirname + "/client/vendor/jquery.js"
app.shareFs __dirname + "/client/vendor/jquery.validate.js"
app.shareFs __dirname + "/client/vendor/underscore.js"
app.shareFs __dirname + "/client/vendor/backbone.js"
app.shareFs __dirname + "/client/vendor/dumbformstate.js"
app.shareFs __dirname + "/client/main.coffee"

app.get "/#{ config.uploadpath }", (req, res) ->
  res.render "upload.jade"


app.get new RegExp("^/([#{ urlsortener.alphabet }]+$)"), (req, res) ->
  url = req.params[0]
  jobid = urlsortener.decode url

  kue.Job.get jobid, (err, job) ->
    throw err if err
    if not job
      res.render "404.jade", status: 404, message: "No such image"
      return

    noext = job.data.img.split(".")[0]
    data =
      imgSmalUrl: "#{ config.domain }img/#{ noext }.small.png"
      imgUrl: "#{ config.domain }img/#{ job.data.img }"
    res.render "image.jade", _.extend(data, job.data, config)




app.post "/#{ config.uploadpath }", (req, res) ->
  req.form.complete (err, fields, files) ->
    if err then throw err
    res.contentType('json')

    for k, v of fields
      fields[k] = qs.unescape v

    fields.status = "starting"


    if not files?.picdata?.path
      res.end JSON.stringify
        error: 1
        message: "Image is missing"
      return

    if not fields.deviceid
      res.end JSON.stringify
        error: 1
        message: "Device id is missing"
      return

    if not fields.network
      res.end JSON.stringify
        error: 1
        message: "Network is missing"
      return

    fields.img = path.basename files.picdata.path
    fields.title = "#{ fields.nick } is posting '#{ fields.caption }' to #{ fields.channel }@#{ fields.network }"

    resizeJob = jobs.create "resizeimg", fields
    resizeJob.save ->
      console.log "url", config.domain + urlsortener.encode resizeJob.id
      res.end JSON.stringify
        url: config.domain + urlsortener.encode resizeJob.id


resizeCluster = cluster()
  .set("workers", 1)
  .use(cluster.debug())
  .start()
if resizeCluster.isMaster
  app.listen config.port
  kueui.listen 3000
  console.log "master", process.pid
else
  {resize} = require "./resize"
  console.log resize
  jobs.process "resizeimg", (job, done) ->
    console.log "resizeing", job.data.img
    input = __dirname + "/public/img/#{ job.data.img }"
    noext = job.data.img.split(".")[0]
    output = __dirname + "/public/img/#{ noext }.small.png"

    resize input, output, 640, (err) ->
      if err
        done err
      else
        ircJob = jobs.create "irc-#{ job.data.network.toLowerCase() }", job.data
        ircJob.save (err) ->
          if err
            done err
          else
            done()


