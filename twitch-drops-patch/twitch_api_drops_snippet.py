# Local addition to twitch_api.py (class TwitchApi) in mwiens91/twitch-game-notify.
# Not part of the upstream project.

def get_streams_with_drops(self, game_id):
    response = self.make_http_request(
        TWITCH_STREAM_API_URL + "?first=100&game_id=" + game_id
    )
    drop_streams = []
    for stream in response.json()["data"]:
        tags = stream.get("tags") or []
        # Twitch tags participating streams with "DropsEnabled"
        if any(tag.lower() == "dropsenabled" for tag in tags):
            drop_streams.append(stream)
    return drop_streams

# Also in configuration.py, add this to the schema so the new key is accepted:
#   Optional("watch-drops"): [And(str, len)]
