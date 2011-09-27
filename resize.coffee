
fs = require "fs"
Canvas = require "canvas"
Image = Canvas.Image


downscale = (width, height, maxWidth) ->
  if width < maxWidth and height < maxWidth
    height = height
    width = width
  else if width > height
    scale = maxWidth / width
    width = maxWidth
    height = height * scale
  else
    scale = maxWidth / height
    height = maxWidth
    width = width * scale

  [width, height]


exports.resize = (inputPath, outputPath, maxWidth, cb) ->
  img = new Image
  img.onerror = (err) ->
    cb? err

  img.onload = ->

    [width, height] = downscale img.width, img.height, maxWidth

    canvas = new Canvas(width, height)
    ctx = canvas.getContext "2d"
    ctx.drawImage(img, 0, 0, width, height)
    canvas.toBuffer (err, buf) ->
      fs.writeFile outputPath, buf, (err) ->
        cb?(err)

  console.log "resing imgae in", inputPath
  img.src = inputPath

if require.main is module
  # exports.resize "/home/epeli/projects/ircshare/server/public/img/717074ae25c8a7e0040d8ecbb5991a06.jpg", "resized.png", 100, ->
  #   console.log "done"
  exports.resize "/home/epeli/Pictures/ensiodvd_coveri_mini.jpg", "resized.png", 100, ->
    console.log "done"
