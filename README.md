
## Hubot HangupsJS

This is a [Hubot](https://hubot.github.com/) adapter for [Google Hangouts](http://www.google.com/+/learnmore/hangouts/).


## Installation

#### Create a new bot

Detailed instructions can be found on the [Hubot wiki](https://hubot.github.com/docs/)

Simple instructions are:

    npm install -g yo generator-hubot
    mkdir myhubot
    cd myhubot
    yo hubot
    
#### Include the adapter

`npm install hubot-hangupsjs --save`

#### Run hubot with the hangupsjs adapter

`bin/hubot -a hangupsjs`

## Configuration

#### Set the Google authentication token

Set the environment variable `HUBOT_GOOGLE_AUTH_TOKEN` to the value found here: [https://accounts.google.com/o/oauth2/auth?&client_id=936475272427.apps.googleusercontent.com&scope=https%3A%2F%2Fwww.google.com%2Faccounts%2FOAuthLogin&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob&response_type=code](https://accounts.google.com/o/oauth2/auth?&client_id=936475272427.apps.googleusercontent.com&scope=https%3A%2F%2Fwww.google.com%2Faccounts%2FOAuthLogin&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob&response_type=code "https://accounts.google.com/o/oauth2/auth?&client_id=936475272427.apps.googleusercontent.com&scope=https%3A%2F%2Fwww.google.com%2Faccounts%2FOAuthLogin&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob&response_type=code")

Alternatively, if the environment variable is omitted the console will interactively request the token from the same URL.

This is a a Google whitelisted OAuth CLIENT\_ID and CLIENT\_SECRET that shows up as "iOS Device" in your accounts page.

This token is a one-time token so it will not work on redeployment or after significant time or changes are made. A new token will have to be obtained and the environment variable removed or reset.

#### Hubot auth

It's highly recommended that you use the [hubot-auth](https://github.com/hubot-scripts/hubot-auth/) script since this bot will be publicly accessible.

You can get the user IDs required for the `HUBOT_AUTH_ADMIN` setting by calling the [plus.people.get API method](https://developers.google.com/apis-explorer/#p/plus/v1/plus.people.get?userId=%252BDavidKassa&fields=id&_h=1&).

#### Google account settings

I'm not sure if these steps are necessary, but I have set/changed the following settings on my bot account.

Turn on [Hangouts in Gmail](https://support.google.com/hangouts/answer/3115176?hl=en).

Disable `Get notified about invitations` and enable `Everyone else: contact you directly` in the [Customize invitation settings](https://support.google.com/hangouts/answer/3111929?p=circles&rd=1).

Add a [cool picture](https://support.google.com/plus/answer/1057172?hl=en) and update your bot's name.
