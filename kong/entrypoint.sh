#!/bin/sh
# Kong entrypoint — substitute API keys in kong config and start Kong
# Reads /tmp/kong.template.yml, replaces ${ANON_KEY} and ${SERVICE_ROLE_KEY},
# writes /tmp/kong.yml, then starts Kong.

# Use sed with a delimiter that doesn't appear in JWTs: @
# Escape special characters in the values
ANON_KEY_ESC=$(printf '%s\n' "$ANON_KEY" | sed 's/[@/\]/\\&/g')
SERVICE_ROLE_KEY_ESC=$(printf '%s\n' "$SERVICE_ROLE_KEY" | sed 's/[@/\]/\\&/g')

sed "s@\${ANON_KEY}@${ANON_KEY_ESC}@g; s@\${SERVICE_ROLE_KEY}@${SERVICE_ROLE_KEY_ESC}@g" \
  /tmp/kong.template.yml > /tmp/kong.yml

exec kong docker-start
