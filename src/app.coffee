#process.env.DEBUG = 'fb-testbot:*'
AWS = require 'aws-sdk'
Q = require 'q'
config = require 'config'
request = require 'request'
express = require 'express'
Wit = require('node-wit').Wit

AWS.config.update config.aws
sdb = new AWS.SimpleDB()

session = {}
client = new Wit config.wit.token,
  say: (sessionId, context, msg, cb) ->
    # if session.fbid
    sendTextMessage session[sessionId].facebookId, msg
    .then -> cb()
  merge: (sessionId, context, entities, message, cb) ->
    cb context
  error: (sessionId, context, err) ->
    console.log err
  'fetch-weather': (sessionId, context, cb) ->
    context.forecast = 'cloudy'
    cb context

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
      do (text = event.message.text) ->
        sessionId = null
        ret = getSession sender
        .then (data) ->
          console.log 'session:', data
          sessionId = data.sessionId
          session[sessionId] = data

          Q.ninvoke client, 'runActions', data.sessionId, text, data.context
        .then (context) ->
          session[sessionId].context = context
          putSession session[sessionId]
        .fail (err) ->
          console.log 'fail:', err

        parr.push ret

  Q.all parr
  .then ->
    res.json message: 'OK'
  .fail (err) ->
    console.log err
    res.json message: 'Error'

app.use (req, res, next) ->
  res.status 404
  .json error: 'Not Found'

getSession = (sender) ->
  Q.ninvoke sdb, 'getAttributes',
    DomainName: config.simpleDb.domain
    ItemName: "#{sender}"
  .then (data) ->
    return JSON.parse data.Attributes[0].Value if data.Attributes
    return {
      sessionId: "#{sender}_#{new Date().toISOString()}"
      facebookId: sender
      context: {}
    }

putSession = (session) ->
  Q.ninvoke sdb, 'putAttributes',
    DomainName: config.simpleDb.domain
    ItemName: "#{session.facebookId}"
    Attributes: [
      Name: 'session'
      Value: JSON.stringify session
      Replace: true
    ]

sendTextMessage = (sender, text) ->
  messageData =
    text: text

  Q.nfcall request,
    url: 'https://graph.facebook.com/me/messages'
    qs:
      access_token: config.facebook.pageAccessToken
    method: 'POST'
    json:
      recipient:
        id: sender
      message: messageData

module.exports = app
