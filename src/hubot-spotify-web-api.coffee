# Description:
#   Allows hubot to interact with spotify
#
# Dependencies:
#   spotify-web-api-node
#
# Configuration:
#   SPOTIFY_ANNOUNCE_CHANNEL
#   SPOTIFY_APP_CLIENT_ID
#   SPOTIFY_APP_CLIENT_SECRET
#   SPOTIFY_PLAYLIST_ID
#   SPOTIFY_SPOTIFY_REDIRECT_URI
#   SPOTIFY_USER_ID
#
# Commands:
#   hubot spotify find <query> - Finds a list of matching songs
#   hubot spotify search <query> - Finds a list of matching songs
#   hubot spotify playlist addId <id> - Adds a song by trackId
#   hubot spotify playlist list - Returns the list of current tracks in the playlist
#
# Author:
#   mickfeech
#

# Requires and Variables
querystring = require('querystring')
SpotifyWebApi = require('spotify-web-api-node')
clientId = process.env.SPOTIFY_APP_CLIENT_ID
clientSecret = process.env.SPOTIFY_APP_CLIENT_SECRET
redirectUri = process.env.SPOTIFY_REDIRECT_URI
playlistId = process.env.SPOTIFY_PLAYLIST_ID
userId = process.env.SPOTIFY_USER_ID
announceChannel = process.env.SPOTIFY_ANNOUNCE_CHANNEL

# Initialize API object
spotifyApi = new SpotifyWebApi(
  clientId: clientId
  clientSecret: clientSecret
  redirectUri: redirectUri)

getTrackName = (trackId) ->
  spotifyApi.getTrack(trackId).then ((data) ->
    return Promise.resolve(data.body.name)
  )

getTrackArtist = (trackId) ->
  spotifyApi.getTrack(trackId).then ((data) ->
    return Promise.resolve(data.body.artists[0].name)
  )

requestTokens = (code, brain) ->
  spotifyApi.authorizationCodeGrant(code).then ((data) ->
    console.log 'The token expires in ' + data.body['expires_in']
    console.log 'The access token is ' + data.body['access_token']
    console.log 'The refresh token is ' + data.body['refresh_token']
    # Set the access token on the API object to use it in later calls
    spotifyApi.setAccessToken data.body['access_token']
    spotifyApi.setRefreshToken data.body['refresh_token']
    brain.set 'access_token', data.body['access_token']
    brain.set 'refresh_token', data.body['refresh_token']
    brain.set 'expires', (new Date().getTime() + (data.body['expires_in'] * 1000))
    return
  ), (err) ->
    console.log 'Something went wrong!', err
    return

refreshTokens = (token) ->
  spotifyApi.setRefreshToken(token)
  spotifyApi.refreshAccessToken().then ((data) ->
    console.log 'The access token has been refreshed!'
    # Save the access token so that it's used in future calls
    spotifyApi.setAccessToken data.body['access_token']
    return Promise.resolve(true)
  ), (err) ->
    console.log 'Could not refresh access token', err
    return Promise.resolve(false)

module.exports = (robot) ->
  # Build Auth link
  robot.respond /spotify auth/i, (res) ->
    console.log 'Requesting Auth'
    scopes = [
      "playlist-modify-public"
      "playlist-modify-private"
    ]
    state = 'accepted'
    authorizeUrl = spotifyApi.createAuthorizeURL(scopes, state)
    res.send authorizeUrl

  # HTTP Listener
  robot.router.get '/hubot/spotify', (req, res) ->
    query = querystring.parse(req._parsedUrl.query)
    res.set 'Content-Type', 'text/plain'
    res.send 'OK, authorization granted'
    room = robot.adapter.client.rtm.dataStore.getDMByName 'mickfeech'
    robot.messageRoom room.id, query.code

  # Find tracks
  robot.respond /spotify (?:find|search) (.*)/i, (res) ->
    trackSearch = res.match[1]
    console.log "Doing a search for #{trackSearch}"
    spotifyApi.searchTracks(trackSearch).then ((data) ->
      string = "*Track Name* - *Artist Name* - *Album Name* - *Track ID* \n"
      for track in data.body.tracks.items
        if track.type == "track"
          string = string + "#{track.name} - #{track.artists[0].name} - #{track.album.name} - #{track.id} \n"
      console.log "sending results"
      string = string + "\n\n_To add to the playlist respond with_ `spotify playlist addId <Track ID>`"
      room = robot.adapter.client.rtm.dataStore.getDMByName res.message.user.name
      robot.messageRoom room.id, string
    )

 # Add track to playlist by id
  robot.respond /spotify playlist addId (.*)/i, (res) ->
    refreshTokens(robot.brain.get('refresh_token')).then ->
      return
    .then ->
      trackId = res.match[1]
      spotifyApi.addTracksToPlaylist(userId, playlistId, [
        "spotify:track:#{trackId}"
      ]).then ((data) ->
        getTrackName(trackId).then ((trackName) ->
          getTrackArtist(trackId).then ((artistName) ->
            room = robot.adapter.client.rtm.dataStore.getDMByName res.message.user.name
            robot.messageRoom room.id, "Added *#{trackName}* by *#{artistName}* to playlist"
            robot.send room: announceChannel, "#{res.message.user.name} added *#{trackName}* by *#{artistName}* to the playlist."
            return
          )
        )
      ), (err) ->
        console.log 'Something went wrong!', err
        return

  # Get playlist Entries
  robot.respond /spotify playlist list/i, (res) ->
    refreshTokens(robot.brain.get('refresh_token')).then ->
      return
    .then ->
      spotifyApi.getPlaylist(userId, playlistId).then ((data) ->
        string = ""
        track_count = 1
        for t in data.body.tracks.items
          string = string + "#{track_count} - #{t.track.artists[0].name} - #{t.track.name}\n"
          track_count++
        msgData = {
          attachments: [
            {
              title: 'Current Spotify Playlist'
              text: string
              fallback: 'Current Spotify Playlist'
              color: '#00cc99'
            }
          ]
        }
        robot.send room: announceChannel, msgData
        return
      ), (err) ->
        console.log 'Something went wrong!', err
        return
