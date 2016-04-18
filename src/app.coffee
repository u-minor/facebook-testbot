#process.env.DEBUG = 'fb-testbot:*'
Q = require 'q'
config = require 'config'
request = require 'request'
express = require 'express'

app = express()
app.use require('body-parser').json limit: '5mb'
app.use require('cookie-parser')()
app.use require('cors')() if process.env.NODE_ENV is 'development'

app.get '/webhook', (req, res) ->
  if req.query['hub.verify_token'] is config.facebook.verifyToken
    res.json body: req.query['hub.challenge']
  res.json body: 'Wrong validation token!'

app.post '/webhook', (req, res) ->
  parr = []

  messaging_events = req.body.entry[0].messaging
  for event in messaging_events
    sender = event.sender.id
    if event.message and event.message.text
      text = event.message.text
      parr.push sendTextMessage sender, "Text received, echo: #{text.substring 0, 200}"

  Q.all parr
  .then ->
    res.json message: 'OK'

app.use (req, res, next) ->
  res.status 404
  .json error: 'Not Found'

sendTextMessage = (sender, text) ->
  messageData =
    text: text

  Q.nfcall request
    url: 'https://graph.facebook.com/v2.6/me/messages'
    qs:
      access_token: config.facebook.pageAccessToken
    method: 'POST'
    json:
      recipient:
        id: sender
      message: messageData
  , (err, res) ->
    if err
      console.log 'Error sending message: ', err
    else if res.body.error
      console.log 'Error: ', res.body.error

module.exports = app
