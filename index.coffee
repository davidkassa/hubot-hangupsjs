HangupsJS = require './src/hangupsjs'

module.exports = exports = {
  HangupsJS
}

exports.use = (robot) ->
  new HangupsJS robot