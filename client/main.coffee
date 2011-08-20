
guidGenerator = ->
  S4 = ->
    (((1 + Math.random()) * 65536) | 0).toString(16).substring(1)

  (S4() + S4() + "-" + S4() + "-" + S4() + "-" + S4() + "-" + S4() + S4() + S4())

jQuery ($) ->
  if not window.localStorage.deviceId
    window.localStorage.deviceId = guidGenerator()
  $('[name="deviceid"]').attr "value", window.localStorage.deviceId
  $('[name="devicename"]').attr "value", window.navigator.appVersion
  $("form").dumbFormState()
