$ = jQuery

guidGenerator = ->
  S4 = ->
    (((1 + Math.random()) * 65536) | 0).toString(16).substring(1)

  (S4() + S4() + "-" + S4() + "-" + S4() + "-" + S4() + "-" + S4() + S4() + S4())

class JQEvenEmitter
  constructor: -> @_jq = jQuery {}

  on: ->                  @_jq.bind.apply @_jq, arguments
  addListener:            JQEvenEmitter::on
  once: ->                @_jq.one.apply @_jq, arguments
  removeListener: ->      @_jq.unbind.apply @_jq, arguments
  removeAllListeners:     JQEvenEmitter::removeListener
  emit: ->                @_jq.trigger.apply @_jq, arguments


class Preview

  constructor: (settings) ->
    @el = settings.el
    @imgHolder = $ "#imgpreview", @el
    @imgCaption = $ "#imgcaption", @el

  if window.FileReader
    showImage: (file) ->
      reader = new FileReader()
      reader.onload = (e) =>
        console.log "LOAD"
        img = new Image
        img.src = e.target.result
        @imgHolder.html img
      reader.readAsDataURL file
  else
    showImage: ->

  setCaption: (str) ->
    @imgCaption.text str




# Load settings
jQuery ($) ->
  if not window.localStorage.deviceId
    window.localStorage.deviceId = guidGenerator()
  $('[name="deviceid"]').attr "value", window.localStorage.deviceId
  $('[name="devicename"]').attr "value", window.navigator.appVersion
  $("form").dumbFormState()



jQuery ($) ->
  preview = new Preview el: $("#preview")
  fileInput = $("#picdata")
  fileInput.change (e) ->
    preview.showImage e.target.files[0]

  captionTextArea = $("#caption")
  setCaption = ->
    preview.setCaption captionTextArea.val()
  setCaption()
  captionTextArea.keydown setCaption


  $(document).bind "dragenter", (e) ->
    e.preventDefault()
    e.originalEvent.dataTransfer.dropEffect = 'copy'
    console.log "enter!", e
  $(document).bind "dragover", (e) ->
    e.preventDefault()
    e.originalEvent.dataTransfer.dropEffect = 'copy'
    # console.log "over", e
  $(document).bind "dragleave", (e) ->
    e.preventDefault()
    console.log "dragleave", e
  $(document).bind "dragend", (e) ->
    e.preventDefault()
    console.log "dragend", e
  $(document).bind "drop", (e) ->
    e.preventDefault()
    file = e.originalEvent.dataTransfer.files[0]
    preview.showImage file




