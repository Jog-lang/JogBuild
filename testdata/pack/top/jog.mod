# top: a library with one path dependency, for pack
module top
version 1.0.0
kind library
jog 0.0.1

require base ../base    # pack rewrites this line

export shapes
